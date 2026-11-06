// BUSINESS_RULES §2: orders of ₹199 *or more* get free delivery.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';

Cart cartOf(int paise) => Cart(lines: [
      CartLine(
        productId: 'a',
        name: 'a',
        emoji: '',
        unit: '',
        unitPricePaise: paise,
        quantity: 1,
        maxPerOrder: 5,
      ),
    ]);

void main() {
  final config = AppConfig.defaults(); // ₹25 fee, free from ₹199

  test('exactly ₹199 gets free delivery', () {
    final p = CartPricing.compute(cartOf(19900), config);
    expect(p.deliveryFeePaise, 0);
    expect(p.totalPaise, 19900);
    expect(p.amountForFreeDeliveryPaise, 0);
  });

  test('₹198.99 still pays the fee', () {
    final p = CartPricing.compute(cartOf(19899), config);
    expect(p.deliveryFeePaise, 2500);
    expect(p.amountForFreeDeliveryPaise, 1);
  });
}
