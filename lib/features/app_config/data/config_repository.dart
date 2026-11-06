import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/app_config.dart';

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(
    ref.watch(apiClientProvider),
    ref.watch(keyValueStoreProvider),
    remoteUpdates: () => ref.read(mockServerProvider).configUpdates,
  ),
);

/// Loads remote config (think: Firebase Remote Config).
class ConfigRepository {
  ConfigRepository(
    this._client,
    this._store, {
    required Stream<int> Function() remoteUpdates,
  }) : _remoteUpdates = remoteUpdates;

  final ApiClient _client;
  final KeyValueStore _store;
  final Stream<int> Function() _remoteUpdates;

  /// Last known good config values, as fetched from the server.
  static const _cacheKey = 'remote_config.v1';

  /// Fires (with the new config version) every time config is published
  /// from the console. Equivalent to Firebase's `onConfigUpdated`.
  Stream<int> get remoteUpdates => _remoteUpdates();

  /// Fetches the latest config. Never throws.
  ///
  /// F2: on success the raw values are persisted; on any failure (offline,
  /// timeout, 5xx, malformed response) the last known good config is used,
  /// and with nothing cached the safe defaults.
  Future<AppConfig> load() async {
    try {
      final json = await _client.get('/v1/config') as Map<String, dynamic>;
      final values = (json['values'] as Map).cast<String, Object?>();
      final config = AppConfig.fromValues(values);
      await _saveCache(values);
      return config;
    } catch (_) {
      // Deliberately broad: a bad network or a bad payload must never stop
      // the app from starting (BUSINESS_RULES §7).
      return await loadCached() ?? AppConfig.defaults();
    }
  }

  /// The last config fetched successfully, or null if there is none.
  /// Used at startup so the first frame never waits for the network.
  Future<AppConfig?> loadCached() async {
    try {
      final raw = await _store.getString(_cacheKey);
      if (raw == null) return null;
      final values = (jsonDecode(raw) as Map).cast<String, Object?>();
      return AppConfig.fromValues(values);
    } catch (_) {
      return null; // corrupt cache = no cache
    }
  }

  Future<void> _saveCache(Map<String, Object?> values) async {
    try {
      await _store.setString(_cacheKey, jsonEncode(values));
    } catch (_) {
      // Failing to cache must not fail the load.
    }
  }
}
