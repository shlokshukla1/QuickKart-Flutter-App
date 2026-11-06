// The scroll listener calls loadMore() on every scroll event; the same page
// must not be fetched and appended several times.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/presentation/catalog_controller.dart';

import '../helpers/test_harness.dart';

void main() {
  test('concurrent loadMore calls do not duplicate products', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final provider = catalogControllerProvider('fruits'); // 12 products
    final sub = h.container.listen(provider, (_, __) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    final controller = h.read(provider.notifier);

    await Future.wait(
        [controller.loadMore(), controller.loadMore(), controller.loadMore()]);

    final ids = h.read(provider).items.map((p) => p.id).toList();
    expect(ids.toSet(), hasLength(ids.length), reason: 'duplicates: $ids');
    expect(ids, hasLength(12));
  });

  test('a refresh during loadMore does not append the stale page', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final provider = catalogControllerProvider('fruits');
    final sub = h.container.listen(provider, (_, __) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    final controller = h.read(provider.notifier);

    await Future.wait([controller.loadMore(), controller.refresh()]);

    final ids = h.read(provider).items.map((p) => p.id).toList();
    expect(ids.toSet(), hasLength(ids.length), reason: 'duplicates: $ids');
  });
}
