import 'dart:async';
import 'dart:convert';

import 'api_exceptions.dart';
import 'transport.dart';

/// JSON API client used by every remote data source.
///
/// * GET requests are retried with exponential backoff.
/// * POST requests are never retried automatically.
///
/// FIX (QK-102): there used to be a 10-minute in-memory GET response cache
/// that was checked *before* the network. Pull-to-refresh, "My orders" and
/// remote config all got stale data until the app was restarted. It was
/// removed; offline browsing is handled by `CatalogCache` instead.
class ApiClient {
  ApiClient(
    this._transport, {
    this.maxRetries = 2,
    this.timeout = const Duration(seconds: 8),
    this.retryBaseDelay = const Duration(milliseconds: 200),
  });

  final Transport _transport;
  final int maxRetries;
  final Duration timeout;
  final Duration retryBaseDelay;

  Future<dynamic> get(String path, {Map<String, String> query = const {}}) {
    return _getWithRetry(
      TransportRequest(method: 'GET', path: path, query: query),
    );
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) {
    return _send(
      TransportRequest(
        method: 'POST',
        path: path,
        headers: {'content-type': 'application/json', ...headers},
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<dynamic> _getWithRetry(TransportRequest request) async {
    ApiException? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await _send(request);
      } on ApiException catch (e) {
        lastError = e;
        if (attempt < maxRetries) {
          await Future<void>.delayed(retryBaseDelay * (1 << attempt));
        }
      }
    }
    throw lastError!;
  }

  Future<dynamic> _send(TransportRequest request) async {
    final TransportResponse response;
    try {
      response = await _transport.send(request).timeout(timeout);
    } on TransportUnreachable {
      throw const NetworkException();
    } on TransportTimeout {
      throw const ApiTimeoutException();
    } on TimeoutException {
      throw const ApiTimeoutException();
    }

    final decoded = _decode(response.body);

    if (response.isSuccess) return decoded;

    final code = decoded is Map ? decoded['error'] as String? : null;
    final message = decoded is Map
        ? (decoded['message'] as String? ?? 'Request failed')
        : 'Request failed';
    if (response.statusCode >= 500) {
      throw ServerException(response.statusCode, message, code: code);
    }
    throw ClientException(
      response.statusCode,
      message,
      code: code,
      details: decoded is Map ? decoded['details'] : null,
    );
  }

  dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
