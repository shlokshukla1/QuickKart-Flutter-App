import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_exceptions.dart';
import 'package:quickkart/features/cart/application/cart_reconciler.dart';
import 'package:quickkart/features/cart/data/coupon_api.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/cart/domain/reconciliation.dart';

import '../helpers/catalog_helpers.dart';
import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;
  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  CartLine lineOf(String id, {int qty = 1}) =>
      CartLine.fromProduct(serverProduct(h, id), quantity: qty);

  Future<ReconciliationResult> reconcile(Cart cart) =>
      h.read(cartReconcilerProvider).reconcile(cart);

  test('an unchanged cart returns an equal cart and no changes', () async {
    final coupon = await h.read(couponApiProvider).validate('SAVE10');
    final cart = Cart(
        lines: [lineOf('fruits-01', qty: 2), lineOf('dairy-03')],
        coupon: coupon);

    final r = await reconcile(cart);

    expect(r.changes, isEmpty);
    expect(r.cart, cart);
    expect(r.requiresUserReview, isFalse);
  });

  test('an empty cart is unchanged', () async {
    final r = await reconcile(const Cart.empty());
    expect(r.changes, isEmpty);
    expect(r.cart, const Cart.empty());
  });

  test('price increase is updated and needs review', () async {
    final cart = Cart(lines: [lineOf('fruits-01')]);
    h.server.setPrice('fruits-01', 5900);

    final r = await reconcile(cart);

    expect(r.cart.lines.single.unitPricePaise, 5900);
    final change = r.changes.single as PriceChanged;
    expect(change.oldPricePaise, 4900);
    expect(change.newPricePaise, 5900);
    expect(r.requiresUserReview, isTrue);
  });

  test('price drop is applied without review', () async {
    final cart = Cart(lines: [lineOf('fruits-01')]);
    h.server.setPrice('fruits-01', 3900);

    final r = await reconcile(cart);

    expect(r.cart.lines.single.unitPricePaise, 3900);
    expect(r.changes.single, isA<PriceChanged>());
    expect(r.requiresUserReview, isFalse);
  });

  test('out-of-stock line is removed', () async {
    final cart = Cart(lines: [lineOf('fruits-01'), lineOf('dairy-03')]);
    h.server.setStock('fruits-01', 0);

    final r = await reconcile(cart);

    expect(r.cart.lines.map((l) => l.productId), ['dairy-03']);
    expect((r.changes.single as OutOfStock).productId, 'fruits-01');
    expect(r.requiresUserReview, isTrue);
  });

  test('quantity is capped by stock and maxPerOrder is refreshed', () async {
    final cart = Cart(lines: [lineOf('fruits-01', qty: 4)]);
    h.server.setStock('fruits-01', 2);

    final r = await reconcile(cart);

    final line = r.cart.lines.single;
    expect(line.quantity, 2);
    expect(line.maxPerOrder, 2);
    final change = r.changes.single as QuantityReduced;
    expect(change.requestedQuantity, 4);
    expect(change.availableQuantity, 2);
  });

  test('quantity is capped by a lowered per-order limit', () async {
    final cart = Cart(lines: [lineOf('fruits-01', qty: 5)]);
    h.server.setMaxPerOrder('fruits-01', 3);

    final r = await reconcile(cart);

    expect(r.cart.lines.single.quantity, 3);
    expect(r.cart.lines.single.maxPerOrder, 3);
    expect(r.changes.single, isA<QuantityReduced>());
  });

  test('a raised limit refreshes maxPerOrder without a change', () async {
    final line = lineOf('fruits-01').copyWith(maxPerOrder: 2);
    final r = await reconcile(Cart(lines: [line]));
    expect(r.cart.lines.single.maxPerOrder,
        h.server.product('fruits-01').maxPerOrder);
    expect(r.changes, isEmpty);
  });

  test('discontinued product is removed', () async {
    final cart = Cart(lines: [lineOf('fruits-01'), lineOf('dairy-03')]);
    h.server.setActive('dairy-03', false);

    final r = await reconcile(cart);

    expect(r.cart.lines.map((l) => l.productId), ['fruits-01']);
    expect((r.changes.single as ProductUnavailable).productId, 'dairy-03');
  });

  test('an unknown product id is treated as no longer sold', () async {
    final cart = Cart(lines: const [
      CartLine(
          productId: 'nope-99',
          name: 'ghost',
          emoji: '',
          unit: '',
          unitPricePaise: 100,
          quantity: 1,
          maxPerOrder: 1),
    ]);
    final r = await reconcile(cart);
    expect(r.cart.isEmpty, isTrue);
    expect(r.changes.single, isA<ProductUnavailable>());
  });

  test('expired coupon is removed', () async {
    final coupon = await h.read(couponApiProvider).validate('SAVE10');
    final cart = Cart(lines: [lineOf('fruits-01')], coupon: coupon);
    h.server.expireCoupon('SAVE10');

    final r = await reconcile(cart);

    expect(r.cart.coupon, isNull);
    final change = r.changes.single as CouponRemoved;
    expect(change.code, 'SAVE10');
    expect(change.reason, 'EXPIRED');
  });

  test('unknown coupon is removed', () async {
    final cart = Cart(
      lines: [lineOf('fruits-01')],
      coupon: Coupon(
        code: 'NOPE',
        type: CouponType.flat,
        value: 100,
        minOrderPaise: 0,
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    final r = await reconcile(cart);
    expect(r.cart.coupon, isNull);
    expect((r.changes.single as CouponRemoved).reason, 'NOT_FOUND');
  });

  test('coupon below its minimum stays, refreshed with server rules', () async {
    final real = await h.read(couponApiProvider).validate('SAVE10');
    final stale = Coupon(
      code: real.code,
      type: real.type,
      value: 5, // outdated rule
      maxDiscountPaise: real.maxDiscountPaise,
      minOrderPaise: real.minOrderPaise,
      expiresAt: real.expiresAt,
    );
    final cart = Cart(lines: [lineOf('fruits-01')], coupon: stale); // ₹49

    final r = await reconcile(cart);

    expect(r.cart.coupon, real);
    expect(r.changes, isEmpty);
  });

  test('order is preserved and every issue is reported', () async {
    final coupon = await h.read(couponApiProvider).validate('FLAT50');
    final ids = ['fruits-01', 'fruits-04', 'dairy-03', 'snacks-00', 'beverages-00'];
    final cart = Cart(lines: [for (final id in ids) lineOf(id, qty: 2)], coupon: coupon);
    h.server.simulateCartConflicts(ids.take(4).toList(), couponCode: 'FLAT50');

    final r = await reconcile(cart);

    // 1st price up, 2nd out of stock, 3rd only 1 left, 4th discontinued.
    expect(r.cart.lines.map((l) => l.productId),
        ['fruits-01', 'dairy-03', 'beverages-00']);
    expect(r.changes.whereType<PriceChanged>().single.productId, 'fruits-01');
    expect(r.changes.whereType<OutOfStock>().single.productId, 'fruits-04');
    expect(r.changes.whereType<QuantityReduced>().single.productId, 'dairy-03');
    expect(r.changes.whereType<ProductUnavailable>().single.productId,
        'snacks-00');
    expect(r.changes.whereType<CouponRemoved>().single.code, 'FLAT50');
    expect(r.changes, hasLength(5));
  });

  test('more than 50 lines are fetched in chunks', () async {
    final ids = h.server.productIds.take(55).toList();
    final cart = Cart(lines: [for (final id in ids) lineOf(id)]);
    final r = await reconcile(cart);
    expect(r.cart.lines, hasLength(
        ids.where((id) => h.server.product(id).stock > 0).length));
  });

  test('offline throws and does not return a partial cart', () async {
    final cart = Cart(lines: [lineOf('fruits-01')]);
    h.server.chaos.offline = true;
    await expectLater(reconcile(cart), throwsA(isA<NetworkException>()));
  });
}
