import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../domain/contracts/contracts.dart';
import '../../shared/app_logger.dart';
import 'network_types.dart';

/// One Source owns one transport; NET-002 schedules each bounded attempt.
class NetworkTransport {
  NetworkTransport({
    required this.policy,
    required this.logger,
    HttpClientAdapter? adapter,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       _dio = Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 10),
           sendTimeout: const Duration(seconds: 10),
           followRedirects: false,
           maxRedirects: 0,
           responseType: ResponseType.stream,
           validateStatus: (_) => true,
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }
  final SourceNetworkPolicy policy;
  final AppLogger logger;
  final DateTime Function() now;
  final Dio _dio;
  final _active = <CancelToken>{};
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    for (final token in _active.toList()) {
      token.cancel();
    }
    _dio.close(force: true);
  }

  Future<Result<NetworkResponse>> attempt(
    NetworkRequest request, {
    required CancellationToken cancellation,
    required DateTime deadline,
    int attemptNumber = 1,
    bool crossOrigin = false,
  }) async {
    if (_closed) throw StateError('Transport closed');
    final started = now();
    final id = logger.newRequestId();
    if (cancellation.isCancelled) {
      return Failure(AppFailure.cancelled(request.operation));
    }
    final remaining = deadline.difference(started);
    if (remaining <= Duration.zero) {
      return Failure(networkFailure(request.operation, FailureKind.timeout));
    }
    final token = CancelToken();
    _active.add(token);
    final stopped = Completer<Result<NetworkResponse>>();
    void stop(AppFailure failure) {
      if (!stopped.isCompleted) stopped.complete(Failure(failure));
      token.cancel();
    }

    final timer = Timer(
      remaining,
      () => stop(
        networkFailure(
          request.operation,
          FailureKind.timeout,
          diagnosticId: id,
        ),
      ),
    );
    final cancelSubscription = cancellation.whenCancelled.asStream().listen(
      (_) => stop(AppFailure.cancelled(request.operation)),
    );
    final transportCancellation = token.whenCancel.asStream().listen((_) {
      if (!stopped.isCompleted) {
        stopped.complete(Failure(AppFailure.cancelled(request.operation)));
      }
    });
    StreamSubscription<Uint8List>? bodySubscription;
    Future<Result<NetworkResponse>> fetch() async {
      try {
        final uri = request.uri;
        if (uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            !policy.allows(uri)) {
          return Failure(
            networkFailure(
              request.operation,
              FailureKind.accessRestricted,
              diagnosticId: id,
            ),
          );
        }
        final headers = Map<String, String>.from(policy.headersFor(uri));
        if (crossOrigin) {
          // Arbitrary custom headers can also carry credentials. Only explicitly
          // non-secret representation headers survive an origin change.
          headers.removeWhere(
            (name, _) => !{
              'accept',
              'content-type',
              'user-agent',
            }.contains(name.toLowerCase()),
          );
        }
        final response = await _dio.requestUri<ResponseBody>(
          uri,
          data: request.body,
          cancelToken: token,
          options: Options(
            method: request.method.name.toUpperCase(),
            headers: headers,
            responseType: ResponseType.stream,
            receiveTimeout: request.receiveTimeout,
          ),
        );
        final body = response.data!;
        if (token.isCancelled) {
          await body.stream.listen(null).cancel();
          return Failure(AppFailure.cancelled(request.operation));
        }
        // Attach before validating so every rejected response is also released.
        final done = Completer<Result<NetworkResponse>>();
        final bytes = BytesBuilder(copy: false);
        final status = response.statusCode ?? 0;
        final responseHeaders = response.headers.map;
        if (status < 200 || status >= 300) {
          // Redirect/status policy needs headers, never the remote error body.
          // In particular a huge/stalled 429 body cannot evade source cooldown.
          bodySubscription = body.stream.listen(null);
          policy.acceptResponse(uri, responseHeaders);
          return Success(
            NetworkResponse(
              status: status,
              headers: responseHeaders,
              bytes: Uint8List(0),
            ),
          );
        }
        final mime = response.headers
            .value('content-type')
            ?.split(';')
            .first
            .trim()
            .toLowerCase();
        final length = int.tryParse(
          response.headers.value('content-length') ?? '',
        );
        AppFailure? rejected;
        if (length != null && length > request.maxBytes) {
          rejected = networkFailure(
            request.operation,
            FailureKind.tooLarge,
            diagnosticId: id,
          );
        } else if (status >= 200 &&
            status < 300 &&
            request.method != HttpMethod.head &&
            !request.mimeTypes.contains(mime)) {
          rejected = networkFailure(
            request.operation,
            FailureKind.accessRestricted,
            diagnosticId: id,
          );
        }
        if (rejected != null) {
          await body.stream.listen(null).cancel();
          return Failure(rejected);
        }
        bodySubscription = body.stream.listen(
          (chunk) {
            if (done.isCompleted) return;
            if (bytes.length + chunk.length > request.maxBytes) {
              done.complete(
                Failure(
                  networkFailure(
                    request.operation,
                    FailureKind.tooLarge,
                    diagnosticId: id,
                  ),
                ),
              );
            } else {
              // Adapter-owned buffers must not mutate previously accepted bytes.
              bytes.add(Uint8List.fromList(chunk));
            }
          },
          onError: (Object error) {
            if (!done.isCompleted) {
              done.complete(Failure(_map(error, request.operation, id)));
            }
          },
          onDone: () {
            if (done.isCompleted) return;
            if (length != null &&
                response.headers.value('content-encoding') == null &&
                request.method != HttpMethod.head &&
                length != bytes.length) {
              done.complete(
                Failure(
                  networkFailure(
                    request.operation,
                    FailureKind.network,
                    diagnosticId: id,
                  ),
                ),
              );
            } else {
              // Cookie/session acceptance is a private Source concern.
              try {
                policy.acceptResponse(uri, responseHeaders);
                done.complete(
                  Success(
                    NetworkResponse(
                      status: status,
                      headers: responseHeaders,
                      bytes: bytes.takeBytes(),
                    ),
                  ),
                );
              } catch (_) {
                done.complete(
                  Failure(
                    networkFailure(
                      request.operation,
                      FailureKind.unsupported,
                      diagnosticId: id,
                    ),
                  ),
                );
              }
            }
          },
        );
        return await Future.any([done.future, stopped.future]);
      } catch (error) {
        return Failure(_map(error, request.operation, id));
      }
    }

    try {
      var result = await Future.any([fetch(), stopped.future]);
      if (cancellation.isCancelled) {
        result = Failure(AppFailure.cancelled(request.operation));
      } else if (!deadline.isAfter(now())) {
        result = Failure(
          networkFailure(
            request.operation,
            FailureKind.timeout,
            diagnosticId: id,
          ),
        );
      }
      logger.network(
        source: policy.sourceId,
        operation: request.operation,
        requestId: id,
        duration: now().difference(started),
        attempt: attemptNumber,
        status: result is Success<NetworkResponse> ? result.value.status : null,
        bytes: result is Success<NetworkResponse>
            ? result.value.bytes.length
            : 0,
        failure: result is Failure<NetworkResponse>
            ? result.failure
            : (result as Success<NetworkResponse>).value.status >= 400
            ? statusFailure(result.value.status, request.operation)
            : null,
      );
      return result;
    } finally {
      timer.cancel();
      unawaited(cancelSubscription.cancel());
      unawaited(transportCancellation.cancel());
      if (bodySubscription != null) {
        // Abort is immediate; a broken adapter's cleanup Future must not extend
        // the caller's deadline or expose raw cleanup errors.
        unawaited(bodySubscription!.cancel().catchError((Object _) {}));
      }
      token.cancel();
      _active.remove(token);
    }
  }
}

AppFailure _map(Object error, Operation operation, String id) {
  final kind = error is DioException
      ? switch (error.type) {
          DioExceptionType.cancel => FailureKind.cancelled,
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.transformTimeout => FailureKind.timeout,
          DioExceptionType.badCertificate => FailureKind.accessRestricted,
          DioExceptionType.badResponse => FailureKind.unsupported,
          DioExceptionType.connectionError ||
          DioExceptionType.unknown => FailureKind.network,
        }
      : FailureKind.network;
  return networkFailure(operation, kind, diagnosticId: id);
}
