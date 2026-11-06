// Products from the legacy catalog service send `"mrp": null` and
// `"stock": "120"` (a string). They crashed the Dairy list and search.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/catalog/presentation/catalog_controller.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;
  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('the Dairy page (with legacy products) loads', () async {
    final page =
        await h.read(catalogRepositoryProvider).getPage(categoryId: 'dairy');
    final milk = page.items.firstWhere((p) => p.id == 'dairy-00');
    final server = h.server.product('dairy-00');
    expect(milk.stock, server.stock);
    expect(milk.pricePaise, server.pricePaise);
    expect(milk.mrpPaise, milk.pricePaise, reason: 'no MRP = no discount');
    expect(milk.hasDiscount, isFalse);
  });

  test('the Dairy screen leaves the loading state', () async {
    final provider = catalogControllerProvider('dairy');
    final sub = h.container.listen(provider, (_, __) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    expect(h.read(provider).isLoadingFirstPage, isFalse);
    expect(h.read(provider).items, isNotEmpty);
  });

  test('searching "milk" works', () async {
    final results = await h.read(catalogRepositoryProvider).search('milk');
    expect(results.map((p) => p.id), contains('dairy-00'));
  });
}
