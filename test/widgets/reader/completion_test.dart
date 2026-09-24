import 'package:flutter/gestures.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/novel_detail/catalog_controller.dart';
import 'package:shiori/features/reader/reader_completion_page.dart';
import 'package:shiori/features/reader/viewport/paper_turn.dart';

class CompletionRepository
    implements
        NovelRepository,
        LocalContentLinkRepository,
        LocalBookProgressRepository {
  CompletionRepository({
    this.local = false,
    this.status = NovelStatus.ongoing,
    this.reversed = false,
  });
  final bool local, reversed;
  final NovelStatus status;
  late final key = NovelKey(
    sourceId: SourceId(local ? 'local' : 'online'),
    novelId: 'book',
  );
  late final keys = List.generate(
    3,
    (i) => ChapterKey(novelKey: key, chapterId: '$i'),
  );
  final updates = StreamController<Result<LoadResult<Catalog>>>.broadcast(
    sync: true,
  );
  int count = 2, loads = 0;
  List<ChapterKey> get order =>
      reversed ? [keys[1], keys[0]] : keys.take(count).toList();
  Catalog get catalog => Catalog(
    novelKey: key,
    volumes: [
      Volume(
        groupId: 'v',
        chapters: List.generate(
          count,
          (i) => Chapter(
            key: keys[i],
            title: 'Chapter $i',
            ordinal: i,
            volumeGroupId: 'v',
          ),
        ),
      ),
    ],
  );
  ChapterContent content(ChapterKey key) => ChapterContent(
    key: key,
    title: 'Chapter ${key.chapterId}',
    blocks: [ParagraphBlock(text: 'Content ${key.chapterId}.')],
  );
  Result<LoadResult<T>> result<T>(T v) => Success(
    LoadResult(
      value: v,
      origin: LoadOrigin.local,
      fetchedAt: DateTime.utc(2026, 1, count),
    ),
  );
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    loads++;
    return result(content(key));
  }

  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    loads++;
    return result(
      NovelDetail(
        summary: NovelSummary(key: key, title: 'Book'),
        status: status,
      ),
    );
  }

  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    loads++;
    return result(catalog);
  }

  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      updates.stream;
  @override
  Future<Result<List<ChapterKey>>> loadReadingOrder(
    NovelKey book, {
    required CancellationToken cancellation,
  }) async => Success(order);
  @override
  Future<Result<List<LocalContentLink>>> loadContentLinks(
    ChapterKey source, {
    required CancellationToken cancellation,
  }) async => const Success([]);
  @override
  Future<Result<BookProgressMetrics>> loadProgressMetrics(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async => Success(
    BookProgressMetrics(
      revision: catalog.revision,
      order: order,
      weights: order.map((_) => 1),
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WeightedRepository extends CompletionRepository
    implements LocalNavigationRepository {
  @override
  Future<Result<List<LocalNavigationEntry>>> loadNavigation(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async => Success([
    LocalNavigationEntry(
      title: 'Start of final chapter',
      chapterKey: order.last,
    ),
  ]);
  _WeightedRepository() : super(local: true);
  @override
  ChapterContent content(ChapterKey key) => ChapterContent(
    key: key,
    title: 'Chapter ${key.chapterId}',
    blocks: List.generate(
      key == keys.first ? 21 : 37,
      (i) => ParagraphBlock(text: 'Paragraph $i. More text in this block.'),
    ),
  );
  @override
  Future<Result<BookProgressMetrics>> loadProgressMetrics(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async => Success(
    BookProgressMetrics(
      revision: catalog.revision,
      order: order,
      weights: order.map((key) => content(key).blocks.length),
    ),
  );
}

class _DelayedDetailRepository extends CompletionRepository {
  final detailGate = Completer<void>();
  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    await detailGate.future;
    return super.loadDetail(key, mode: mode, cancellation: cancellation);
  }
}

class _DelayedCatalogRepository extends CompletionRepository {
  final catalogGate = Completer<Result<LoadResult<Catalog>>>();
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => catalogGate.future;
}

void main() {
  for (final responseIsNewer in [false, true]) {
    testWidgets(
      'catalog fetch time wins across stream/load ordering ($responseIsNewer)',
      (tester) async {
        final repo = _DelayedCatalogRepository();
        final old = repo.catalog;
        repo.count = 3;
        final newer = repo.catalog;
        final controller = CatalogController(repository: repo, novel: repo.key)
          ..onStart();
        Result<LoadResult<Catalog>> observation(Catalog value, int day) =>
            Success(
              LoadResult(
                value: value,
                origin: LoadOrigin.remote,
                fetchedAt: DateTime.utc(2026, 1, day),
              ),
            );
        repo.updates.add(
          responseIsNewer ? observation(old, 1) : observation(newer, 3),
        );
        repo.catalogGate.complete(
          responseIsNewer ? observation(newer, 3) : observation(old, 1),
        );
        await tester.pumpAndSettle();
        expect(controller.loaded!.value.revision, newer.revision);
        final failure = AppFailure(
          kind: FailureKind.network,
          operation: Operation.catalog,
        );
        repo.updates.add(
          Success(
            LoadResult(
              value: old,
              origin: LoadOrigin.local,
              fetchedAt: DateTime.utc(2026),
              isStale: true,
              refreshFailure: failure,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.loaded!.value.revision, newer.revision);
        expect(controller.failure, same(failure));
        // A later deletion is valid, and its successful refresh clears the error.
        repo.updates.add(observation(old, 4));
        await tester.pumpAndSettle();
        expect(controller.loaded!.value.revision, old.revision);
        expect(controller.failure, isNull);
        controller.onDelete();
        await repo.updates.close();
      },
    );
  }

  for (final resize in [false, true]) {
    testWidgets(
      'completion catalog seek survives animation and close/reopen (resize=$resize)',
      (tester) async {
        final repo = _WeightedRepository();
        final library = FixtureLibraryRepository();
        final settings = FixtureSettingsStore();
        await settings.save(
          ReaderSettings(controlsHintSeen: true),
          cancellation: CancellationSource().token,
        );
        Widget open() => ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: repo.order.last,
              repository: repo,
              library: library,
              settings: settings,
            ),
          ),
        );
        final c = repo.content(repo.order.last);
        final token = CancellationSource().token;
        final generation =
            (await library.beginProgressSession(repo.key, cancellation: token)
                    as Success<int>)
                .value;
        await library.saveProgress(
          ReadingProgress(
            snapshot: NovelSummary(key: repo.key, title: 'Book'),
            chapterKey: c.key,
            chapterOrdinalSnapshot: 1,
            catalogRevision: repo.catalog.revision,
            position: ReaderPosition(
              contentRevision: c.contentRevision,
              blockKey: c.blocks.last.blockKey,
              blockIndex: c.blocks.length - 1,
              blockFraction: 1,
              chapterFraction: 1,
            ),
            completed: true,
            lastReadAt: DateTime.utc(2026),
          ),
          stamp: ProgressWriteStamp(generation: generation, sequence: 0),
          cancellation: token,
        );
        await tester.pumpWidget(open());
        await tester.pumpAndSettle();
        ReaderContentView view() =>
            tester.widget<ReaderContentView>(find.byType(ReaderContentView));
        await view().viewportController!.next();
        await tester.pumpAndSettle();
        expect(find.byType(ReaderCompletionPage), findsOneWidget);
        // Hidden layout may restore while the completion page is visible.
        if (resize) {
          tester.view.physicalSize =
              const Size(700, 900) * tester.view.devicePixelRatio;
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpAndSettle();
          expect(view().session!.restoreStatus, ReaderRestoreStatus.ready);
          expect(
            view().session!.progress!.bookProgress!.terminal,
            BookTerminalState.finished,
          );
        }
        await tester.tap(find.text('View contents'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start of final chapter'));
        await tester.pumpAndSettle();
        expect(view().viewportController!.capture()!.chapterFraction, 0);
        expect(view().session!.restoreStatus, ReaderRestoreStatus.ready);
        await view().session!.flushProgress();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        final saved =
            (await library.getProgress(
                      repo.key,
                      cancellation: CancellationSource().token,
                    )
                    as Success<ReadingProgress?>)
                .value!;
        expect(saved.position.chapterFraction, 0);
        expect(saved.bookProgress!.terminal, BookTerminalState.reading);
        await tester.pumpWidget(open());
        await tester.pumpAndSettle();
        expect(view().viewportController!.capture()!.chapterFraction, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await repo.updates.close();
        await library.close();
      },
    );
  }
  testWidgets('new catalog wins over an earlier metadata load', (tester) async {
    final repo = _DelayedDetailRepository();
    final library = FixtureLibraryRepository();
    final reader = ReaderController(
      repository: repo,
      chapter: repo.keys[1],
      library: library,
    )..onStart();
    await tester.pump();
    expect(repo.loads, 2); // chapter and original catalog; detail is pending
    repo.count = 3;
    repo.updates.add(repo.result(repo.catalog));
    repo.detailGate.complete();
    await tester.pumpAndSettle();
    expect(reader.bookMetrics!.order, repo.order);
    final c = reader.content!;
    reader.sampleProgress(
      ReaderPosition(
        contentRevision: c.contentRevision,
        blockKey: c.blocks.last.blockKey,
        blockIndex: 0,
        blockFraction: 1,
        chapterFraction: 1,
      ),
      true,
    );
    await reader.flushProgress();
    expect(reader.progress!.bookProgress!.fraction, 2 / 3);
    expect(reader.progress!.catalogRevision, repo.catalog.revision);
    final acceptedRevision = repo.catalog.revision;
    Future<ReadingProgress> saved() async =>
        (await library.getProgress(
                  repo.key,
                  cancellation: CancellationSource().token,
                )
                as Success<ReadingProgress?>)
            .value!;
    final before = await saved();
    repo.count = 2;
    repo.updates.add(
      Success(
        LoadResult(
          value: repo.catalog,
          origin: LoadOrigin.local,
          fetchedAt: DateTime.utc(2026, 1, 2),
          isStale: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reader.bookMetrics!.order.length, 3);
    expect(reader.progress!.catalogRevision, acceptedRevision);
    repo.updates.add(
      Success(
        LoadResult(
          value: repo.catalog,
          origin: LoadOrigin.remote,
          fetchedAt: DateTime.utc(2026, 1, 4),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reader.flushProgress();
    expect(reader.bookMetrics!.order.length, 2);
    expect(reader.progress!.bookProgress!.fraction, 1);
    expect((await saved()).lastReadAt, before.lastReadAt);

    reader.onDelete();
    await tester.pump();
    await repo.updates.close();
    await library.close();
  });
  testWidgets('older catalog cannot remove next chapter or expose completion', (
    tester,
  ) async {
    final repo = CompletionRepository();
    final library = FixtureLibraryRepository();
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: repo.keys[1],
            repository: repo,
            library: library,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repo.count = 3;
    repo.updates.add(repo.result(repo.catalog));
    await tester.pumpAndSettle();
    repo.count = 2;
    repo.updates.add(repo.result(repo.catalog));
    await tester.pumpAndSettle();
    ReaderContentView view() =>
        tester.widget<ReaderContentView>(find.byType(ReaderContentView));
    expect(view().actions.nextChapter, isNotNull);
    expect(view().actions.bookEnd, isNull);
    await view().viewportController!.next();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderCompletionPage), findsNothing);
    expect(view().content.key, repo.keys[2]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await repo.updates.close();
    await library.close();
  });

  testWidgets(
    'explicit slider seek leaves finished even on one-page final chapter',
    (tester) async {
      final repo = CompletionRepository(local: true);
      final library = FixtureLibraryRepository();
      final settings = FixtureSettingsStore();
      await settings.save(
        ReaderSettings(controlsHintSeen: true),
        cancellation: CancellationSource().token,
      );
      Widget open() => ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: repo.order.last,
            repository: repo,
            library: library,
            settings: settings,
          ),
        ),
      );
      ReaderContentView view() =>
          tester.widget<ReaderContentView>(find.byType(ReaderContentView));
      Future<ReadingProgress> saved() async =>
          (await library.getProgress(
                    repo.key,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value!;
      await tester.pumpWidget(open());
      await tester.pumpAndSettle();
      await view().viewportController!.next();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCompletionPage), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCompletionPage), findsNothing);
      expect(
        (await saved()).bookProgress!.terminal,
        BookTerminalState.finished,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Chapter ').last);
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(.2);
      slider.onChangeEnd!(.2);
      await tester.pumpAndSettle();
      await view().session!.flushProgress();
      expect((await saved()).position.chapterFraction, closeTo(.2, .0001));
      expect((await saved()).bookProgress!.terminal, BookTerminalState.reading);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(open());
      await tester.pumpAndSettle();
      expect(
        view().viewportController!.capture()!.chapterFraction,
        closeTo(.2, .0001),
      );
      expect((await saved()).bookProgress!.terminal, BookTerminalState.reading);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await repo.updates.close();
      await library.close();
    },
  );

  testWidgets('chapter 42.00%, overall 63.00%, slider remains chapter-only', (
    tester,
  ) async {
    final repo = _WeightedRepository();
    final library = FixtureLibraryRepository();
    final settings = FixtureSettingsStore();
    final token = CancellationSource().token;
    await settings.save(
      ReaderSettings(controlsHintSeen: true),
      cancellation: token,
    );
    final chapter = repo.content(repo.order.last);
    final gen =
        (await library.beginProgressSession(repo.key, cancellation: token)
                as Success<int>)
            .value;
    await library.saveProgress(
      ReadingProgress(
        snapshot: NovelSummary(key: repo.key, title: 'Book'),
        chapterKey: chapter.key,
        chapterOrdinalSnapshot: 1,
        catalogRevision: repo.catalog.revision,
        position: ReaderPosition(
          contentRevision: chapter.contentRevision,
          blockKey: chapter.blocks[15].blockKey,
          blockIndex: 15,
          blockFraction: .54,
          chapterFraction: .42,
        ),
        completed: false,
        lastReadAt: DateTime.utc(2026),
        bookProgress: BookProgressSnapshot(fraction: .63, chapterCount: 2),
      ),
      stamp: ProgressWriteStamp(generation: gen, sequence: 0),
      cancellation: token,
    );
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: chapter.key,
            repository: repo,
            library: library,
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    if (find.byKey(const ValueKey('reader-chapter-title')).evaluate().isEmpty) {
      await tester.tapAt(tester.getCenter(find.byType(ReaderContentView)));
      await tester.pumpAndSettle();
    }
    expect(find.text('Chapter 42.00%'), findsOneWidget);
    final requests = repo.loads;
    await tester.tap(find.text('Chapter 42.00%'));
    await tester.pumpAndSettle();
    expect(find.text('Reading progress'), findsOneWidget);
    expect(find.text('63.00%'), findsOneWidget);
    expect(find.text('42.00%'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, closeTo(.42, .0001));
    slider.onChanged!(.2);
    slider.onChangeEnd!(.2);
    await tester.pumpAndSettle();
    final view = tester.widget<ReaderContentView>(
      find.byType(ReaderContentView),
    );
    expect(
      view.viewportController!.capture()!.chapterFraction,
      closeTo(.2, .0001),
    );
    expect(view.content.key, chapter.key);
    expect(repo.loads, requests);
    Navigator.of(tester.element(find.byType(Slider))).pop();
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(ReaderContentView)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('20.00%'), findsOneWidget);
    expect(find.textContaining('63.00%'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await repo.updates.close();
    await library.close();
  });

  testWidgets(
    'completion save failure keeps reader open; retry then returns to shelf',
    (tester) async {
      final repo = CompletionRepository();
      final library = FixtureLibraryRepository();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          homeBuilder: (context, _) => Scaffold(
            body: TextButton(
              child: const Text('Shelf'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BookReaderScreen(
                    chapter: repo.order.last,
                    repository: repo,
                    library: library,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Shelf'));
      await tester.pumpAndSettle();
      AppFailure failure() => AppFailure(
        kind: FailureKind.database,
        operation: Operation.progressWrite,
        retryPolicy: RetryPolicy.manual,
      );
      // The immediate end write and trailing sample write both fail.
      library.controls.failNext(failure());
      library.controls.failNext(failure());
      final view = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView),
      );
      await view.viewportController!.next();
      await tester.pumpAndSettle();
      library.controls.failNext(failure());
      await tester.tap(find.text('Back to bookshelf'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCompletionPage), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to bookshelf'));
      await tester.pumpAndSettle();
      expect(find.text('Shelf'), findsOneWidget);
      expect(find.byType(ReaderCompletionPage), findsNothing);
      final saved =
          (await library.getProgress(
                    repo.key,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value!;
      expect(saved.bookProgress!.terminal, BookTerminalState.caughtUp);
      await tester.pumpWidget(const SizedBox());
      await repo.updates.close();
      await library.close();
    },
  );

  for (final scenario in [
    (true, NovelStatus.unknown, 'Finished'),
    (false, NovelStatus.completed, 'Finished'),
    (false, NovelStatus.ongoing, 'Caught up'),
    (false, NovelStatus.hiatus, 'End of available chapters'),
    (false, NovelStatus.unknown, 'End of available chapters'),
  ]) {
    testWidgets(
      'deliberate end, previous, repeated forward, restart: $scenario',
      (tester) async {
        final repo = CompletionRepository(
          local: scenario.$1,
          status: scenario.$2,
          reversed: scenario.$1,
        );
        final library = FixtureLibraryRepository();
        final settings = FixtureSettingsStore();
        await settings.save(
          ReaderSettings(controlsHintSeen: true),
          cancellation: CancellationSource().token,
        );
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (_) => BookReaderScreen(
                chapter: repo.order.last,
                repository: repo,
                library: library,
                settings: settings,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        ReaderContentView view() =>
            tester.widget<ReaderContentView>(find.byType(ReaderContentView));
        expect(find.byType(ReaderCompletionPage), findsNothing);
        expect(view().actions.nextChapter, isNull);
        final requests = repo.loads;
        // Actual keyboard boundary, not a direct invocation of onBookEnd.
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester
              .widgetList<PaperTurnFold>(find.byType(PaperTurnFold))
              .any(
                (fold) =>
                    fold.progress > 0 &&
                    fold.progress < 1 &&
                    fold.direction == 1,
              ),
          isTrue,
        );
        // Input during the reveal cannot queue another turn.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.byType(ReaderCompletionPage), findsOneWidget);
        expect(find.text(scenario.$3), findsOneWidget);
        expect(repo.loads, requests);
        final before =
            (await library.getProgress(
                      repo.key,
                      cancellation: CancellationSource().token,
                    )
                    as Success<ReadingProgress?>)
                .value!;
        expect(before.bookProgress!.fraction, 1);
        expect(
          before.bookProgress!.terminal,
          bookEndState(local: scenario.$1, status: scenario.$2),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(
          (await library.getProgress(
                    repo.key,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value,
          before,
        );
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byType(ReaderCompletionPage)),
            scrollDelta: const Offset(0, -120),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReaderCompletionPage), findsNothing);
        await view().viewportController!.next();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester
              .widgetList<PaperTurnFold>(find.byType(PaperTurnFold))
              .any(
                (fold) =>
                    fold.progress > 0 &&
                    fold.progress < 1 &&
                    fold.direction == -1,
              ),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReaderCompletionPage), findsNothing);
        expect(view().content.key, repo.order.last);
        // Re-enter by native forward boundary and leave using a mobile swipe.
        await view().viewportController!.next();
        await tester.pumpAndSettle();
        await tester.fling(
          find.byType(ReaderCompletionPage),
          const Offset(250, 0),
          1000,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReaderCompletionPage), findsNothing);
        await view().viewportController!.next();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Read again'));
        await tester.pumpAndSettle();
        expect(find.byType(ReaderCompletionPage), findsNothing);
        expect(view().content.key, repo.order.first);
        // A non-final chapter still advances normally.
        await view().viewportController!.next();
        await tester.pumpAndSettle();
        expect(view().content.key, repo.order.last);
        expect(find.byType(ReaderCompletionPage), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await repo.updates.close();
        await library.close();
      },
    );
  }
  testWidgets('catalog growth removes caught-up screen without moving anchor', (
    tester,
  ) async {
    final repo = CompletionRepository();
    final library = FixtureLibraryRepository();
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: repo.order.last,
            repository: repo,
            library: library,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final view = tester.widget<ReaderContentView>(
      find.byType(ReaderContentView),
    );
    await view.viewportController!.next();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderCompletionPage), findsOneWidget);
    repo.count = 3;
    repo.updates.add(repo.result(repo.catalog));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderCompletionPage), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    final saved =
        (await library.getProgress(
                  repo.key,
                  cancellation: CancellationSource().token,
                )
                as Success<ReadingProgress?>)
            .value!;
    expect(saved.chapterKey, repo.keys[1]);
    expect(saved.bookProgress!.terminal, BookTerminalState.reading);
    expect(saved.bookProgress!.fraction, 2 / 3);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await repo.updates.close();
    await library.close();
  });
}
