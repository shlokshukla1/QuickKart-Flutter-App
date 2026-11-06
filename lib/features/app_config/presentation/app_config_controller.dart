import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/config_repository.dart';
import '../domain/app_config.dart';

/// The config the app is currently using. Hydrated in `main.dart` before the
/// first frame.
final appConfigControllerProvider =
    NotifierProvider<AppConfigController, AppConfig>(AppConfigController.new);

class AppConfigController extends Notifier<AppConfig> {
  /// Incremented by every refresh; only the newest refresh may set state,
  /// so a slow older fetch can't overwrite a newer config.
  int _refreshId = 0;
  bool _disposed = false;

  @override
  AppConfig build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // F2 live updates: refetch whenever config is published from the
    // console (like Firebase's onConfigUpdated). Works without any widget,
    // and the subscription is cancelled when the provider is disposed, so
    // nothing leaks.
    final sub = ref
        .read(configRepositoryProvider)
        .remoteUpdates
        .listen((_) => unawaited(refresh()));
    ref.onDispose(sub.cancel);
    return AppConfig.defaults();
  }

  /// Used at startup with the config loaded during bootstrap.
  void hydrate(AppConfig config) => state = config;

  /// Fetches the latest config. Never throws (the repository falls back to
  /// the cached / default config).
  Future<void> refresh() async {
    final id = ++_refreshId;
    final config = await ref.read(configRepositoryProvider).load();
    if (!_disposed && id == _refreshId) state = config;
  }
}
