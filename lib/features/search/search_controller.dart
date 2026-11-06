import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exceptions.dart';
import '../catalog/data/catalog_repository.dart';
import '../catalog/domain/product.dart';

class SearchState {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  /// The query the visible [results] belong to.
  final String query;
  final List<Product> results;
  final bool isLoading;
  final String? errorMessage;
}

final searchControllerProvider =
    NotifierProvider<ProductSearchController, SearchState>(
  ProductSearchController.new,
);

class ProductSearchController extends Notifier<SearchState> {
  // FIX (search race): one request per keystroke; responses can arrive out
  // of order. Only the response of the latest request may update the
  // screen, otherwise "mi" results could overwrite "milk" results.
  int _latestRequest = 0;

  @override
  SearchState build() => const SearchState();

  /// Called on every keystroke of the search field.
  Future<void> search(String query) async {
    final request = ++_latestRequest;
    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }
    state = SearchState(query: query, results: state.results, isLoading: true);
    try {
      final results =
          await ref.read(catalogRepositoryProvider).search(query.trim());
      if (request != _latestRequest) return; // a newer search is running
      state = SearchState(query: query, results: results);
    } on ApiException catch (e) {
      if (request != _latestRequest) return;
      state = SearchState(query: query, errorMessage: e.message);
    }
  }

  void clear() {
    _latestRequest++; // ignore any search still in flight
    state = const SearchState();
  }
}
