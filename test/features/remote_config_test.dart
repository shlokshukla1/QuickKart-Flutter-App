import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/mock_server/mock_server.dart';

import '../helpers/test_harness.dart';

void main() {
  group('ConfigRepository.load', () {
    test('online: returns the server config', () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      h.server.publishConfig({'store_open': false, 'delivery_fee_paise': 3000});

      final config = await h.read(configRepositoryProvider).load();

      expect(config.storeOpen, isFalse);
      expect(config.deliveryFeePaise, 3000);
    });

    test('offline with nothing cached: defaults, never throws', () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      h.server.chaos.offline = true;

      final config = await h.read(configRepositoryProvider).load();

      expect(config.storeOpen, isTrue);
      expect(config.minSupportedVersion, '0.0.0');
    });

    test('offline after a successful load: last known good config', () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      h.server.publishConfig({'store_open': false, 'latest_version': '1.9.0'});
      await h.read(configRepositoryProvider).load();

      // App restart while offline.
      final restarted = h.restart();
      addTearDown(restarted.dispose);
      h.server.chaos.offline = true;
      final config = await restarted.read(configRepositoryProvider).load();

      expect(config.storeOpen, isFalse);
      expect(config.latestVersion, '1.9.0');
    });

    test('a 5xx keeps the last known good config', () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      h.server.publishConfig({'delivery_fee_paise': 1234});
      await h.read(configRepositoryProvider).load();
      h.server.chaos.failureRate = 1;

      final config = await h.read(configRepositoryProvider).load();

      expect(config.deliveryFeePaise, 1234);
    });

    test('a corrupt cache entry is ignored', () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.store.setString('remote_config.v1', '{not json');
      h.server.chaos.offline = true;

      final config = await h.read(configRepositoryProvider).load();
      expect(config.storeOpen, isTrue);
      expect(await h.read(configRepositoryProvider).loadCached(), isNull);
    });
  });

  group('AppConfigController', () {
    test('applies published config within moments, no restart', () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final sub = h.container.listen(appConfigControllerProvider, (_, __) {});
      addTearDown(sub.close);

      h.server.publishConfig({'store_open': false});
      await pumpEventQueue();
      expect(h.read(appConfigControllerProvider).storeOpen, isFalse);

      h.server.publishConfig(
          {'store_open': true, 'min_supported_version': '2.0.0'});
      await pumpEventQueue();
      final config = h.read(appConfigControllerProvider);
      expect(config.storeOpen, isTrue);
      expect(config.minSupportedVersion, '2.0.0');
    });

    test('one listener, released when the container is disposed', () async {
      final server = MockServer.inMemory();
      final h = TestHarness(server: server);
      h.read(appConfigControllerProvider);
      h.read(appConfigControllerProvider);
      expect(server.configListenerCount, 1);

      h.dispose();
      expect(server.configListenerCount, 0);
    });

    test('a slow older refresh does not overwrite a newer one', () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final controller = h.read(appConfigControllerProvider.notifier);
      var calls = 0;
      h.server.chaos.latencyOverride = (req) => req.path == '/v1/config'
          ? Duration(milliseconds: ++calls == 1 ? 200 : 10)
          : null;

      final slow = controller.refresh(); // fetched before the publish
      h.server.publishConfig({'store_open': false});
      final fast = controller.refresh();
      await Future.wait([slow, fast]);

      expect(h.read(appConfigControllerProvider).storeOpen, isFalse);
    });
  });
}
