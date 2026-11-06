import 'package:quickkart/features/catalog/domain/product.dart';

import 'test_harness.dart';

/// Builds a domain [Product] straight from the server's admin snapshot, so
/// cart / checkout tests don't depend on the catalog JSON parsing.
Product serverProduct(TestHarness h, String id) {
  final p = h.server.product(id);
  return Product(
    id: p.id,
    name: p.name,
    categoryId: p.categoryId,
    emoji: '🛒',
    unit: '',
    pricePaise: p.pricePaise,
    mrpPaise: p.mrpPaise,
    stock: p.stock,
    maxPerOrder: p.maxPerOrder,
  );
}
