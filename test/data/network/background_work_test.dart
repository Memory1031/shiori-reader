import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/data/network/background_work.dart';
import 'package:shiori/data/network/network_client.dart';
import 'package:shiori/data/network/network_transport.dart';
import 'package:shiori/data/network/network_types.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/shared/app_logger.dart';
import 'network_test_support.dart';

void main() {
  test(
    'foreground join promotes a queued background job without waiting for other background',
    () async {
      final scheduler = RequestScheduler(startInterval: Duration.zero);
      final hold = Completer<Result<NetworkResponse>>();
      final first = scheduler.run(
        source: SourceId('a'),
        operation: Operation.media,
        priority: RequestPriority.background,
        deadline: DateTime.now().add(const Duration(seconds: 10)),
        cancellation: CancellationSource().token,
        work: (_) => hold.future,
      );
      final scope = BackgroundWork(BackgroundBudget());
      var started = false;
      final queued = scope.run(
        () => scheduler.run(
          source: SourceId('b'),
          operation: Operation.media,
          priority: RequestPriority.background,
          deadline: DateTime.now().add(const Duration(seconds: 10)),
          cancellation: CancellationSource().token,
          work: (_) async {
            started = true;
            return Success(
              NetworkResponse(
                status: 200,
                headers: const {},
                bytes: Uint8List(0),
              ),
            );
          },
        ),
      );
      expect(started, isFalse);
      BackgroundWork.promote(scope);
      await queued;
      expect(started, isTrue);
      expect(hold.isCompleted, isFalse);
      hold.complete(
        Success(
          NetworkResponse(status: 200, headers: const {}, bytes: Uint8List(0)),
        ),
      );
      await first;
      scheduler.close();
      expect(scope.onPromoted, isEmpty);
    },
  );
  test(
    'redirect and streamed bytes charge shared budget; foreground bypasses exhausted budget',
    () async {
      final adapter = TestAdapter(
        (options) => options.uri.path == '/redirect'
            ? response(
                status: 302,
                headers: {
                  'location': ['/body'],
                },
              )
            : response(bytes: List.filled(8, 0)),
      );
      final transport = NetworkTransport(
        policy: TestPolicy(),
        logger: AppLogger(),
        adapter: adapter,
      );
      final scheduler = RequestScheduler(startInterval: Duration.zero);
      final client = NetworkClient(transport: transport, scheduler: scheduler);
      final budget = BackgroundBudget(maxBytes: 4, maxAttempts: 5);
      Future<Result<NetworkResponse>> request() => client.send(
        NetworkRequest(
          uri: Uri.parse('https://example.test/redirect'),
          operation: Operation.chapter,
        ),
        cancellation: CancellationSource().token,
      );
      expect(await BackgroundWork(budget).run(request), isA<Failure>());
      expect(budget.attempts, 2);
      expect(budget.bytes, 8);
      expect(await BackgroundWork(budget).run(request), isA<Failure>());
      expect(adapter.requests, hasLength(2));
      expect(await request(), isA<Success>());
      expect(adapter.requests, hasLength(4));
      transport.close();
      scheduler.close();
    },
  );
}
