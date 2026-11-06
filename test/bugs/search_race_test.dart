// One search request per keystroke: a slow response for an older query must
// not replace the results of the newer query.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/search/search_controller.dart';

import '../helpers/test_harness.dart';

void main() {
  test('a slow older search does not overwrite the newer one', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    h.server.chaos.latencyOverride = (req) => req.query['q'] == 'ba'
        ? const Duration(milliseconds: 300)
        : const Duration(milliseconds: 10);
    final search = h.read(searchControllerProvider.notifier);

    final slow = search.search('ba'); // user typed "ba"...
    final fast = search.search('banana'); // ...then "banana"
    await Future.wait([slow, fast]);

    final state = h.read(searchControllerProvider);
    expect(state.query, 'banana');
    expect(state.results.map((p) => p.id), ['fruits-01']);
  });
}
