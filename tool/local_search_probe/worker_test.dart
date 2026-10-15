import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'matcher.dart';
import 'worker.dart';

const deadline = Duration(seconds: 2);

ProbeBlock block(String text) => ProbeBlock(
  LocalBookIdentity.chapter(LocalBookIdentity.book('a' * 64), 'txt:0'),
  'revision',
  'block',
  0,
  text,
);

void main() {
  for (final cancel in [true, false]) {
    test(
      'in-flight scan settles on ${cancel ? 'cancel' : 'unexpected exit'}',
      () async {
        final worker = await ProbeWorker.start();
        addTearDown(worker.close);
        final started = ReceivePort();
        addTearDown(started.close);
        // Worker acknowledges this actual scan before its synchronous ASCII fold.
        final query = worker.call('scan', (
          '不存在',
          [block('M' * 5580000)],
          1000,
        ), started: started.sendPort);
        final stopped = isA<ProbeWorkerStopped>().having(
          (e) => e.cancelled,
          'cancelled',
          cancel,
        );
        final settled = expectLater(query.timeout(deadline), throwsA(stopped));
        await started.first.timeout(deadline);
        expect(
          worker.pendingCalls,
          1,
          reason: 'scan result is still outstanding',
        );
        final queued = expectLater(
          worker.call('scan', ('新查询', null, 1000)).timeout(deadline),
          throwsA(stopped),
        );
        final watch = Stopwatch()..start();
        if (cancel) {
          await worker.close().timeout(deadline);
        } else {
          worker.isolate.kill(priority: Isolate.immediate);
          await worker.exited.timeout(deadline);
        }
        await Future.wait([settled, queued]);
        watch.stop();
        expect(
          worker.pendingCalls,
          0,
          reason: 'all reply ports have been closed',
        );
        await expectLater(worker.call('load', []), throwsA(stopped));

        final replacement = await ProbeWorker.start();
        addTearDown(replacement.close);
        final result = await replacement
            .call('scan', ('新查询', [block('只有新查询')], 1000))
            .timeout(deadline);
        expect(
          (result as (({List<ProbeHit> hits, int count}), int)).$1.count,
          1,
        );
        expect(replacement.pendingCalls, 0);
        // ignore: avoid_print
        print(
          'QUERY_CLEANUP cancelled=$cancel settledUs=${watch.elapsedMicroseconds}',
        );
      },
    );
  }

  test(
    'uncaught worker errors fail pending calls without the timeout',
    () async {
      final worker = await ProbeWorker.start();
      addTearDown(worker.close);
      await expectLater(
        worker.call('scan', ('无', [block('正文')], -1)).timeout(deadline),
        throwsA(
          isA<ProbeWorkerStopped>()
              .having((e) => e.cancelled, 'cancelled', false)
              .having((e) => e.cause.toString(), 'cause', contains('limit')),
        ),
      );
      await worker.exited.timeout(deadline);
      expect(worker.pendingCalls, 0);
    },
  );

  test(
    'batch worker returns stable positions for retained original summaries',
    () async {
      final worker = await ProbeWorker.start();
      addTearDown(worker.close);
      final original = block('前😀山山${'上下文' * 30}山山末尾');
      final retained = <ProbeHit>[];
      var count = 0;
      for (final batch in batches([original], '山', maxUnits: 20)) {
        final reply = await worker.call('scan', (
          '山',
          batch,
          3 - retained.length,
        ));
        final result = (reply as (({List<ProbeHit> hits, int count}), int)).$1;
        count += result.count;
        retained.addAll(result.hits);
      }
      expect(count, 4);
      expect(retained, hasLength(3));
      final expected = scan([original], '山', limit: 3).hits;
      for (var i = 0; i < retained.length; i++) {
        final actual = retained[i].summarize(original);
        final full = expected[i].summarize(original);
        expect(
          (actual.before, actual.match, actual.after),
          (full.before, full.match, full.after),
        );
      }
      expect(retained[1].summarize(original).before, '前😀山');
      expect(worker.pendingCalls, 0);
    },
  );
}
