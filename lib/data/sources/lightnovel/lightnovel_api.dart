import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../domain/contracts/contracts.dart';
import '../../../domain/models/models.dart';
import '../../../shared/app_logger.dart';
import '../../network/network_client.dart';
import '../../network/network_transport.dart';
import '../../network/network_types.dart';
import '../../network/request_scheduler.dart';

final lightNovelSourceId = SourceId('lightnovel');

/// Data-layer protocol only; never pass envelopes or endpoints to presentation.
enum LightNovelEndpoint {
  search('/api/bff/apk-search-result-v1', Operation.search),
  detail('/api/new-content-read/get-book-detail', Operation.novelDetail),
  volumes('/api/new-content-read/get-book-volumes', Operation.catalog),
  chapters('/api/new-content-read/get-volume-chapters', Operation.catalog),
  chapter('/api/new-content-read/get-chapter-detail', Operation.chapter);

  const LightNovelEndpoint(this.path, this.operation);
  final String path;
  final Operation operation;
  Uri get uri => Uri.parse('https://www.lightnovel.fun/api/pc-proxy$path');
}

class _Policy implements SourceNetworkPolicy {
  @override
  SourceId get sourceId => lightNovelSourceId;
  @override
  bool allows(Uri uri) => LightNovelEndpoint.values.any((e) => e.uri == uri);
  @override
  Map<String, String> headersFor(Uri uri) => const {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Origin': 'https://www.lightnovel.fun',
    'Referer': 'https://www.lightnovel.fun/',
  };
  // SRC-004 chose credential-free requests. Never retain Set-Cookie.
  @override
  void acceptResponse(Uri uri, Map<String, List<String>> headers) {}
}

/// Owns a private transport, borrows the application-wide scheduler.
/// No I/O on construction, no disk/session store, no automatic recovery.
final class LightNovelApi {
  LightNovelApi({
    required RequestScheduler scheduler,
    required AppLogger logger,
    HttpClientAdapter? adapter,
  }) {
    _transport = NetworkTransport(
      policy: _Policy(),
      logger: logger,
      adapter: adapter,
    );
    _client = NetworkClient(transport: _transport, scheduler: scheduler);
  }
  late final NetworkTransport _transport;
  late final NetworkClient _client;
  bool _closed = false;

  /// Deliberately no-op: independent unauthenticated requests were verified.
  /// Concurrent callers need no single-flight network initialization.
  Result<void> ensureSession(
    Operation operation,
    CancellationToken cancellation,
  ) => cancellation.isCancelled || _closed
      ? Failure(AppFailure.cancelled(operation))
      : const Success(null);

  Future<Result<Map<String, dynamic>>> request(
    LightNovelEndpoint endpoint,
    Map<String, Object?> payload, {
    required CancellationToken cancellation,
    DateTime? deadline,
  }) async {
    final session = ensureSession(endpoint.operation, cancellation);
    if (session case Failure(:final failure)) return Failure(failure);
    final result = await _client.send(
      NetworkRequest(
        uri: endpoint.uri,
        operation: endpoint.operation,
        method: HttpMethod.post,
        body: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        // No observed redirect or confirmed replay/recovery semantics.
        safeToRepeat: false,
        maxRedirects: 0,
      ),
      cancellation: cancellation,
      deadline: deadline,
    );
    if (result case Failure(:final failure)) return Failure(failure);
    if (cancellation.isCancelled || _closed) {
      return Failure(AppFailure.cancelled(endpoint.operation));
    }
    try {
      final envelope = jsonDecode(
        utf8.decode((result as Success<NetworkResponse>).value.bytes),
      );
      if (envelope is! Map<String, dynamic> || envelope['code'] is! int) {
        return _parse(endpoint.operation);
      }
      if (envelope['code'] != 0) {
        // Real error-code semantics are unknown. Do not infer expired session,
        // expose server text, or attempt another endpoint.
        return Failure(
          AppFailure(
            kind: FailureKind.unsupported,
            operation: endpoint.operation,
          ),
        );
      }
      final data = envelope['data'];
      if (data is! Map<String, dynamic>) return _parse(endpoint.operation);
      return Success(Map.unmodifiable(data));
    } catch (_) {
      return _parse(endpoint.operation);
    }
  }

  Failure<Map<String, dynamic>> _parse(Operation operation) => Failure(
    AppFailure(
      kind: FailureKind.parse,
      operation: operation,
      context: FailureContext.invalidContent,
    ),
  );
  void close() {
    if (_closed) return;
    _closed = true;
    _transport.close();
  }
}
