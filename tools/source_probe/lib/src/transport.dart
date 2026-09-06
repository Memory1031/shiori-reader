import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const site = 'https://www.lightnovel.fun';
const apiPrefix = '/api/pc-proxy/api/';
const apiOperations = {
  'bff/apk-search-result-v1',
  'new-content-read/get-book-detail',
  'new-content-read/get-book-volumes',
  'new-content-read/get-volume-chapters',
  'new-content-read/get-chapter-detail',
};

// Only constant codes reach reports. Never stringify remote errors or URLs.
class ProbeFailure implements Exception {
  const ProbeFailure(this.code);
  final String code;
}

void require(bool condition, String code) {
  if (!condition) throw ProbeFailure(code);
}

void validateTarget(Uri uri, String method) {
  require(
    uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.port == 443 &&
        !uri.hasFragment,
    'unsafe_target',
  );
  if (method == 'POST') {
    require(
      uri.host == 'www.lightnovel.fun' &&
          !uri.hasQuery &&
          apiOperations.any((op) => uri.path == '$apiPrefix$op'),
      'unsafe_target',
    );
  } else {
    require(
      method == 'GET' &&
          uri.host == 'api.lightnovel.fun' &&
          RegExp(
            r'^/upload-files/images/[0-9]+/[a-f0-9]+\.(jpg|jpeg|png)$',
          ).hasMatch(uri.path),
      'unsafe_target',
    );
  }
}

class WireResponse {
  WireResponse(this.status, this.mime, this.bytes, {this.location});
  final int status;
  final String mime;
  final Uint8List bytes;
  final String? location;
}

typedef Exchange =
    Future<WireResponse> Function(
      String method,
      Uri uri,
      Map<String, Object?>? body,
      int byteLimit,
    );

// Exactly one HTTP attempt, no automatic redirects/retries/cookie persistence.
Future<WireResponse> ioExchange(
  String method,
  Uri uri,
  Map<String, Object?>? body,
  int byteLimit,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    return await (() async {
      final request = await client.openUrl(method, uri);
      request.followRedirects = false;
      request.persistentConnection = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        method == 'POST' ? 'application/json' : 'image/jpeg,image/png',
      );
      request.headers.set(HttpHeaders.refererHeader, '$site/');
      if (body != null) {
        request.headers.set('Origin', site);
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close();
      final mime = response.headers.contentType?.mimeType ?? '';
      final location = response.headers.value(HttpHeaders.locationHeader);
      // Do not consume denial/challenge bodies, which may contain private data.
      if (response.statusCode != 200) {
        return WireResponse(
          response.statusCode,
          mime,
          Uint8List(0),
          location: location,
        );
      }
      require(response.contentLength <= byteLimit, 'response_too_large');
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        require(bytes.length + chunk.length <= byteLimit, 'response_too_large');
        bytes.add(chunk);
      }
      return WireResponse(response.statusCode, mime, bytes.takeBytes());
    })().timeout(const Duration(seconds: 30));
  } finally {
    client.close(force: true);
  }
}

class BudgetTransport {
  BudgetTransport({
    required this.live,
    this.limit = 30,
    Exchange? exchange,
    this.spacing = const Duration(seconds: 1),
  }) : _exchange = exchange ?? ioExchange {
    require(limit >= 1 && limit <= 30, 'invalid_budget');
  }

  final bool live;
  final int limit;
  final Duration spacing;
  final Exchange _exchange;
  final List<Map<String, Object?>> attempts = [];
  bool _busy = false;
  bool _stopped = false;

  Future<WireResponse> request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
    int byteLimit = 16 * 1024 * 1024,
  }) async {
    require(live, 'live_disabled');
    require(!_stopped, 'transport_stopped');
    require(!_busy, 'concurrent_request');
    _busy = true;
    try {
      var redirects = 0;
      while (true) {
        validateTarget(uri, method);
        require(attempts.length < limit, 'budget_exhausted');
        if (attempts.isNotEmpty) await Future<void>.delayed(spacing);
        final record = <String, Object?>{
          'attempt': attempts.length + 1,
          'method': method,
          'kind': method == 'POST' ? 'api' : 'body_image',
        };
        attempts.add(record); // Failures and redirects consume budget too.
        final response = await _exchange(method, uri, body, byteLimit);
        record['httpStatus'] = response.status;
        record['bytes'] = response.bytes.length;
        require(response.bytes.length <= byteLimit, 'response_too_large');
        if ({301, 302, 303, 307, 308}.contains(response.status)) {
          require(
            method == 'GET' && redirects < 3 && response.location != null,
            'redirect_stopped',
          );
          final next = uri.resolve(response.location!);
          validateTarget(next, method);
          uri = next;
          redirects++;
          continue;
        }
        require(response.status == 200, 'http_status_rejected');
        return response;
      }
    } on ProbeFailure {
      _stopped = true;
      rethrow;
    } on TimeoutException {
      _stopped = true;
      throw const ProbeFailure('network_timeout');
    } catch (_) {
      _stopped = true;
      throw const ProbeFailure('transport_failed');
    } finally {
      _busy = false;
    }
  }
}
