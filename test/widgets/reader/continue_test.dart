import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/continue_reading.dart';

Future<void> finish(ContinueController c) async {
  for (var i = 0; i < 30 && c.loading; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(c.loading, isFalse);
}

Future<void> seed(
  FixtureEnvironment env,
  ChapterKey chapter, {
  int ordinal = 0,
}) async {
  final token = CancellationSource().token;
  final stamp =
      (await env.library.beginProgressSession(
                chapter.novelKey,
                cancellation: token,
              )
              as Success<int>)
          .value;
  await env.library.saveProgress(
    ReadingProgress(
      snapshot: env.source.data.summary(FixtureScenario.multiVolume),
      chapterKey: chapter,
      chapterOrdinalSnapshot: ordinal,
      catalogRevision: 'old',
      position: ReaderPosition(
        contentRevision: 'old',
        blockKey: 'old',
        blockIndex: 0,
        blockFraction: 0,
        chapterFraction: 0,
      ),
      completed: false,
      lastReadAt: DateTime.now(),
    ),
    stamp: ProgressWriteStamp(generation: stamp, sequence: 0),
    cancellation: token,
  );
}

void main() {
  test('no progress starts first chapter without writing history', () async {
    final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
    final key = fixtureNovelKey(FixtureScenario.multiVolume);
    final c = ContinueController(
      novel: key,
      repository: env.novels,
      library: env.library,
    )..onStart();
    await finish(c);
    expect(c.chapter, fixtureChapterKey(FixtureScenario.multiVolume));
    expect(
      (await env.library.getProgress(
                key,
                cancellation: CancellationSource().token,
              )
              as Success<ReadingProgress?>)
          .value,
      isNull,
    );
    c.onDelete();
    c.dispose();
    await env.close();
  });
  test('cached saved chapter continues without source requests', () async {
    final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
    final key = fixtureChapterKey(FixtureScenario.multiVolume, 1);
    await env.novels.loadChapter(
      key,
      mode: ReadMode.refresh,
      cancellation: CancellationSource().token,
    );
    await seed(env, key, ordinal: 1);
    env.source.controls.calls.clear();
    final c = ContinueController(
      novel: key.novelKey,
      repository: env.novels,
      library: env.library,
    )..onStart();
    await finish(c);
    expect(c.chapter, key);
    expect(env.source.controls.calls, isEmpty);
    c.onDelete();
    c.dispose();
    await env.close();
  });
  test(
    'deleted chapter falls back by ordinal and preserves previous record until reader ready',
    () async {
      final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
      final deleted = ChapterKey(
        novelKey: fixtureNovelKey(FixtureScenario.multiVolume),
        chapterId: 'deleted',
      );
      await seed(env, deleted, ordinal: 2);
      final c = ContinueController(
        novel: deleted.novelKey,
        repository: env.novels,
        library: env.library,
      )..onStart();
      await finish(c);
      expect(c.chapter, fixtureChapterKey(FixtureScenario.multiVolume, 2));
      expect(c.usedFallback, isTrue);
      expect(
        (await env.library.getProgress(
                  deleted.novelKey,
                  cancellation: CancellationSource().token,
                )
                as Success<ReadingProgress?>)
            .value!
            .chapterKey,
        deleted,
      );
      c.onDelete();
      c.dispose();
      await env.close();
    },
  );
  test('progress read failure stops navigation and never writes', () async {
    final env = FixtureEnvironment();
    env.library.controls.failNext(
      AppFailure(kind: FailureKind.database, operation: Operation.progressRead),
    );
    final c = ContinueController(
      novel: fixtureNovelKey(FixtureScenario.shortChapter),
      repository: env.novels,
      library: env.library,
    )..onStart();
    await finish(c);
    expect(c.chapter, isNull);
    expect(c.failure!.kind, FailureKind.database);
    expect(env.source.controls.calls, isEmpty);
    c.onDelete();
    c.dispose();
    await env.close();
  });
}
