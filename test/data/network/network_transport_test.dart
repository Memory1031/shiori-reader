import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/network/network_transport.dart';
import 'package:shiori/data/network/network_types.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/shared/app_logger.dart';

import 'network_test_support.dart';

void main() {
  test(
    '429 status survives huge stalled error body without consuming it',
    () async {
      final stream = StreamController<Uint8List>();
      final transport = NetworkTransport(
        policy: TestPolicy(),
        logger: AppLogger(),
        adapter: TestAdapter(
          (_) => ResponseBody(
            stream.stream,
            429,
            headers: {
              'content-length': ['999999999'],
              'content-type': ['text/html'],
              'retry-after': ['60'],
            },
          ),
        ),
      );
      final result = await transport.attempt(
        NetworkRequest(
          uri: Uri.parse('https://example.test/'),
          operation: Operation.chapter,
        ),
        cancellation: CancellationSource().token,
        deadline: DateTime.now().add(const Duration(seconds: 45)),
      );
      expect((result as Success<NetworkResponse>).value.status, 429);
      expect(result.value.bytes, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(stream.hasListener, isFalse);
      transport.close();
      await stream.close();
    },
  );
  test(
    'release logs omit successes and ring buffer remains bounded and immutable',
    () {
      final logger = AppLogger(release: true, capacity: 2);
      final source = TestPolicy().sourceId;
      logger.network(
        source: source,
        operation: Operation.chapter,
        requestId: logger.newRequestId(),
        duration: Duration.zero,
      );
      expect(logger.events, isEmpty);
      for (var i = 0; i < 4; i++) {
        logger.network(
          source: source,
          operation: Operation.chapter,
          requestId: logger.newRequestId(),
          duration: Duration.zero,
          failure: networkFailure(Operation.chapter, FailureKind.network),
        );
      }
      expect(logger.events, hasLength(2));
      expect(
        () => logger.events.first.fields['body'] = 'SECRET',
        throwsUnsupportedError,
      );
    },
  );
  NetworkRequest request({int maxBytes = 100}) => NetworkRequest(
    uri: Uri.parse('https://example.test/read?token=SECRET'),
    operation: Operation.chapter,
    maxBytes: maxBytes,
  );

  test('bounded immutable bytes, private policy and safe logs', () async {
    final logger = AppLogger();
    final adapter = TestAdapter((_) => response(bytes: [1, 2, 3]));
    final policy = TestPolicy(
      label: 'SECRET',
      headers: {'Authorization': 'SECRET'},
    );
    final transport = NetworkTransport(
      policy: policy,
      logger: logger,
      adapter: adapter,
    );
    final result = await transport.attempt(
      request(),
      cancellation: CancellationSource().token,
      deadline: DateTime.now().add(const Duration(seconds: 45)),
    );
    expect((result as Success<NetworkResponse>).value.bytes, [1, 2, 3]);
    expect(() => result.value.bytes[0] = 9, throwsUnsupportedError);
    expect(adapter.requests.single.followRedirects, isFalse);
    expect(adapter.requests.single.connectTimeout, const Duration(seconds: 10));
    expect(policy.accepted, 1);
    expect(logger.events.join(), isNot(contains('SECRET')));
    expect(logger.events.join(), isNot(contains('https:')));
    transport.close();
    expect(adapter.closed, isTrue);
  });

  test('declared, streamed limits and MIME mismatch are failures', () async {
    for (final body in [
      response(
        headers: {
          'content-length': ['101'],
        },
      ),
      response(bytes: List.filled(101, 0)),
      response(
        headers: {
          'content-type': ['text/html'],
        },
      ),
    ]) {
      final transport = NetworkTransport(
        policy: TestPolicy(),
        logger: AppLogger(),
        adapter: TestAdapter((_) => body),
      );
      final result = await transport.attempt(
        request(),
        cancellation: CancellationSource().token,
        deadline: DateTime.now().add(const Duration(seconds: 45)),
      );
      expect(result, isA<Failure<NetworkResponse>>());
      expect(
        (result as Failure).failure.kind,
        anyOf(FailureKind.tooLarge, FailureKind.accessRestricted),
      );
      transport.close();
    }
  });

  test('raw nested exceptions never enter logs or public failures', () async {
    final logger = AppLogger();
    final transport = NetworkTransport(
      policy: TestPolicy(),
      logger: logger,
      adapter: TestAdapter(
        (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'SECRET',
          error: {'secret': 'SECRET'},
        ),
      ),
    );
    final result = await transport.attempt(
      request(),
      cancellation: CancellationSource().token,
      deadline: DateTime.now().add(const Duration(seconds: 45)),
    );
    expect((result as Failure).failure.kind, FailureKind.network);
    expect(logger.events.join(), isNot(contains('SECRET')));
    transport.close();
  });

  test('deadline interrupts stalled adapter and cancellation aborts body', () {
    fakeAsync((async) {
      final epoch = DateTime.utc(2026);
      final adapter = TestAdapter((_) => Completer<ResponseBody>().future);
      final transport = NetworkTransport(
        policy: TestPolicy(),
        logger: AppLogger(),
        adapter: adapter,
        now: () => epoch.add(async.elapsed),
      );
      Result<NetworkResponse>? result;
      transport
          .attempt(
            request(),
            cancellation: CancellationSource().token,
            deadline: epoch.add(const Duration(seconds: 2)),
          )
          .then((value) => result = value);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect((result as Failure).failure.kind, FailureKind.timeout);
      expect(adapter.cancellations, 1);
      transport.close();
      expect(async.pendingTimers, isEmpty);
    });
    fakeAsync((async) {
      final stream = StreamController<Uint8List>();
      final adapter = TestAdapter(
        (_) => ResponseBody(
          stream.stream,
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
      final logger = AppLogger();
      final transport = NetworkTransport(
        policy: TestPolicy(),
        logger: logger,
        adapter: adapter,
      );
      final cancel = CancellationSource();
      Result<NetworkResponse>? result;
      transport
          .attempt(
            request(),
            cancellation: cancel.token,
            deadline: DateTime.now().add(const Duration(seconds: 45)),
          )
          .then((value) => result = value);
      async.flushMicrotasks();
      cancel.cancel();
      async.flushMicrotasks();
      expect((result as Failure).failure.isCancellation, isTrue);
      expect(stream.hasListener, isFalse);
      expect(logger.events, isEmpty);
      transport.close();
      stream.close();
    });
  });

  test(
    'status mapping does not retry access, missing or ordinary server errors',
    () {
      expect(
        statusFailure(403, Operation.chapter)!.kind,
        FailureKind.accessRestricted,
      );
      expect(statusFailure(404, Operation.chapter)!.kind, FailureKind.notFound);
      expect(
        statusFailure(500, Operation.chapter)!.retryPolicy,
        RetryPolicy.never,
      );
      expect(
        statusFailure(503, Operation.chapter)!.retryPolicy,
        RetryPolicy.boundedAutomatic,
      );
    },
  );
}
