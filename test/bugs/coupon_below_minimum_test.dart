// BUSINESS_RULES §3: below the minimum the coupon stays applied, gives no
// discount, and "the customer can still place the order".
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/coupon_api.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';

import '../helpers/catalog_helpers.dart';
import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;
  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('an order below the coupon minimum can still be placed', () async {
    final cart = h.read(cartControllerProvider.notifier);
    await cart.add(serverProduct(h, 'fruits-01')); // ₹49 < SAVE10 min ₹199
    await cart.applyCoupon(await h.read(couponApiProvider).validate('SAVE10'));

    final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutSuccess>());
    expect((result as CheckoutSuccess).order.discountPaise, 0);
  });
}
