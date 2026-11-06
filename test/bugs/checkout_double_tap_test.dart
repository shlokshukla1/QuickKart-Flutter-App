// A double tap on "Place order" must create one order.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';

import '../helpers/catalog_helpers.dart';
import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;
  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('two placeOrder calls at the same time create one order', () async {
    await h
        .read(cartControllerProvider.notifier)
        .add(serverProduct(h, 'fruits-01'));
    final checkout = h.read(checkoutControllerProvider.notifier);

    final results = await Future.wait([checkout.placeOrder(), checkout.placeOrder()]);

    expect(results, everyElement(isA<CheckoutSuccess>()));
    expect(h.server.orderCount, 1);
  });
}
