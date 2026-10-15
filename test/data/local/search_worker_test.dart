import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/search/search_worker.dart';
import 'package:shiori/domain/contracts/contracts.dart';

void main() {
  test(
    'bounded worker resumes overlaps and retains original unit and point offsets',
    () async {
      final worker = await LocalSearchWorker.start();
      addTearDown(worker.close);
      const chunk = SearchChunk('😀e\u0301aaaa', 8, 100, 90);
      final first = await worker.scan(chunk, 'aa', 2);
      expect(first.hits.map((r) => (r.start, r.end, r.unitStart, r.unitEnd)), [
        (93, 95, 104, 106),
        (94, 96, 105, 107),
      ]);
      expect(first.done, isFalse);
      final next = await worker.scan(null, 'aa', 2);
      expect(next.hits.single.start, 95);
      expect(next.done, isTrue);
      expect(next.nextPoint, 97);
    },
  );
  for (final cancel in [true, false]) {
    test(
      'pending scan settles and ports close on ${cancel ? 'cancel' : 'unexpected exit'}',
      () async {
        final worker = await LocalSearchWorker.start();
        addTearDown(worker.close);
        final pending = worker.scan(
          SearchChunk('M' * searchBatchUnits, searchBatchUnits, 0, 0),
          '无',
          64,
        );
        expect(worker.pendingCalls, 1);
        final settled = expectLater(
          pending.timeout(const Duration(seconds: 2)),
          throwsA(
            isA<AppFailure>().having(
              (f) => f.isCancellation,
              'cancelled',
              cancel,
            ),
          ),
        );
        if (cancel) {
          await worker.close();
        } else {
          worker.isolate.kill(priority: Isolate.immediate);
          await settled;
          await worker.close();
        }
        await settled;
        expect(worker.pendingCalls, 0);
        final replacement = await LocalSearchWorker.start();
        addTearDown(replacement.close);
        expect(
          (await replacement.scan(
            const SearchChunk('新查询', 3, 0, 0),
            '新',
            64,
          )).hits,
          hasLength(1),
        );
      },
    );
  }
  test(
    'worker exception promptly ends the pending future with a safe failure',
    () async {
      final worker = await LocalSearchWorker.start();
      addTearDown(worker.close);
      await expectLater(
        worker
            .scan(const SearchChunk('正文', 2, 0, 0), '文', 0)
            .timeout(const Duration(seconds: 2)),
        throwsA(
          isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.parse),
        ),
      );
      await worker.close();
      expect(worker.pendingCalls, 0);
    },
  );
}
