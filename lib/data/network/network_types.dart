import 'dart:typed_data';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';

enum HttpMethod { get, head, post }

enum RequestPriority { foreground, background }

final class NetworkRequest {
  NetworkRequest({
    required this.uri,
    required this.operation,
    this.method = HttpMethod.get,
    Uint8List? body,
    this.safeToRepeat = false,
    this.priority = RequestPriority.foreground,
    this.maxBytes = 8 * 1024 * 1024,
    Set<String> mimeTypes = const {'application/json'},
    this.receiveTimeout = const Duration(seconds: 20),
  }) : body = body == null
           ? null
           : Uint8List.fromList(body).asUnmodifiableView(),
       mimeTypes = Set.unmodifiable(mimeTypes) {
    if (maxBytes < 1 ||
        maxBytes > 20 * 1024 * 1024 ||
        receiveTimeout <= Duration.zero ||
        mimeTypes.isEmpty) {
      throw ArgumentError('Invalid request budget');
    }
  }
  final Uri uri;
  final Operation operation;
  final HttpMethod method;
  final Uint8List? body;
  final bool safeToRepeat;
  final RequestPriority priority;
  final int maxBytes;
  final Set<String> mimeTypes;
  final Duration receiveTimeout;
  NetworkRequest redirect(Uri target, HttpMethod nextMethod) => NetworkRequest(
    uri: target,
    operation: operation,
    method: nextMethod,
    body: nextMethod == HttpMethod.post ? body : null,
    safeToRepeat: safeToRepeat,
    priority: priority,
    maxBytes: maxBytes,
    mimeTypes: mimeTypes,
    receiveTimeout: receiveTimeout,
  );
}

/// Source-owned policy, never exposed to UI. Headers are rebuilt for each hop;
/// response cookies can be accepted privately here without logging them.
abstract interface class SourceNetworkPolicy {
  SourceId get sourceId;
  bool allows(Uri uri);
  Map<String, String> headersFor(Uri uri);
  void acceptResponse(Uri uri, Map<String, List<String>> headers);
}

final class NetworkResponse {
  NetworkResponse({
    required this.status,
    required Map<String, List<String>> headers,
    required Uint8List bytes,
  }) : headers = Map.unmodifiable(
         headers.map(
           (key, value) =>
               MapEntry(key.toLowerCase(), List<String>.unmodifiable(value)),
         ),
       ),
       bytes = bytes.asUnmodifiableView();
  final int status;
  final Map<String, List<String>> headers;
  final Uint8List bytes;
  String? header(String name) => headers[name.toLowerCase()]?.firstOrNull;
}

AppFailure networkFailure(
  Operation operation,
  FailureKind kind, {
  String? diagnosticId,
  DateTime? retryNotBefore,
}) => AppFailure(
  kind: kind,
  operation: operation,
  diagnosticId: diagnosticId,
  retryNotBefore: retryNotBefore,
  retryPolicy: switch (kind) {
    FailureKind.network ||
    FailureKind.timeout ||
    FailureKind.sourceUnavailable => RetryPolicy.boundedAutomatic,
    FailureKind.rateLimited || FailureKind.parse => RetryPolicy.manual,
    _ => RetryPolicy.never,
  },
);

AppFailure? statusFailure(
  int status,
  Operation operation, {
  DateTime? retryNotBefore,
}) => status >= 200 && status < 300
    ? null
    : networkFailure(operation, switch (status) {
        401 || 403 => FailureKind.accessRestricted,
        404 || 410 => FailureKind.notFound,
        429 => FailureKind.rateLimited,
        502 || 503 || 504 => FailureKind.sourceUnavailable,
        _ => FailureKind.unsupported,
      }, retryNotBefore: status == 429 ? retryNotBefore : null);
