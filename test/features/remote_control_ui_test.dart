import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/core/storage/key_value_store.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/app_config/presentation/update_gate.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/presentation/cart_screen.dart';
import 'package:quickkart/features/catalog/presentation/home_screen.dart';
import 'package:quickkart/mock_server/mock_server.dart';

import '../helpers/catalog_helpers.dart';
import '../helpers/test_harness.dart';

void main() {
  late MockServer server;
  late InMemoryKeyValueStore store;
  late ProviderContainer container;

  setUp(() {
    server = MockServer.inMemory();
    store = InMemoryKeyValueStore();
    container = ProviderContainer(overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      mockServerProvider.overrideWithValue(server),
    ]);
  });
  tearDown(() => container.dispose());

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => UpdateGate(child: child!),
        home: home,
      ),
    ));
    await settle(tester);
  }

  Future<void> publish(WidgetTester tester, Map<String, Object?> values) async {
    server.publishConfig(values);
    await settle(tester);
  }

  testWidgets('force update blocks the app mid-session, and lifts again',
      (tester) async {
    await pumpApp(tester, const Scaffold(body: Text('home')));
    expect(find.text('home'), findsOneWidget);

    await publish(tester, {'min_supported_version': '2.0.0'});
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('home'), findsNothing);
    expect(find.text('Update now'), findsOneWidget);

    await publish(tester, {'min_supported_version': '1.0.0'});
    expect(find.text('Update required'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('optional update: dismissible, not shown again for that version',
      (tester) async {
    await pumpApp(tester, const Scaffold(body: Text('home')));
    await publish(tester, {'latest_version': '1.5.0'});
    expect(find.text('A new version (1.5.0) is available'), findsOneWidget);
    expect(find.text('home'), findsOneWidget, reason: 'app still usable');

    await tester.tap(find.text('Later'));
    await settle(tester);
    expect(find.textContaining('A new version'), findsNothing);
    expect(await store.getString(kDismissedUpdateVersionKey), '1.5.0');

    await publish(tester, {'store_open': true}); // unrelated publish
    expect(find.textContaining('A new version'), findsNothing);

    await publish(tester, {'latest_version': '1.6.0'});
    expect(find.text('A new version (1.6.0) is available'), findsOneWidget);
  });

  testWidgets('home screen follows home_sections and survives bad config',
      (tester) async {
    container
        .read(appConfigControllerProvider.notifier)
        .hydrate(await container.read(configRepositoryProvider).load());
    await pumpApp(tester, const HomeScreen());
    expect(find.text('Diwali Dhamaka'), findsOneWidget); // banner
    expect(find.text('Deals for you 🔥'), findsOneWidget);
    expect(find.text('All products'), findsOneWidget);

    await publish(tester, {
      'home_sections': jsonEncode(['all_products'])
    });
    expect(find.text('Diwali Dhamaka'), findsNothing);
    expect(find.text('Deals for you 🔥'), findsNothing);
    expect(find.text('All products'), findsOneWidget);

    await publish(tester, {'home_sections': '[banner,'}); // malformed
    expect(tester.takeException(), isNull);
    expect(find.text('All products'), findsOneWidget); // default layout
    expect(find.text('Diwali Dhamaka'), findsNothing);

    await publish(tester, {
      'home_banner': '{oops',
      'home_sections': jsonEncode(['banner', 'categories'])
    });
    expect(tester.takeException(), isNull);
    expect(find.text('All products'), findsNothing);
  });

  testWidgets('store closes while the user is on the cart screen',
      (tester) async {
    final h = TestHarness(store: store, server: server);
    addTearDown(h.dispose);
    await container
        .read(cartControllerProvider.notifier)
        .add(serverProduct(h, 'fruits-01'));
    await pumpApp(tester, const CartScreen());
    expect(find.text('Place order  ▶'), findsOneWidget);

    await publish(tester, {'store_open': false});

    expect(find.text(server.configValues['store_closed_message'] as String),
        findsOneWidget);
    expect(find.text('Store closed'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Store closed'), matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull);
  });
}

/// Lets the in-process network calls (zero latency in tests) complete.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
