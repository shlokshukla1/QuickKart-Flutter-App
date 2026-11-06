import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/providers.dart';
import '../domain/product.dart';
import 'catalog_api.dart';
import 'catalog_cache.dart';

final catalogApiProvider = Provider<CatalogApi>(
  (ref) => CatalogApi(ref.watch(apiClientProvider)),
);

final catalogCacheProvider = Provider<CatalogCache>(
  (ref) => CatalogCache(ref.watch(keyValueStoreProvider)),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(
    ref.watch(catalogApiProvider),
    ref.watch(catalogCacheProvider),
  ),
);

/// Special category id used for the "All products" listing.
const String kAllProductsCategory = 'all';

/// Network-first catalog with an offline fallback.
class CatalogRepository {
  CatalogRepository(this._api, this._cache);

  final CatalogApi _api;
  final CatalogCache _cache;

  Future<List<Category>> getCategories() => _api.getCategories();

  /// Returns one page of products for [categoryId]
  /// ([kAllProductsCategory] for everything).
  ///
  /// When the network is unavailable the last cached copy of the page is
  /// returned with `fromCache: true`.
  Future<CatalogPage> getPage({
    required String categoryId,
    String? cursor,
    int limit = 10,
  }) async {
    // FIX (offline wrong category): the key had no category, so every
    // category's first page overwrote the same entry and offline "Dairy"
    // could show "All products" or another category.
    final cacheKey = 'page.$categoryId.${cursor ?? 'first'}';
    try {
      final page = await _api.getProducts(
        categoryId: categoryId == kAllProductsCategory ? null : categoryId,
        cursor: cursor,
        limit: limit,
      );
      await _cache.write(cacheKey, page);
      return page;
    } on ApiException catch (e) {
      if (!e.isTransient) rethrow;
      final cached = await _cache.read(cacheKey);
      if (cached == null) rethrow;
      return cached.page.copyWith(fromCache: true);
    }
  }

  Future<List<Product>> search(String query) => _api.search(query);

  Future<CatalogPage> getDeals({int limit = 10}) =>
      _api.getProducts(dealsOnly: true, limit: limit);
}
