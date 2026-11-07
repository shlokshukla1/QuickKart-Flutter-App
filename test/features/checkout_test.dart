import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/application/cart_review_controller.dart';
import 'package:quickkart/features/cart/data/coupon_api.dart';
import 'package:quickkart/features/cart/domain/reconciliation.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';

import '../helpers/catalog_helpers.dart';
import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;
  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  CartController cart() => h.read(cartControllerProvider.notifier);
  CheckoutController checkout() => h.read(checkoutControllerProvider.notifier);
  int orderPosts() => h.server.requestLog
      .where((r) => r.method == 'POST' && r.path == '/v1/orders')
      .length;

  test('cart conflicts: needs review, no order, then the second tap orders',
      () async {
    final ids = ['fruits-01', 'fruits-04', 'dairy-03', 'snacks-00'];
    for (final id in ids) {
      await cart().add(serverProduct(h, id));
      await cart().increment(id);
    }
    await cart()
        .applyCoupon(await h.read(couponApiProvider).validate('FLAT50'));
    h.server.simulateCartConflicts(ids, couponCode: 'FLAT50');

    final first = await checkout().placeOrder();

    expect(first, isA<CheckoutNeedsReview>());
    expect(h.server.orderCount, 0);
    expect(orderPosts(), 0,
        reason: 'never send an order the user has not seen');
    final review = (first as CheckoutNeedsReview).reconciliation;
    expect(h.read(cartControllerProvider), review.cart,
        reason: 'contract: cart already updated');
    expect(h.read(cartReviewProvider)!.changes, hasLength(5));

    final second = await checkout().placeOrder();
    expect(second, isA<CheckoutSuccess>());
    expect(h.server.orderCount, 1);
    expect(h.read(cartControllerProvider).isEmpty, isTrue);
  });

  test('a price drop is applied silently and the order goes through', () async {
    await cart().add(serverProduct(h, 'fruits-01'));
    h.server.setPrice('fruits-01', 3900);

    final result = await checkout().placeOrder();

    expect(result, isA<CheckoutSuccess>());
    expect((result as CheckoutSuccess).order.items.single.unitPricePaise, 3900);
  });

  test('a price increase is never charged without review', () async {
    await cart().add(serverProduct(h, 'fruits-01'));
    h.server.setPrice('fruits-01', 5900);

    final result = await checkout().placeOrder();

    expect(result, isA<CheckoutNeedsReview>());
    final change = (result as CheckoutNeedsReview).reconciliation.changes.single
        as PriceChanged;
    expect(change.newPricePaise, 5900);
    expect(h.server.orderCount, 0);
  });

  test('store closed (known by the app): failure without any request',
      () async {
    await cart().add(serverProduct(h, 'fruits-01'));
    final sub = h.container.listen(appConfigControllerProvider, (_, __) {});
    addTearDown(sub.close);
    h.server.publishConfig({'store_open': false});
    await pumpEventQueue();
    expect(h.read(appConfigControllerProvider).storeOpen, isFalse);
    final before = h.server.requestLog.length;

    final result = await checkout().placeOrder();

    expect(result, isA<CheckoutFailure>());
    expect((result as CheckoutFailure).message,
        h.server.configValues['store_closed_message']);
    expect(h.server.requestLog.length, before);
  });

  test('store closed on the server but not yet known: honest failure',
      () async {
    await cart().add(serverProduct(h, 'fruits-01'));
    h.server.publishConfig({'store_open': false}); // nobody listening

    final result = await checkout().placeOrder();

    expect(result, isA<CheckoutFailure>());
    expect(h.server.orderCount, 0);
    expect(h.read(appConfigControllerProvider).storeOpen, isFalse,
        reason: 'config refreshed after STORE_CLOSED');
  });

  test('offline: clear message, cart kept, no order', () async {
    await cart().add(serverProduct(h, 'fruits-01'));
    h.server.chaos.offline = true;

    final result = await checkout().placeOrder();

    expect(result, isA<CheckoutFailure>());
    expect((result as CheckoutFailure).message, CheckoutMessages.offline);
    expect(result.canRetry, isTrue);
    expect(h.read(cartControllerProvider).isEmpty, isFalse);
  });

  test('a cart built offline is reconciled when checked out online', () async {
    await cart().add(serverProduct(h, 'fruits-01'));
    h.server.chaos.offline = true;
    await checkout().placeOrder();
    h.server.setStock('fruits-01', 0); // sold out while offline
    h.server.chaos.offline = false;

    final result = await checkout().placeOrder();

    expect(result, isA<CheckoutNeedsReview>());
    expect(h.read(cartControllerProvider).isEmpty, isTrue);
  });

  test('lost response on the last item in stock: retry returns that order',
      () async {
    h.server.setStock('fruits-01', 1);
    await cart().add(serverProduct(h, 'fruits-01'));
    h.server.chaos.loseNextOrderResponses = 2;

    final first = await checkout().placeOrder();
    expect(first, isA<CheckoutFailure>());
    expect(h.server.product('fruits-01').stock, 0, reason: 'order was created');

    final second = await checkout().placeOrder();
    expect(second, isA<CheckoutSuccess>(),
        reason: 'must not say "out of stock" for the user\'s own order');
    expect(h.server.orderCount, 1);
  });

  test('opening the cart reconciles it and shows the changes', () async {
    await cart().add(serverProduct(h, 'fruits-01'));
    h.server.setActive('fruits-01', false);

    await h.read(cartReviewProvider.notifier).syncWithServer();

    expect(h.read(cartControllerProvider).isEmpty, isTrue);
    expect(
        h.read(cartReviewProvider)!.changes.single, isA<ProductUnavailable>());
  });

  test('opening the cart applies a price drop silently', () async {
    await cart().add(serverProduct(h, 'fruits-01'));
    h.server.setPrice('fruits-01', 3900);

    await h.read(cartReviewProvider.notifier).syncWithServer();

    expect(h.read(cartControllerProvider).lines.single.unitPricePaise, 3900);
    expect(h.read(cartReviewProvider), isNull);
  });

  test('opening the cart offline keeps it untouched', () async {
    await cart().add(serverProduct(h, 'fruits-01'));
    final before = h.read(cartControllerProvider);
    h.server.chaos.offline = true;

    await h.read(cartReviewProvider.notifier).syncWithServer();

    expect(h.read(cartControllerProvider), before);
    expect(h.read(cartReviewProvider), isNull);
  });
}
