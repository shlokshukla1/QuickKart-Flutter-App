// QK-102: "Prices don't update until I restart the app" + "My orders doesn't
// show the order I just placed".
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/catalog/presentation/catalog_controller.dart';
import 'package:quickkart/features/checkout/data/order_api.dart';
import 'package:quickkart/features/orders/data/order_tracking_repository.dart';

import '../helpers/catalog_helpers.dart';
import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;
  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('pull-to-refresh shows a price that changed on the server', () async {
    final provider = catalogControllerProvider('fruits');
    final sub = h.container.listen(provider, (_, __) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    int bananaPrice() =>
        h.read(provider).items.firstWhere((p) => p.id == 'fruits-01').pricePaise;
    final before = bananaPrice();

    h.server.setPrice('fruits-01', before + 1000);
    await h.read(provider.notifier).refresh();

    expect(bananaPrice(), before + 1000);
  });

  test('My orders shows an order placed after it was first opened', () async {
    final sub = h.container.listen(ordersProvider, (_, __) {});
    expect(await h.read(ordersProvider.future), isEmpty);
    sub.close(); // user leaves "My orders"
    await pumpEventQueue();

    final cart = Cart(lines: [CartLine.fromProduct(serverProduct(h, 'fruits-01'))]);
    await h
        .read(orderApiProvider)
        .placeOrder(cart, CartPricing.compute(cart, AppConfig.defaults()));

    // User opens "My orders" again.
    expect(await h.read(ordersProvider.future), hasLength(1));
  });
}
