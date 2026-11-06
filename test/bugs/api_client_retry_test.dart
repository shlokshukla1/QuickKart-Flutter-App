// 4xx responses are permanent; retrying them only makes the user wait.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_exceptions.dart';
import 'package:quickkart/core/providers.dart';

import '../helpers/test_harness.dart';

void main() {
  test('a 4xx GET is sent once, not retried', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final before = h.server.requestLog.length;

    await expectLater(
      h.read(apiClientProvider).get('/v1/products/search', query: {'q': 'm'}),
      throwsA(isA<ClientException>()
          .having((e) => e.code, 'code', 'QUERY_TOO_SHORT')),
    );
    expect(h.server.requestLog.length - before, 1);
  });

  test('a 5xx GET is still retried', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    h.server.chaos.failureRate = 1; // every request fails before the server
    final before = h.server.requestLog.length;

    await expectLater(
      h.read(apiClientProvider).get('/v1/categories'),
      throwsA(isA<ApiException>()),
    );
    expect(h.server.requestLog.length - before, 3);
  });
}
