// QK-101: "Items I removed come back".
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/cart_storage.dart';
import 'package:quickkart/features/cart/data/coupon_api.dart';

import '../helpers/catalog_helpers.dart';
import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;
  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('remove, decrement and removeCoupon survive an app restart', () async {
    final cart = h.read(cartControllerProvider.notifier);
    final chips = serverProduct(h, 'snacks-00');
    final eggs = serverProduct(h, 'dairy-03');
    await cart.add(chips);
    await cart.add(eggs);
    await cart.add(eggs);
    await cart.applyCoupon(await h.read(couponApiProvider).validate('SAVE10'));

    await cart.remove(chips.id);
    await cart.decrement(eggs.id);
    await cart.removeCoupon();

    // Restart: same device storage, fresh app state (like main.dart).
    final restarted = h.restart();
    addTearDown(restarted.dispose);
    final saved = await restarted.read(cartStorageProvider).load();
    restarted.read(cartControllerProvider.notifier).hydrate(saved);
    final after = restarted.read(cartControllerProvider);

    expect(after.lineFor(chips.id), isNull, reason: 'removed chips came back');
    expect(after.quantityOf(eggs.id), 1, reason: 'decrement was lost');
    expect(after.coupon, isNull, reason: 'removed coupon came back');
    expect(after.totalQuantity, 1, reason: 'cart badge count');
  });
}
