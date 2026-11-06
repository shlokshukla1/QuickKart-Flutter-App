// "Charged twice for the same order on slow networks": a lost response
// (the server created the order, the app saw a timeout) must not lead to a
// second order.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/cart_storage.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';

import '../helpers/catalog_helpers.dart';
import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;
  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  Future<void> addBanana() =>
      h.read(cartControllerProvider.notifier).add(serverProduct(h, 'fruits-01'));

  test('lost response + automatic retry creates exactly one order', () async {
    await addBanana();
    h.server.chaos.loseNextOrderResponses = 1;

    final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutSuccess>());
    expect(h.server.orderCount, 1);
  });

  test('tapping "Place order" again after a timeout creates no second order',
      () async {
    await addBanana();
    h.server.chaos.loseNextOrderResponses = 2; // first try + its retry
    final checkout = h.read(checkoutControllerProvider.notifier);

    final first = await checkout.placeOrder();
    expect(first, isA<CheckoutFailure>());
    expect((first as CheckoutFailure).message, contains('My orders'),
        reason: 'a timeout must not claim the order failed');
    expect(h.server.orderCount, 1);

    final second = await checkout.placeOrder();
    expect(second, isA<CheckoutSuccess>());
    expect(h.server.orderCount, 1);
  });

  test('...also after an app restart', () async {
    await addBanana();
    h.server.chaos.loseNextOrderResponses = 2;
    await h.read(checkoutControllerProvider.notifier).placeOrder();
    expect(h.server.orderCount, 1);

    final restarted = h.restart();
    addTearDown(restarted.dispose);
    restarted
        .read(cartControllerProvider.notifier)
        .hydrate(await restarted.read(cartStorageProvider).load());
    final result =
        await restarted.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutSuccess>());
    expect(h.server.orderCount, 1);
  });
}
