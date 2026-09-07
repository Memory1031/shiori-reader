import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/position/progress_tracker.dart';
import '../../support/contract_library.dart';

final book = NovelSummary(
  key: NovelKey(sourceId: SourceId('test'), novelId: 'book'),
  title: 'Book',
);
ChapterContent content([String id = 'one']) => ChapterContent(
  key: ChapterKey(novelKey: book.key, chapterId: id),
  title: id,
  blocks: [ParagraphBlock(text: 'a' * 1000)],
);
ReaderPosition position(ChapterContent c, double fraction) => ReaderPosition(
  contentRevision: c.contentRevision,
  blockKey: c.blocks.first.blockKey,
  blockIndex: 0,
  blockFraction: fraction,
  chapterFraction: 0,
);

class Library implements LibraryRepository {
  final inner = ContractLibrary();
  final writes = <(ReadingProgress, ProgressWriteStamp)>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<Result<int>> beginProgressSession(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => inner.beginProgressSession(key, cancellation: cancellation);
  @override
  Future<Result<bool>> saveProgress(
    ReadingProgress value, {
    required ProgressWriteStamp stamp,
    required CancellationToken cancellation,
  }) async {
    writes.add((value, stamp));
    await gate?.future;
    if (fail) {
      return Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.progressWrite,
        ),
      );
    }
    return inner.saveProgress(value, stamp: stamp, cancellation: cancellation);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProgressTracker tracker(
  Library library,
  ChapterContent c, {
  DateTime Function()? now,
}) => ProgressTracker(
  library: library,
  content: c,
  snapshot: book,
  ordinal: 0,
  catalogRevision: 'catalog',
  now: now,
);
void main() {
  test(
    'ten seconds of changes produce at most six writes and a trailing latest value',
    () {
      fakeAsync((clock) {
        final library = Library();
        final c = content();
        final t = tracker(
          library,
          c,
          now: () => DateTime.utc(2026).add(clock.elapsed),
        );
        for (var i = 0; i <= 100; i++) {
          t.sample(position(c, i / 100), completed: i == 100);
          clock.elapse(const Duration(milliseconds: 100));
        }
        clock.elapse(const Duration(milliseconds: 300));
        expect(library.writes.length, lessThanOrEqualTo(6));
        expect(library.writes.last.$1.position.chapterFraction, 1);
        expect(library.writes.last.$1.completed, isTrue);
        expect(
          library.writes.map((w) => w.$2.sequence).toList(),
          orderedEquals(List.generate(library.writes.length, (i) => i)),
        );
        t.close();
        clock.flushMicrotasks();
        expect(clock.periodicTimerCount + clock.nonPeriodicTimerCount, 0);
      });
    },
  );
  test(
    'slow storage keeps only newest pending snapshot and forced close drains it',
    () {
      fakeAsync((clock) {
        final library = Library()..gate = Completer<void>();
        final c = content();
        final t = tracker(library, c);
        t.sample(position(c, .1), completed: false);
        t.flush();
        clock.flushMicrotasks();
        for (var i = 2; i <= 9; i++) {
          t.sample(position(c, i / 10), completed: false);
          t.flush();
        }
        expect(library.writes, hasLength(1));
        t.close();
        library.gate!.complete();
        clock.flushMicrotasks();
        expect(library.writes.map((w) => w.$1.position.blockFraction), [
          .1,
          .9,
        ]);
        expect(clock.periodicTimerCount + clock.nonPeriodicTimerCount, 0);
      });
    },
  );
  test(
    'restoration suppresses temporary positions; invalid anchors and NaN never write',
    () {
      fakeAsync((clock) {
        final library = Library();
        final c = content();
        final t = tracker(library, c);
        t.restoring(true);
        t.sample(position(c, 0), completed: false);
        t.flush();
        clock.elapse(const Duration(seconds: 4));
        expect(library.writes, isEmpty);
        expect(() => position(c, double.nan), throwsArgumentError);
        t.restoring(false);
        t.sample(
          ReaderPosition(
            contentRevision: 'wrong',
            blockKey: 'wrong',
            blockIndex: 2,
            blockFraction: 0,
            chapterFraction: 0,
          ),
          completed: false,
        );
        t.sample(position(c, .6), completed: false);
        clock.elapse(const Duration(milliseconds: 300));
        expect(library.writes.single.$1.position.blockFraction, .6);
        expect(library.writes.single.$1.position.pixelOffset, isNull);
        t.close();
        clock.flushMicrotasks();
      });
    },
  );
  test(
    'failure retains latest snapshot and manual retry does not duplicate successful writes',
    () {
      fakeAsync((clock) {
        final library = Library()..fail = true;
        final c = content();
        final t = tracker(library, c);
        t.sample(position(c, .7), completed: false);
        clock.elapse(const Duration(milliseconds: 300));
        expect(t.unsaved, isTrue);
        clock.elapse(const Duration(minutes: 1));
        expect(library.writes, hasLength(1));
        library.fail = false;
        t.retry();
        clock.flushMicrotasks();
        expect(t.unsaved, isFalse);
        t.flush();
        clock.flushMicrotasks();
        expect(library.writes, hasLength(2));
        t.close();
        clock.flushMicrotasks();
      });
    },
  );
  test(
    'old chapter completing after a new generation cannot overwrite it or revive cleared history',
    () {
      fakeAsync((clock) {
        final library = Library()..gate = Completer<void>();
        final old = tracker(library, content());
        old.sample(position(content(), .8), completed: false);
        old.flush();
        clock.flushMicrotasks();
        final gate = library.gate!;
        library.gate = null;
        final next = tracker(library, content('two'));
        next.sample(position(content('two'), .1), completed: false);
        next.flush();
        clock.flushMicrotasks();
        gate.complete();
        clock.flushMicrotasks();
        expect(old.unsaved, isTrue);
        library.inner
            .getProgress(book.key, cancellation: CancellationSource().token)
            .then(
              (r) => expect(
                (r as Success<ReadingProgress?>).value!.chapterKey.chapterId,
                'two',
              ),
            );
        clock.flushMicrotasks();
        library.inner.clearHistory(
          book.key,
          cancellation: CancellationSource().token,
        );
        clock.flushMicrotasks();
        next.sample(position(content('two'), .4), completed: false);
        next.flush();
        clock.flushMicrotasks();
        expect(next.unsaved, isTrue);
        old.close();
        next.close();
        clock.flushMicrotasks();
      });
    },
  );
}
