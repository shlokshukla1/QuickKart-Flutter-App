import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../data/catalog_repository.dart';
import '../domain/product.dart';

class CatalogState {
  const CatalogState({
    this.items = const [],
    this.nextCursor,
    this.hasMore = true,
    this.isLoadingFirstPage = false,
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.fromCache = false,
    this.errorMessage,
  });

  final List<Product> items;
  final String? nextCursor;
  final bool hasMore;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool isRefreshing;

  /// True when the visible data came from the offline cache.
  final bool fromCache;
  final String? errorMessage;

  CatalogState copyWith({
    List<Product>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? hasMore,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? isRefreshing,
    bool? fromCache,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CatalogState(
      items: items ?? this.items,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      hasMore: hasMore ?? this.hasMore,
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      fromCache: fromCache ?? this.fromCache,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Paginated product list. The family argument is a category id, or
/// [kAllProductsCategory].
final catalogControllerProvider =
    NotifierProvider.family<CatalogController, CatalogState, String>(
  CatalogController.new,
);

class CatalogController extends FamilyNotifier<CatalogState, String> {
  static const pageSize = 10;

  CatalogRepository get _repo => ref.read(catalogRepositoryProvider);

  // FIX (duplicate pages): bumped on every first-page load / refresh. A
  // loadMore that started before a refresh sees a different number when it
  // finishes and drops its page instead of appending it to the new list.
  int _generation = 0;

  @override
  CatalogState build(String categoryId) {
    Future.microtask(_loadFirstPage);
    return const CatalogState(isLoadingFirstPage: true);
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    try {
      final page = await _repo.getPage(categoryId: arg, limit: pageSize);
      if (generation != _generation) return;
      state = CatalogState(
        items: page.items,
        nextCursor: page.nextCursor,
        hasMore: page.nextCursor != null,
        fromCache: page.fromCache,
      );
    } on ApiException catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(
        isLoadingFirstPage: false,
        errorMessage: e.message,
      );
    }
  }

  /// Retries the first page after an error.
  Future<void> retry() async {
    state = const CatalogState(isLoadingFirstPage: true);
    await _loadFirstPage();
  }

  /// Loads the next page. Called by the UI when the user scrolls near the
  /// end of the list.
  Future<void> loadMore() async {
    // FIX (duplicate pages): the scroll listener fires on every pixel, so
    // the same page was requested and appended many times. Also never
    // "load more" before the first page exists (cursor null = page 1 again).
    if (!state.hasMore ||
        state.isLoadingMore ||
        state.isLoadingFirstPage ||
        state.isRefreshing ||
        state.nextCursor == null) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final page = await _repo.getPage(
        categoryId: arg,
        cursor: state.nextCursor,
        limit: pageSize,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        hasMore: page.nextCursor != null,
        isLoadingMore: false,
        fromCache: state.fromCache || page.fromCache,
      );
    } on ApiException catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(isLoadingMore: false, errorMessage: e.message);
    }
  }

  /// Pull-to-refresh: reloads from the first page.
  Future<void> refresh() async {
    final generation = ++_generation;
    state = state.copyWith(
        isRefreshing: true, isLoadingMore: false, clearError: true);
    try {
      final page = await _repo.getPage(categoryId: arg, limit: pageSize);
      if (generation != _generation) return;
      state = CatalogState(
        items: page.items,
        nextCursor: page.nextCursor,
        hasMore: page.nextCursor != null,
        fromCache: page.fromCache,
      );
    } on ApiException catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(isRefreshing: false, errorMessage: e.message);
    }
  }
}

final categoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(catalogRepositoryProvider).getCategories(),
);
