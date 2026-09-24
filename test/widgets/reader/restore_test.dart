import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/position/position_resolver.dart';
import 'package:shiori/dev/ui/dev_reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/dev/viewport/reader_viewport.dart';
import 'settings_test.dart' show Store;

class ObservedLibrary implements LibraryRepository {
  ObservedLibrary(this.inner);
  final LibraryRepository inner;
  Completer<Result<ReadingProgress?>>? pending;
  bool failRead = false;
  int sessions = 0;
  CancellationToken? readToken;
  final writes = <ReadingProgress>[];
  @override
  Future<Result<ReadingProgress?>> getProgress(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    readToken = cancellation;
    if (pending != null) return pending!.future;
    if (failRead) {
      return Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.progressRead,
        ),
      );
    }
    return inner.getProgress(key, cancellation: cancellation);
  }

  @override
  Future<Result<int>> beginProgressSession(
    NovelKey key, {
    required CancellationToken cancellation,
  }) {
    sessions++;
    return inner.beginProgressSession(key, cancellation: cancellation);
  }

  @override
  Future<Result<bool>> saveProgress(
    ReadingProgress progress, {
    required ProgressWriteStamp stamp,
    required CancellationToken cancellation,
  }) {
    writes.add(progress);
    return inner.saveProgress(
      progress,
      stamp: stamp,
      cancellation: cancellation,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReaderPosition anchor(ChapterContent content, int index, double fraction) =>
    ReaderPosition(
      contentRevision: content.contentRevision,
      blockKey: content.blocks[index].blockKey,
      blockIndex: index,
      blockFraction: fraction,
      chapterFraction: ReaderPosition.fractionFor(
        blockIndex: index,
        blockFraction: fraction,
        blockCount: content.blocks.length,
      ),
    );

Future<ReadingProgress> seed(
  FixtureEnvironment env,
  FixtureScenario scenario,
  ReaderPosition position, {
  ChapterKey? chapter,
}) async {
  final token = CancellationSource().token;
  final generation =
      (await env.library.beginProgressSession(
                fixtureNovelKey(scenario),
                cancellation: token,
              )
              as Success<int>)
          .value;
  final record = ReadingProgress(
    snapshot: env.source.data.summary(scenario),
    chapterKey: chapter ?? fixtureChapterKey(scenario),
    chapterOrdinalSnapshot: 0,
    catalogRevision: env.source.data.catalog(scenario).revision,
    position: position,
    completed: false,
    lastReadAt: DateTime.utc(2026, 9, 7),
  );
  await env.library.saveProgress(
    record,
    stamp: ProgressWriteStamp(generation: generation, sequence: 0),
    cancellation: token,
  );
  return record;
}

Widget reader(
  FixtureEnvironment env,
  ObservedLibrary library, {
  SettingsStore? settings,
}) => ShioriApp(
  locale: const Locale('en'),
  routes: AppRoutes(
    home: (_) => ReaderScreen(
      chapter: fixtureChapterKey(FixtureScenario.extremeParagraph),
      repository: env.novels,
      library: library,
      settings: settings,
    ),
  ),
);

void main() {
  test(
    'semantic resolver handles revisions, occurrence identity, corrupt index and stale pixel hints',
    () {
      final old = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.typography),
        title: 'old',
        blocks: [
          ParagraphBlock(text: 'same'),
          ParagraphBlock(text: 'same'),
          ParagraphBlock(text: 'end'),
        ],
      );
      final saved = anchor(old, 1, .4);
      final changed = ChapterContent(
        key: old.key,
        title: 'new',
        blocks: [
          HeadingBlock(text: 'insert'),
          ...old.blocks,
        ],
      );
      final found = resolveReaderPosition(changed, saved);
      expect(found.usedFallback, isFalse);
      expect(found.position.blockIndex, 2);
      expect(found.position.blockFraction, .4);
      final inconsistent = ReaderPosition(
        contentRevision: old.contentRevision,
        blockKey: saved.blockKey,
        blockIndex: 999,
        blockFraction: .4,
        chapterFraction: .99,
        pixelOffset: 1000000,
        layoutKey: 'old-layout',
      );
      final same = resolveReaderPosition(old, inconsistent);
      expect(same.position, saved);
      expect(same.position.pixelOffset, isNull);
      final missing = ReaderPosition(
        contentRevision: 'old',
        blockKey: 'gone',
        blockIndex: 999,
        blockFraction: .2,
        chapterFraction: .625,
      );
      final nearby = resolveReaderPosition(changed, missing);
      expect(nearby.usedFallback, isTrue);
      expect(nearby.position.blockIndex, 2);
      expect(nearby.position.blockFraction, .5);
    },
  );

  for (final mode in [ReaderMode.paged]) {
    testWidgets(
      '${mode.name}: reopened persisted anchor survives delayed settings; no temporary writes',
      (tester) async {
        final env = FixtureEnvironment(
          scenario: FixtureScenario.extremeParagraph,
        );
        final content = env.source.data.content(
          FixtureScenario.extremeParagraph,
        );
        final saved = await seed(
          env,
          FixtureScenario.extremeParagraph,
          anchor(content, 0, .63),
        );
        final library = ObservedLibrary(env.library);
        final settings = Store()..loading = Completer<Result<ReaderSettings>>();
        await tester.pumpWidget(reader(env, library, settings: settings));
        await tester.pump(const Duration(seconds: 3));
        expect(library.writes, isEmpty);
        expect(find.byType(PagedReaderViewport), findsNothing);
        settings.loading!.complete(
          Success(ReaderSettings(mode: mode, fontSize: 24)),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        expect(library.writes, isNotEmpty);
        expect(
          library.writes.every(
            (p) =>
                p.position.blockKey == saved.position.blockKey &&
                (p.position.blockFraction - .63).abs() < .005,
          ),
          isTrue,
        );
        final stable = library.writes.last.position;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        library.writes.clear();
        await tester.pumpWidget(
          reader(
            env,
            library,
            settings: Store()..value = ReaderSettings(mode: mode, fontSize: 24),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        final restored = library.writes.last.position;
        expect(restored.blockKey, stable.blockKey);
        final error =
            ((restored.blockFraction - stable.blockFraction) *
                    (content.blocks.first as ParagraphBlock).text.runes.length)
                .abs();
        expect(
          error,
          lessThanOrEqualTo(1),
          reason: 'same-layout code-point error: $error',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await env.close();
      },
    );

    testWidgets(
      '${mode.name}: extreme paragraph rechunk, font and rotation keep the semantic target',
      (tester) async {
        final content = const FixtureData().content(
          FixtureScenario.extremeParagraph,
        );
        final paged = PagedReaderController(),
            scroll = ReaderViewportController();
        final target = anchor(content, 0, .51);
        final samples = <ReaderPosition>[];
        Widget viewport(double width, double height, double font, int chunk) =>
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: mode == ReaderMode.paged
                      ? PagedReaderViewport(
                          content: content,
                          controller: paged,
                          initialPosition: target,
                          maxChunkCodePoints: chunk,
                          textStyle: TextStyle(fontSize: font, height: 1.7),
                          onPosition: (p, _) => samples.add(p),
                        )
                      : ReaderViewport(
                          content: content,
                          controller: scroll,
                          initialPosition: target,
                          maxChunkCodePoints: chunk,
                          textStyle: TextStyle(fontSize: font, height: 1.7),
                          onPosition: (p, _) => samples.add(p),
                        ),
                ),
              ),
            );
        await tester.pumpWidget(viewport(320, 500, 20, 800));
        await tester.pumpAndSettle();
        final before = samples.last;
        samples.clear();
        await tester.pumpWidget(viewport(680, 300, 28, 160));
        await tester.pumpAndSettle();
        expect(samples, isNotEmpty);
        expect(samples.every((p) => p.blockKey == before.blockKey), isTrue);
        final error =
            ((samples.last.blockFraction - before.blockFraction) *
                    (content.blocks.first as ParagraphBlock).text.runes.length)
                .abs();
        expect(
          error,
          lessThanOrEqualTo(40),
          reason: 'changed-layout code-point error: $error',
        );
        if (mode == ReaderMode.scroll) {
          expect(scroll.visibleBlocks, contains(0));
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'leaving while progress read is pending cancels it and never begins a write session',
    (tester) async {
      final env = FixtureEnvironment(
        scenario: FixtureScenario.extremeParagraph,
      );
      final library = ObservedLibrary(env.library)
        ..pending = Completer<Result<ReadingProgress?>>();
      await tester.pumpWidget(reader(env, library));
      await tester.pump(const Duration(milliseconds: 100));
      expect(library.readToken, isNotNull);
      expect(library.sessions, 0);
      await tester.pumpWidget(const SizedBox());
      expect(library.readToken!.isCancelled, isTrue);
      library.pending!.complete(const Success(null));
      await tester.pumpAndSettle();
      expect(library.sessions, 0);
      expect(library.writes, isEmpty);
      await env.close();
    },
  );

  testWidgets(
    'read failure permits reading but preserves old progress until explicit retry',
    (tester) async {
      final env = FixtureEnvironment(
        scenario: FixtureScenario.extremeParagraph,
      );
      await seed(
        env,
        FixtureScenario.extremeParagraph,
        anchor(
          env.source.data.content(FixtureScenario.extremeParagraph),
          0,
          .7,
        ),
      );
      final library = ObservedLibrary(env.library)..failRead = true;
      await tester.pumpWidget(reader(env, library));
      await tester.pumpAndSettle();
      expect(find.byType(PagedReaderViewport), findsOneWidget);
      await tester.drag(
        find.byType(PagedReaderViewport),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(library.writes, isEmpty);
      expect(library.sessions, 0);
      library.failRead = false;
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Could not read saved progress'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect(library.writes, isNotEmpty);
      expect(
        library.writes.every(
          (p) => (p.position.blockFraction - .7).abs() < .005,
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
  );

  testWidgets(
    'missing key surfaces localized fallback and writes only the resolved position',
    (tester) async {
      final env = FixtureEnvironment(
        scenario: FixtureScenario.extremeParagraph,
      );
      await seed(
        env,
        FixtureScenario.extremeParagraph,
        ReaderPosition(
          contentRevision: 'removed',
          blockKey: 'gone',
          blockIndex: 10,
          blockFraction: .1,
          chapterFraction: .6,
        ),
      );
      final library = ObservedLibrary(env.library);
      await tester.pumpWidget(reader(env, library));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(
        find.text('Content changed. Restored to a nearby position.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        library.writes.every(
          (p) => (p.position.blockFraction - .6).abs() < .005,
        ),
        isTrue,
      );
      expect(library.writes, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
  );

  testWidgets(
    'a different explicitly opened chapter does not inherit the saved chapter anchor',
    (tester) async {
      final env = FixtureEnvironment(
        scenario: FixtureScenario.extremeParagraph,
      );
      await seed(
        env,
        FixtureScenario.extremeParagraph,
        anchor(
          env.source.data.content(FixtureScenario.extremeParagraph),
          0,
          .7,
        ),
        chapter: fixtureChapterKey(FixtureScenario.extremeParagraph, 1),
      );
      final library = ObservedLibrary(env.library);
      await tester.pumpWidget(reader(env, library));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect(library.writes.last.position.blockFraction, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
  );

  testWidgets(
    'late image geometry follows the user current anchor, never the initial saved anchor',
    (tester) async {
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.singleImage),
        title: 'image',
        blocks: [ImageBlock(media: fixtureMediaRef(0))],
      );
      final controller = ReaderViewportController();
      Widget viewport(double height) => MaterialApp(
        home: ReaderViewport(
          content: content,
          controller: controller,
          initialPosition: anchor(content, 0, .5),
          imageBuilder: (_, _) => SizedBox(height: height),
        ),
      );
      await tester.pumpWidget(viewport(2000));
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockFraction, closeTo(.5, .001));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -160));
      await tester.pumpAndSettle();
      final moved = controller.capture()!.blockFraction;
      expect(moved, greaterThan(.5));
      await tester.pumpWidget(viewport(3000));
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockFraction, closeTo(moved, .001));
      controller.restore(anchor(content, 0, .1));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
