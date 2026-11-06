// Offline, a category must show its own saved products, not another one's.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';

import '../helpers/test_harness.dart';

void main() {
  test('offline category page comes from that category\'s cache', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final repo = h.read(catalogRepositoryProvider);
    await repo.getPage(categoryId: 'beverages'); // user opened Beverages
    await repo.getPage(categoryId: kAllProductsCategory); // then Home

    h.server.chaos.offline = true;
    final page = await repo.getPage(categoryId: 'beverages');

    expect(page.fromCache, isTrue);
    expect(page.items, isNotEmpty);
    expect(page.items.map((p) => p.categoryId), everyElement('beverages'));
  });
}
