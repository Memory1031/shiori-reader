import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/cache/cache_screen.dart';
import 'package:shiori/features/cache/prefetch_sheet.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_cache_screen.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/home/desktop_shell.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/capabilities.dart';

import '../cache/harness.dart' show DesktopCache;
import 'completion_test.dart' show CompletionRepository;
import 'settings_test.dart' show Store;

class CachedRepository extends CompletionRepository {
  CachedRepository() {
    count = 3;
  }
  final calls = <(String, ReadMode, ChapterKey?)>[];
  Completer<Result<LoadResult<ChapterContent>>>? pending;
  CancellationToken? pendingToken;
  ChapterKey? missing;
  bool wrongKey = false;
  @override
  ChapterContent content(ChapterKey key) => ChapterContent(
    key: key,
    title: 'Chapter ${key.chapterId}',
    blocks: [
      for (var i = 0; i < 40; i++)
        ParagraphBlock(text: '$i ${'离线正文与 offline reading。' * 8}'),
      if (key == keys[1])
        ImageBlock(
          media: MediaRef(
            sourceId: key.novelKey.sourceId,
            mediaId: 'missing-image',
          ),
          width: 200,
          height: 200,
        ),
    ],
  );
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    calls.add(('chapter', mode, key));
    if (mode == ReadMode.cacheOnly && pending != null) {
      final gate = pending!;
      pending = null;
      pendingToken = cancellation;
      return gate.future;
    }
    if (key == missing) {
      return Failure(
        AppFailure(
          kind: FailureKind.cache,
          operation: Operation.chapter,
          context: FailureContext.cacheMiss,
        ),
      );
    }
    return result(
      content(wrongKey && mode == ReadMode.cacheOnly ? keys[0] : key),
    );
  }

  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    calls.add(('catalog', mode, null));
    if (key != this.key) {
      return Future.value(
        result(
          Catalog(
            novelKey: key,
            volumes: [
              Volume(
                groupId: 'cached',
                chapters: [
                  Chapter(
                    key: ChapterKey(novelKey: key, chapterId: 'saved'),
                    title: 'Saved chapter',
                    ordinal: 0,
                    volumeGroupId: 'cached',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return super.loadCatalog(key, mode: mode, cancellation: cancellation);
  }

  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    calls.add(('detail', mode, null));
    return super.loadDetail(key, mode: mode, cancellation: cancellation);
  }
}

class Library implements LibraryRepository, LibraryBookRemoval {
  final backing = FixtureLibraryRepository();
  final writes = <ReadingProgress>[];
  bool failWrites = false, failReads = false;
  Completer<void>? pending;
  int sessions = 0;
  @override
  Stream<NovelKey> get removedBooks => backing.removedBooks;
  @override
  Future<Result<ReadingProgress?>> getProgress(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => failReads
      ? Future.value(
          Failure(
            AppFailure(
              kind: FailureKind.database,
              operation: Operation.progressRead,
            ),
          ),
        )
      : backing.getProgress(key, cancellation: cancellation);
  @override
  Future<Result<int>> beginProgressSession(
    NovelKey key, {
    required CancellationToken cancellation,
  }) {
    sessions++;
    return backing.beginProgressSession(key, cancellation: cancellation);
  }

  @override
  Future<Result<bool>> saveProgress(
    ReadingProgress progress, {
    required ProgressWriteStamp stamp,
    required CancellationToken cancellation,
    LoadResult<Catalog>? catalog,
  }) async {
    writes.add(progress);
    await pending?.future;
    if (failWrites) {
      return Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.progressWrite,
          retryPolicy: RetryPolicy.manual,
        ),
      );
    }
    return backing.saveProgress(
      progress,
      stamp: stamp,
      cancellation: cancellation,
      catalog: catalog,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class MissingImages implements ImageRepository {
  final modes = <ReadMode>[];
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    modes.add(mode);
    return Failure(
      AppFailure(
        kind: FailureKind.cache,
        operation: Operation.media,
        context: FailureContext.cacheMiss,
      ),
    );
  }
}

class Cache extends DesktopCache {
  Cache(CachedRepository repo) : super(books: 0) {
    data = CacheOverview(
      textBytes: 1024,
      imageBytes: 0,
      books: {
        repo.key: '缓存测试与 long offline book title',
        for (var i = 0; i < 20; i++) novel(i + 1): 'Other cached book $i',
      },
      chapters: [
        for (final key in repo.keys)
          CachedChapter(
            key: key,
            title: 'Offline chapter ${key.chapterId}',
            imageCount: key == repo.keys[1] ? 1 : 0,
            savedImages: 0,
          ),
      ],
    );
  }
  final pins = <ChapterKey, int>{};
  @override
  VoidCallback pinChapter(ChapterKey chapter) {
    pins.update(chapter, (n) => n + 1, ifAbsent: () => 1);
    var released = false;
    return () {
      expect(released, isFalse, reason: 'A lease is released only once');
      released = true;
      pins.update(chapter, (n) => n - 1);
    };
  }
}

class Harness {
  Harness(this.tester);
  final WidgetTester tester;
  final repo = CachedRepository();
  final library = Library();
  final images = MissingImages();
  late final cache = Cache(repo);
  final navigator = GlobalKey<NavigatorState>();
  final repaint = GlobalKey();
  late Route<void> originalRoute;
  late ReaderController original;
  late ReaderPosition anchor;
  AppLocalizations get l =>
      AppLocalizations.of(tester.element(find.byType(CacheScreen)));
  Finder row(int i) => find.byKey(ValueKey(('cache-chapter', repo.keys[i])));
  ScrollableState get scroll => tester.state(
    find
        .descendant(
          of: find.byType(CacheScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  Future<void> pump({
    Size? size,
    String lang = 'en',
    double scale = 1,
    bool shell = false,
  }) async {
    tester.view
      ..physicalSize =
          size ??
          (debugDefaultTargetPlatformOverride == TargetPlatform.windows
              ? const Size(1280, 900)
              : const Size(390, 850))
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShioriApp(
        locale: Locale(lang),
        navigatorKey: navigator,
        overlayBuilder: (context, child) {
          final scaled = MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child,
          );
          final theme = Theme.of(context);
          return RepaintBoundary(
            key: repaint,
            child: Platform.environment['SHIORI_CACHE_FONT'] == null
                ? scaled
                : Theme(
                    data: theme.copyWith(
                      appBarTheme: theme.appBarTheme.copyWith(
                        titleTextStyle: theme.appBarTheme.titleTextStyle
                            ?.copyWith(fontFamily: 'Roboto'),
                      ),
                    ),
                    child: scaled,
                  ),
          );
        },
        routes: AppRoutes(
          home: (_) => shell
              ? ReadingHome(
                  repository: repo,
                  library: library.backing,
                  sources: const [],
                  cache: cache,
                )
              : const Scaffold(body: Text('Home')),
        ),
      ),
    );
    final context = navigator.currentContext!;
    originalRoute = platformPageRoute<void>(
      context,
      builder: (_) => BookReaderScreen(
        chapter: repo.keys[0],
        repository: repo,
        library: library,
        cache: cache,
        images: images,
        settings: Store()..value = ReaderSettings(controlsHintSeen: true),
      ),
    );
    unawaited(navigator.currentState!.push(originalRoute));
    await tester.pumpAndSettle();
    original = tester
        .widget<ReaderContentView>(find.byType(ReaderContentView).first)
        .session!;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    anchor = original.currentPosition!;
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> manage() async {
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip(
        AppLocalizations.of(
          tester.element(find.byType(BookReaderScreen)),
        ).moreActions,
      ),
    );
    await tester.pumpAndSettle();
    final locale = AppLocalizations.of(
      tester.element(find.byType(BookReaderScreen)),
    );
    await tester.tap(find.text(locale.prefetchTitle));
    await tester.pumpAndSettle();
    expect(find.byType(PrefetchPanel), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(locale.cacheTitle),
      150,
      scrollable: find
          .descendant(
            of: find.byType(PrefetchPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(locale.cacheTitle));
    await tester.pumpAndSettle();
    expect(find.byType(PrefetchPanel, skipOffstage: false), findsNothing);
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('reader-panel')), findsNothing);
    expect(find.byType(ReaderCacheScreen), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(CacheScreen))),
      same(navigator.currentState),
    );
    expect(find.byType(CacheScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(('cache-book', repo.key))),
      150,
      scrollable: find
          .descendant(
            of: find.byType(CacheScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
  }

  Future<void> back() async {
    if (debugDefaultTargetPlatformOverride == TargetPlatform.windows) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    } else {
      await tester.binding.handlePopRoute();
    }
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(String name) async {
    final directory = Platform.environment['SHIORI_CACHE_SCREENSHOTS'];
    if (directory == null) return;
    final boundary =
        repaint.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(cache.pins.values.every((n) => n == 0), isTrue);
    await repo.updates.close();
    await cache.prefetch.events.close();
    await library.backing.close();
    expect(tester.takeException(), isNull);
  }
}

const platforms = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.windows,
});
void main() {
  testWidgets(
    'A cache B back cache C back home retains cache identity and last source anchor',
    (tester) async {
      final h = Harness(tester);
      await h.pump();
      await h.manage();
      h.scroll.position.jumpTo(100);
      await tester.pumpAndSettle();
      final page = tester.element(find.byType(CacheScreen));
      final state = tester.state(find.byType(CacheScreen));
      final expansion = tester.state(find.byType(ExpansionTile).first);
      final offset = h.scroll.position.pixels;
      h.repo.calls.clear();
      final sourceWrites = h.library.writes
          .where((p) => p.chapterKey == h.repo.keys[0])
          .length;
      await tester.tap(h.row(1));
      await tester.pumpAndSettle();
      expect(h.original.isClosed, isTrue);
      expect(h.originalRoute.isActive, isFalse);
      expect(
        find.byType(BookReaderScreen, skipOffstage: false),
        findsOneWidget,
      );
      final reader = tester.widget<BookReaderScreen>(
        find.byType(BookReaderScreen),
      );
      expect(reader.chapter, h.repo.keys[1]);
      expect(reader.offline, isTrue);
      expect(
        h.repo.calls.every((call) => call.$2 == ReadMode.cacheOnly),
        isTrue,
      );
      expect(
        h.library.writes
            .lastWhere((p) => p.chapterKey == h.repo.keys[0])
            .position,
        h.anchor,
      );
      await h.back();
      expect(tester.element(find.byType(CacheScreen)), same(page));
      expect(tester.state(find.byType(CacheScreen)), same(state));
      expect(tester.state(find.byType(ExpansionTile).first), same(expansion));
      expect(h.scroll.position.pixels, closeTo(offset, .01));
      final retiredWrites = h.library.writes
          .where((p) => p.chapterKey == h.repo.keys[0])
          .length;
      expect(retiredWrites, greaterThanOrEqualTo(sourceWrites));
      await tester.ensureVisible(h.row(2));
      await tester.pump();
      final offsetC = h.scroll.position.pixels;
      await tester.tap(h.row(2));
      await tester.pumpAndSettle();
      expect(
        tester.widget<BookReaderScreen>(find.byType(BookReaderScreen)).chapter,
        h.repo.keys[2],
      );
      expect(
        h.library.writes.where((p) => p.chapterKey == h.repo.keys[0]).length,
        retiredWrites,
      );
      await h.back();
      expect(tester.element(find.byType(CacheScreen)), same(page));
      expect(h.scroll.position.pixels, closeTo(offsetC, .01));
      await h.back();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(BookReaderScreen, skipOffstage: false), findsNothing);
      await h.close();
    },
    variant: platforms,
  );

  testWidgets(
    'viewing cache only returns to unchanged A without a residual sheet',
    (tester) async {
      final h = Harness(tester);
      await h.pump();
      await h.manage();
      await h.back();
      expect(h.originalRoute.isCurrent, isTrue);
      expect(h.original.isClosed, isFalse);
      expect(h.original.currentPosition, h.anchor);
      expect(find.byType(PrefetchPanel), findsNothing);
      await h.close();
    },
    variant: platforms,
  );

  testWidgets(
    'missing or mismatched target preserves A and does not save until a readable selection',
    (tester) async {
      final h = Harness(tester);
      await h.pump();
      await h.manage();
      final writes = h.library.writes.length, sessions = h.library.sessions;
      h.repo.missing = h.repo.keys[1];
      h.repo.calls.clear();
      await tester.tap(h.row(1));
      await tester.pumpAndSettle();
      expect(find.text(h.l.cacheMissMessage), findsOneWidget);
      expect(h.originalRoute.isActive, isTrue);
      expect(h.library.writes.length, writes);
      expect(h.library.sessions, sessions);
      expect(h.repo.calls, [('chapter', ReadMode.cacheOnly, h.repo.keys[1])]);
      h.repo.missing = null;
      h.repo.wrongKey = true;
      await tester.ensureVisible(h.row(2));
      await tester.pump();
      await tester.tap(h.row(2));
      await tester.pumpAndSettle();
      expect(h.originalRoute.isActive, isTrue);
      expect(h.library.sessions, sessions);
      h.repo.wrongKey = false;
      await tester.ensureVisible(h.row(2));
      await tester.pump();
      await tester.tap(h.row(2));
      await tester.pumpAndSettle();
      expect(h.original.isClosed, isTrue);
      await h.close();
    },
    variant: platforms,
  );

  testWidgets('save failure keeps cache and A; retry can then retire it', (
    tester,
  ) async {
    final h = Harness(tester);
    await h.pump();
    h.library.failWrites = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final unsaved = h.original.currentPosition;
    await h.manage();
    final page = tester.element(find.byType(CacheScreen));
    await tester.tap(h.row(1));
    await tester.pumpAndSettle();
    expect(h.originalRoute.isActive, isTrue);
    expect(h.original.isClosed, isFalse);
    expect(h.original.currentPosition, unsaved);
    expect(tester.element(find.byType(CacheScreen)), same(page));
    expect(find.text(h.l.readerProgressUnsaved), findsOneWidget);
    await h.back();
    expect(h.originalRoute.isCurrent, isTrue);
    h.library.failWrites = false;
    await h.original.retryProgress();
    await tester.pumpAndSettle();
    expect(h.original.hasUnsavedProgress, isFalse);
    // Chrome remained expanded beneath the cache page.
    await tester.tap(
      find.byTooltip(
        AppLocalizations.of(
          tester.element(find.byType(BookReaderScreen)),
        ).moreActions,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reading cache'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline content'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    await tester.tap(h.row(1));
    await tester.pumpAndSettle();
    expect(h.originalRoute.isActive, isFalse);
    await h.close();
  }, variant: platforms);

  for (final race in [
    'double tap',
    'back',
    'cover',
    'delete',
    'retire source',
    'dispose',
  ]) {
    testWidgets(
      'pending cache validation rejects stale interaction: $race',
      (tester) async {
        final h = Harness(tester);
        await h.pump();
        await h.manage();
        final gate = Completer<Result<LoadResult<ChapterContent>>>();
        h.repo.pending = gate;
        h.repo.calls.clear();
        await tester.tap(h.row(1));
        await tester.pump();
        switch (race) {
          case 'double tap':
            await tester.tap(h.row(1));
            await tester.ensureVisible(h.row(2));
            await tester.pump();
            await tester.tap(h.row(2));
          case 'back':
            await h.back();
          case 'cover':
            unawaited(
              h.navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Cover')),
                ),
              ),
            );
            await tester.pumpAndSettle();
          case 'delete':
            await h.library.backing.removeOnlineBook(
              h.repo.key,
              cancellation: CancellationSource().token,
            );
            await tester.pump();
          case 'retire source':
            h.navigator.currentState!.removeRoute(h.originalRoute);
            await tester.pump();
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
        }
        gate.complete(h.repo.result(h.repo.content(h.repo.keys[1])));
        await tester.pumpAndSettle();
        if (race == 'double tap') {
          expect(
            find.byType(BookReaderScreen, skipOffstage: false),
            findsOneWidget,
          );
          expect(
            tester
                .widget<BookReaderScreen>(find.byType(BookReaderScreen))
                .chapter,
            h.repo.keys[1],
          );
        } else {
          expect(
            find.byType(BookReaderScreen),
            race == 'back' ? findsOneWidget : findsNothing,
          );
        }
        expect(
          h.repo.calls.where(
            (call) =>
                call.$1 == 'chapter' &&
                call.$2 == ReadMode.cacheOnly &&
                call.$3 == h.repo.keys[2],
          ),
          isEmpty,
        );
        if (race == 'back' || race == 'dispose') {
          expect(h.repo.pendingToken!.isCancelled, isTrue);
        }
        await h.close();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
  testWidgets(
    'new offline route restores a different book target and keeps cache-only modes',
    (tester) async {
      final h = Harness(tester);
      final book = NovelKey(
        sourceId: SourceId('online'),
        novelId: 'saved-book',
      );
      final target = ChapterKey(novelKey: book, chapterId: 'saved');
      final content = h.repo.content(target);
      final position = ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks[20].blockKey,
        blockIndex: 20,
        blockFraction: .25,
        chapterFraction: .50625,
      );
      final token = CancellationSource().token;
      final generation =
          (await h.library.beginProgressSession(book, cancellation: token)
                  as Success<int>)
              .value;
      final catalog =
          (await h.repo.loadCatalog(
                    book,
                    mode: ReadMode.cacheOnly,
                    cancellation: token,
                  )
                  as Success<LoadResult<Catalog>>)
              .value;
      await h.library.saveProgress(
        ReadingProgress(
          snapshot: NovelSummary(key: book, title: 'Saved book'),
          chapterKey: target,
          chapterOrdinalSnapshot: 0,
          catalogRevision: catalog.value.revision,
          position: position,
          completed: false,
          lastReadAt: DateTime.utc(2026),
        ),
        stamp: ProgressWriteStamp(generation: generation, sequence: 0),
        cancellation: token,
      );
      h.cache.data = CacheOverview(
        textBytes: 1024,
        imageBytes: 0,
        books: {book: 'Saved book'},
        chapters: [
          CachedChapter(
            key: target,
            title: 'Saved chapter',
            imageCount: 0,
            savedImages: 0,
          ),
        ],
      );
      await h.pump();
      // This book has a single cached row and a different identity from A.
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reading cache'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Offline content'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      h.repo.calls.clear();
      await tester.tap(find.byKey(ValueKey(('cache-chapter', target))));
      await tester.pumpAndSettle();
      final widget = tester.widget<BookReaderScreen>(
        find.byType(BookReaderScreen),
      );
      expect(widget.startAtBeginning, isFalse);
      final reader = tester
          .widget<ReaderContentView>(find.byType(ReaderContentView).first)
          .session!;
      expect(reader.usedFallback, isFalse);
      expect(reader.currentPosition!.blockIndex, greaterThan(15));
      expect(
        h.repo.calls.every((call) => call.$2 == ReadMode.cacheOnly),
        isTrue,
      );
      await h.close();
    },
  );

  testWidgets(
    'readable text with missing images opens and image loads remain strictly offline',
    (tester) async {
      final h = Harness(tester);
      await h.pump();
      await h.manage();
      await tester.tap(h.row(1));
      await tester.pumpAndSettle();
      final view = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView).first,
      );
      final content = view.content;
      view.viewportController!.restore(
        ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks.last.blockKey,
          blockIndex: content.blocks.length - 1,
          blockFraction: 0,
          chapterFraction: .98,
        ),
      );
      await tester.pumpAndSettle();
      expect(h.originalRoute.isActive, isFalse);
      expect(h.images.modes, isNotEmpty);
      expect(
        h.images.modes.every((mode) => mode == ReadMode.cacheOnly),
        isTrue,
      );
      await h.close();
    },
  );

  testWidgets(
    'old progress read failure keeps source protected during cache selection',
    (tester) async {
      final h = Harness(tester);
      h.library.failReads = true;
      await h.pump();
      await h.manage();
      await tester.tap(h.row(1));
      await tester.pumpAndSettle();
      expect(h.original.restoreFailure, isNotNull);
      expect(h.originalRoute.isActive, isTrue);
      expect(find.text(h.l.readerRestoreReadFailed), findsOneWidget);
      expect(h.library.writes, isEmpty);
      await h.close();
    },
    variant: platforms,
  );

  for (final race in [
    'complete',
    'double tap',
    'back',
    'delete',
    'dispose',
    'background',
    'obsolete',
  ]) {
    testWidgets(
      'latest stable source save is a real barrier: $race',
      (tester) async {
        final h = Harness(tester);
        await h.pump();
        final gate = Completer<void>();
        h.library.pending = gate;
        final content = h.original.content!;
        final view = tester.widget<ReaderContentView>(
          find.byType(ReaderContentView).first,
        );
        view.viewportController!.restore(
          ReaderPosition(
            contentRevision: content.contentRevision,
            blockKey: content.blocks[20].blockKey,
            blockIndex: 20,
            blockFraction: .35,
            chapterFraction: .5,
          ),
        );
        await tester.pumpAndSettle();
        final latest = h.original.currentPosition!;
        expect(latest, isNot(h.anchor));
        await h.manage();
        final writes = h.library.writes.length;
        await tester.tap(h.row(1));
        await tester.pump();
        expect(h.originalRoute.isActive, isTrue);
        expect(find.byType(BookReaderScreen), findsNothing);
        expect(h.library.writes.length, writes);
        switch (race) {
          case 'double tap':
            await tester.tap(h.row(1));
            await tester.ensureVisible(h.row(2));
            await tester.pump();
            await tester.tap(h.row(2));
          case 'back':
            await h.back();
          case 'delete':
            await h.library.backing.removeOnlineBook(
              h.repo.key,
              cancellation: CancellationSource().token,
            );
            await tester.pump();
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          case 'background':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            await tester.pump();
          case 'obsolete':
            await h.library.backing.beginProgressSession(
              h.repo.key,
              cancellation: CancellationSource().token,
            );
          default:
            break;
        }
        h.library.pending = null;
        gate.complete();
        await tester.pumpAndSettle();
        if (race == 'complete' || race == 'double tap') {
          expect(h.originalRoute.isActive, isFalse);
          expect(
            h.library.writes
                .lastWhere((p) => p.chapterKey == h.repo.keys[0])
                .position
                .values
                .take(4)
                .toList(),
            latest.values.take(4).toList(),
          );
          expect(
            tester
                .widget<BookReaderScreen>(find.byType(BookReaderScreen))
                .chapter,
            h.repo.keys[1],
          );
        } else {
          expect(h.originalRoute.isActive, race != 'dispose');
          expect(
            find.byType(BookReaderScreen),
            race == 'back' ? findsOneWidget : findsNothing,
          );
          if (race == 'obsolete') {
            expect(h.original.progress!.obsolete, isTrue);
            expect(
              find.text(
                '${h.l.readerReadingProgress} · ${h.l.readerProgressNotSaved}',
              ),
              findsOneWidget,
            );
            expect(find.byType(SnackBarAction), findsNothing);
          }
        }
        if (race == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await h.close();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'Windows uses root cache and reader without mutating the workspace navigator',
    (tester) async {
      final h = Harness(tester);
      await h.pump(shell: true);
      final workspace = tester.state<NavigatorState>(
        find
            .descendant(
              of: find.byType(DesktopShell, skipOffstage: false),
              matching: find.byType(Navigator, skipOffstage: false),
            )
            .first,
      );
      expect(workspace, isNot(same(h.navigator.currentState)));
      await h.manage();
      await tester.tap(h.row(1));
      await tester.pumpAndSettle();
      expect(
        Navigator.of(tester.element(find.byType(BookReaderScreen))),
        same(h.navigator.currentState),
      );
      expect(find.byType(DesktopShell), findsNothing);
      await h.back();
      expect(
        Navigator.of(tester.element(find.byType(CacheScreen))),
        same(h.navigator.currentState),
      );
      await h.back();
      expect(find.byType(DesktopShell), findsOneWidget);
      expect(workspace.canPop(), isFalse);
      await h.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'iOS edge swipe returns B to the retained cache and then to home',
    (tester) async {
      final h = Harness(tester);
      await h.pump();
      await h.manage();
      final page = tester.element(find.byType(CacheScreen));
      await tester.tap(h.row(1));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(1, 400), const Offset(340, 0));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(CacheScreen)), same(page));
      await tester.dragFrom(const Offset(1, 400), const Offset(340, 0));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      await h.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final scene in [
    (TargetPlatform.android, 'zh', const Size(390, 850), 1.0, Brightness.light),
    (TargetPlatform.iOS, 'en', const Size(320, 850), 1.5, Brightness.dark),
    (TargetPlatform.windows, 'zh', const Size(900, 900), 1.5, Brightness.dark),
    (
      TargetPlatform.windows,
      'en',
      const Size(1600, 900),
      1.0,
      Brightness.light,
    ),
  ]) {
    testWidgets(
      'render cache open loading failure and retained list ${scene.$1}/${scene.$2}/${scene.$3.width}',
      (tester) async {
        final font = Platform.environment['SHIORI_CACHE_FONT'];
        if (font != null) {
          await tester.runAsync(() async {
            final data = ByteData.sublistView(await File(font).readAsBytes());
            for (final family in [
              'Roboto',
              'MicrosoftYaHeiUI',
              'Microsoft YaHei UI',
              'CupertinoSystemText',
              'CupertinoSystemDisplay',
              'serif',
            ]) {
              final loader = FontLoader(family)..addFont(Future.value(data));
              await loader.load();
            }
            final icons = FontLoader('MaterialIcons')
              ..addFont(
                File(
                  '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                ).readAsBytes().then(ByteData.sublistView),
              );
            await icons.load();
          });
        }
        tester.platformDispatcher.platformBrightnessTestValue = scene.$5;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final h = Harness(tester);
        await h.pump(size: scene.$3, lang: scene.$2, scale: scene.$4);
        await h.manage();
        final prefix = '${scene.$1.name}-${scene.$2}-${scene.$3.width.toInt()}';
        await h.screenshot('$prefix-list');
        await tester.ensureVisible(h.row(1));
        await tester.pump();
        final gate = Completer<Result<LoadResult<ChapterContent>>>();
        h.repo.pending = gate;
        await tester.tap(h.row(1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await h.screenshot('$prefix-checking');
        gate.complete(
          Failure(
            AppFailure(
              kind: FailureKind.cache,
              operation: Operation.chapter,
              context: FailureContext.cacheMiss,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(h.l.cacheMissMessage), findsOneWidget);
        await h.screenshot('$prefix-failed');
        ScaffoldMessenger.of(
          tester.element(find.byType(CacheScreen)),
        ).removeCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.tap(h.row(1));
        await tester.pumpAndSettle();
        await h.screenshot('$prefix-offline-reader');
        await h.back();
        await h.screenshot('$prefix-returned-list');
        await h.close();
      },
      variant: TargetPlatformVariant.only(scene.$1),
    );
  }
}
