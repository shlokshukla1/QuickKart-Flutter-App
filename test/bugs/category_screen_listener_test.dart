// CategoryScreen subscribed to config updates and never unsubscribed: a
// leaked listener per visit, and setState() after dispose on the next
// config publish.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/core/storage/key_value_store.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/catalog/domain/product.dart';
import 'package:quickkart/features/catalog/presentation/category_screen.dart';
import 'package:quickkart/mock_server/mock_server.dart';

void main() {
  testWidgets('leaving the category screen removes its config listener',
      (tester) async {
    final server = MockServer.inMemory();
    final container = ProviderContainer(overrides: [
      keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      mockServerProvider.overrideWithValue(server),
    ]);
    addTearDown(container.dispose);
    // The app-wide config controller may hold a listener of its own.
    container.listen(appConfigControllerProvider, (_, __) {});
    final baseline = server.configListenerCount;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: CategoryScreen(
          category: Category(id: 'fruits', name: 'Fruits', emoji: '🍎'),
        ),
      ),
    ));
    await tester.pump();

    // Leave the screen, then publish config from the console.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SizedBox()),
    ));
    server.publishConfig({'free_delivery_threshold_paise': 9900});
    await tester.pump();
    await tester.pump();

    expect(server.configListenerCount, baseline);
  });
}
