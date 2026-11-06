// Prices with paise (₹19.99) were converted to the wrong number of paise.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/utils/money.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/checkout/data/order_api.dart';

import '../helpers/test_harness.dart';

void main() {
  test('rupeesToPaise is exact for prices with paise', () {
    expect(rupeesToPaise(19.99), 1999);
    expect(rupeesToPaise(79.99), 7999);
    expect(rupeesToPaise(69.99), 6999);
    expect(rupeesToPaise(74.99), 7499);
    expect(rupeesToPaise(17.99), 1799);
    expect(rupeesToPaise(49), 4900);
  });

  test('a ₹19.99 tomato from the catalog can be ordered', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final page =
        await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits');
    final tomato = page.items.firstWhere((p) => p.id == 'fruits-03');
    expect(tomato.pricePaise, h.server.product('fruits-03').pricePaise);

    final cart = Cart(lines: [CartLine.fromProduct(tomato)]);
    final order = await h
        .read(orderApiProvider)
        .placeOrder(cart, CartPricing.compute(cart, AppConfig.defaults()));
    expect(order.items.single.unitPricePaise, 1999);
  });
}
