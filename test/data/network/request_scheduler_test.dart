import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/network/network_types.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';

Result<NetworkResponse> ok() =>
    Success(NetworkResponse(status: 200, headers: {}, bytes: Uint8List(1)));

void main() {
  test(
    'global/source concurrency, spacing and foreground priority share one queue',
    () {
      fakeAsync((async) {
        final epoch = DateTime.utc(2026);
        final scheduler = RequestScheduler(now: () => epoch.add(async.elapsed));
        final jobs = <String, Completer<Result<NetworkResponse>>>{};
        Future<Result<NetworkResponse>> add(
          String name,
          String source,
          RequestPriority priority,
        ) => scheduler.run(
          source: SourceId(source),
          operation: Operation.media,
          priority: priority,
          deadline: epoch.add(const Duration(seconds: 45)),
          cancellation: CancellationSource().token,
          work: (_) {
            final job = Completer<Result<NetworkResponse>>();
            jobs[name] = job;
            return job.future;
          },
        );
        add('background1', 'a', RequestPriority.background);
        add('background2', 'b', RequestPriority.background);
        add('foreground', 'a', RequestPriority.foreground);
        async.flushMicrotasks();
        expect(jobs.keys, ['background1']);
        async.elapse(const Duration(milliseconds: 499));
        expect(jobs, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(jobs.keys, ['background1', 'foreground']);
        expect(scheduler.activeCount, 2);
        jobs['background1']!.complete(ok());
        async.flushMicrotasks();
        expect(jobs.keys, ['background1', 'foreground', 'background2']);
        expect(scheduler.activeCount, 2);
        for (final job in jobs.values.where((j) => !j.isCompleted)) {
          job.complete(ok());
        }
        async.flushMicrotasks();
        scheduler.close();
        expect(async.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'queued cancellation/deadline and foreground admission evict pending background',
    () {
      fakeAsync((async) {
        final epoch = DateTime.utc(2026);
        final scheduler = RequestScheduler(
          now: () => epoch.add(async.elapsed),
          maxQueued: 2,
        );
        final blockers = <Completer<Result<NetworkResponse>>>[];
        final tokens = <CancellationToken>[];
        var starts = 0;
        Future<Result<NetworkResponse>> add(
          String source,
          RequestPriority priority, {
          CancellationToken? token,
          Duration lifetime = const Duration(seconds: 45),
        }) => scheduler.run(
          source: SourceId(source),
          operation: Operation.chapter,
          priority: priority,
          deadline: epoch.add(lifetime),
          cancellation: token ?? CancellationSource().token,
          work: (token) {
            starts++;
            tokens.add(token);
            final c = Completer<Result<NetworkResponse>>();
            blockers.add(c);
            return c.future;
          },
        );
        add('a', RequestPriority.foreground);
        add('b', RequestPriority.foreground);
        Result<NetworkResponse>? evicted;
        add('c', RequestPriority.background).then((v) => evicted = v);
        final cancel = CancellationSource();
        add('d', RequestPriority.foreground, token: cancel.token);
        add(
          'e',
          RequestPriority.foreground,
          lifetime: const Duration(seconds: 1),
        );
        async.flushMicrotasks();
        expect((evicted as Failure).failure.isCancellation, isTrue);
        expect(scheduler.queuedCount, 2);
        cancel.cancel();
        async.flushMicrotasks();
        expect(scheduler.queuedCount, 1);
        async.elapse(const Duration(seconds: 1));
        expect(scheduler.queuedCount, 0);
        expect(starts, 2);
        scheduler.close();
        expect(tokens.every((t) => t.isCancelled), isTrue);
        for (final blocker in blockers) {
          blocker.complete(ok());
        }
        async.flushMicrotasks();
        expect(scheduler.activeCount, 0);
        expect(async.pendingTimers, isEmpty);
      });
    },
  );
}
