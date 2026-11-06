import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/storage/key_value_store.dart';
import 'features/app_config/data/config_repository.dart';
import 'features/app_config/presentation/app_config_controller.dart';
import 'features/app_config/presentation/update_gate.dart';
import 'features/cart/application/cart_controller.dart';
import 'features/cart/data/cart_storage.dart';
import 'mock_server/mock_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final store = SharedPrefsKeyValueStore(prefs);

  // The "backend". Its data is persisted on the device.
  final server = await MockServer.open(store);

  final versionOverride = await store.getString(kDebugAppVersionKey);

  final container = ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      mockServerProvider.overrideWithValue(server),
      if (versionOverride != null && versionOverride.isNotEmpty)
        appVersionProvider.overrideWithValue(versionOverride),
    ],
  );

  // Restore the cart and config before the first frame.
  final cart = await container.read(cartStorageProvider).load();
  container.read(cartControllerProvider.notifier).hydrate(cart);

  // F2: start from the last known good config (instant, works offline),
  // then fetch the latest in the background. The first frame never waits
  // for a slow network; a force update still applies within seconds.
  final configRepo = container.read(configRepositoryProvider);
  final configController = container.read(appConfigControllerProvider.notifier);
  final cached = await configRepo.loadCached();
  if (cached != null) {
    configController.hydrate(cached);
    unawaited(configController.refresh());
  } else {
    // First launch: nothing cached yet, so wait for the fetch (load() never
    // throws and falls back to defaults offline).
    configController.hydrate(await configRepo.load());
  }

  container
      .read(dismissedUpdateVersionProvider.notifier)
      .hydrate(await store.getString(kDismissedUpdateVersionKey));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const QuickKartApp(),
    ),
  );
}
