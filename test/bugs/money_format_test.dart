// BUSINESS_RULES §1: "₹50, ₹49.99" - paise are shown only when there are any.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/utils/money.dart';

void main() {
  test('formatMoney shows paise only when there are any', () {
    expect(formatMoney(5000), '₹50');
    expect(formatMoney(4999), '₹49.99');
    expect(formatMoney(1999), '₹19.99');
    expect(formatMoney(5005), '₹50.05');
    expect(formatMoney(0), '₹0');
  });
}
