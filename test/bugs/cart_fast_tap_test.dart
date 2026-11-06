// Fast taps on "+" must not lose increments.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/cart_storage.dart';

import '../helpers/catalog_helpers.dart';
import '../helpers/test_harness.dart';

void main() {
  test('two quick increments add two units, in memory and on disk', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final cart = h.read(cartControllerProvider.notifier);
    final eggs = serverProduct(h, 'dairy-03');
    await cart.add(eggs);

    // Second tap arrives before the first save has finished.
    await Future.wait([cart.increment(eggs.id), cart.increment(eggs.id)]);

    expect(h.read(cartControllerProvider).quantityOf(eggs.id), 3);
    final saved = await h.read(cartStorageProvider).load();
    expect(saved.quantityOf(eggs.id), 3);
  });
}
