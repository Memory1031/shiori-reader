import 'package:drift/native.dart';
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/data/repositories/novel_repository.dart';
import 'package:shiori/data/sources/source_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/user_bookmark_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/bookmark_position.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_commands.dart';
import 'package:shiori/features/reader/reader_bookmarks.dart';
import 'package:shiori/features/reader/reader_contents.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'local_search_test.dart' show fonts;
import '../shiori_feedback_test.dart' show feedbackScreenshot;

class Harness {
  final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
  final db = UserDatabase(NativeDatabase.memory());
  late final bookmarks = LocalUserBookmarkRepository(db);
  final boundary = GlobalKey();
  ReaderContentView view(WidgetTester t) => t
      .widgetList<ReaderContentView>(find.byType(ReaderContentView))
      .firstWhere((v) => v.active);
  Future<void> pump(
    WidgetTester t, {
    int depth = 0,
    Size size = const Size(390, 844),
    NovelRepository? repository,
  }) async {
    t.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await env.close();
      await db.close();
      await t.pump();
    });
    await fonts(t);
    await env.settings.save(
      ReaderSettings(controlsHintSeen: true, paper: ReaderPaper.warm),
      cancellation: CancellationSource().token,
    );
    if (repository != null) {
      await t.runAsync(
        () => Future.wait([
          repository.loadChapter(
            fixtureChapterKey(FixtureScenario.multiVolume),
            mode: ReadMode.cacheFirst,
            cancellation: CancellationSource().token,
          ),
          repository.loadDetail(
            fixtureNovelKey(FixtureScenario.multiVolume),
            mode: ReadMode.cacheFirst,
            cancellation: CancellationSource().token,
          ),
          repository.loadCatalog(
            fixtureNovelKey(FixtureScenario.multiVolume),
            mode: ReadMode.cacheFirst,
            cancellation: CancellationSource().token,
          ),
        ]),
      );
    }
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ShioriApp(
          locale: const Locale('en'),
          homeBuilder: (context, _) => BookReaderScreen(
            chapter: fixtureChapterKey(FixtureScenario.multiVolume),
            repository: repository ?? env.novels,
            library: env.library,
            bookmarks: bookmarks,
            linkDepth: depth,
            settings: env.settings,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> settleRepository(WidgetTester t) async {
    // Native SQLite completes on the real loop; wait for an active confirmed surface.
    for (var i = 0; i < 100; i++) {
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pumpAndSettle();
      if (t
          .widgetList<ReaderContentView>(find.byType(ReaderContentView))
          .any((v) => v.active)) {
        return;
      }
    }
    fail('The repository navigation did not settle');
  }

  Future<void> openMenu(WidgetTester t) async {
    view(t).chrome!.value = true;
    await t.pumpAndSettle();
    await t.tap(find.byType(PopupMenuButton<ReaderCommand>));
    await t.pumpAndSettle();
  }

  Future<void> menu(WidgetTester t, String label) async {
    await openMenu(t);
    await t.tap(find.text(label));
    await t.pumpAndSettle();
  }

  Future<BookmarkSnapshot> snapshot(WidgetTester t) async =>
      (await t.runAsync(
                () => bookmarks.readBookmarks(
                  fixtureNovelKey(FixtureScenario.multiVolume),
                  cancellation: CancellationSource().token,
                ),
              )
              as Success<BookmarkSnapshot>)
          .value;
  Future<void> seed(
    WidgetTester t,
    ChapterContent c,
    String id, {
    BookmarkLocation state = BookmarkLocation.exact,
  }) async {
    final p = ReaderPosition(
      contentRevision: c.contentRevision,
      blockKey: c.blocks.first.blockKey,
      blockIndex: 0,
      blockFraction: 0,
      chapterFraction: 0,
    );
    final before = await snapshot(t);
    await t.runAsync(
      () => bookmarks.saveBookmark(
        UserBookmark(
          id: id,
          chapter: c.key,
          anchor: BookmarkPositionIndex([c]).capture(c.key, p)!,
          chapterTitle: c.title,
          createdAt: DateTime.utc(2026, 10, 16),
          location: state,
        ),
        revision: before.revision,
        cancellation: CancellationSource().token,
      ),
    );
    await t.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'online bookmark return survives cache eviction and a transient network failure',
    (t) async {
      final h = Harness(), cache = CacheDatabase(NativeDatabase.memory());
      final novels = createNovelRepository(
        sources: SourceRegistry([h.env.source]),
        cache: cache,
      );
      addTearDown(() async {
        await novels.close();
        await cache.close();
      });
      await h.pump(t, repository: novels);
      final a = h.view(t).viewportController!.capture()!,
          first = h.view(t).content.key;
      final loaded = await t.runAsync(
        () => novels.loadChapter(
          fixtureChapterKey(FixtureScenario.multiVolume, 1),
          mode: ReadMode.cacheFirst,
          cancellation: CancellationSource().token,
        ),
      );
      await h.seed(
        t,
        (loaded as Success<LoadResult<ChapterContent>>).value.value,
        'b',
      );
      await h.menu(t, 'My bookmarks');
      await t.tap(find.byKey(const ValueKey('bookmark-b')));
      await h.settleRepository(t);
      final b = h.view(t).content.key;
      expect(b, isNot(first));
      expect(
        find.byKey(const ValueKey('reader-location-return')).hitTestable(),
        findsOneWidget,
      );
      expect(
        h.view(t).actions.previousLocationLabel,
        'Back to before bookmark navigation',
      );
      await t.runAsync(
        () => cache.customStatement('DELETE FROM chapter_cache'),
      );
      h.env.source.controls.failNext(
        AppFailure(
          kind: FailureKind.network,
          operation: Operation.chapter,
          retryPolicy: RetryPolicy.manual,
        ),
      );
      h.view(t).actions.previousLocation!();
      await h.settleRepository(t);
      expect(h.view(t).content.key, b);
      expect(h.view(t).actions.previousLocation, isNotNull);
      h.view(t).actions.previousLocation!();
      await h.settleRepository(t);
      expect(h.view(t).content.key, first);
      expect(h.view(t).viewportController!.capture(), a);
      expect(h.view(t).actions.previousLocation, isNull);
      await h.view(t).session!.flushProgress();
      final saved = await h.env.library.getProgress(
        first.novelKey,
        cancellation: CancellationSource().token,
      );
      expect((saved as Success<ReadingProgress?>).value!.chapterKey, first);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  for (final invalid in ['revision', 'chapter']) {
    testWidgets(
      'online return rejects confirmed $invalid identity loss without guessing',
      (t) async {
        final h = Harness(), cache = CacheDatabase(NativeDatabase.memory());
        final novels = createNovelRepository(
          sources: SourceRegistry([h.env.source]),
          cache: cache,
        );
        addTearDown(() async {
          await novels.close();
          await cache.close();
        });
        await h.pump(t, repository: novels);
        final loaded = await t.runAsync(
          () => novels.loadChapter(
            fixtureChapterKey(FixtureScenario.multiVolume, 1),
            mode: ReadMode.cacheFirst,
            cancellation: CancellationSource().token,
          ),
        );
        await h.seed(
          t,
          (loaded as Success<LoadResult<ChapterContent>>).value.value,
          'b',
        );
        await h.menu(t, 'My bookmarks');
        await t.tap(find.byKey(const ValueKey('bookmark-b')));
        await h.settleRepository(t);
        final b = h.view(t).content.key;
        await t.runAsync(
          () => cache.customStatement('DELETE FROM chapter_cache'),
        );
        if (invalid == 'revision') {
          h.env.source.controls.revision = 1;
        } else {
          h.env.source.controls.chapterDeleted = true;
        }
        h.view(t).actions.previousLocation!();
        await h.settleRepository(t);
        expect(h.view(t).content.key, b);
        expect(h.view(t).actions.previousLocation, isNull);
        expect((await h.snapshot(t)).bookmarks.single.id, 'b');
        expect(
          find.text(
            'Link unavailable. Only valid documents and anchors within this book can be opened.',
          ),
          findsOneWidget,
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'page turns refresh bookmark labels and toggle the displayed anchor',
    (t) async {
      final h = Harness();
      await h.pump(t);
      await h.menu(t, 'Add bookmark');
      final first = (await h.snapshot(t)).bookmarks.single;
      await h.openMenu(t);
      expect(find.text('Remove bookmark'), findsOneWidget);
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      final viewport = h.view(t).viewportController!;
      final layout = viewport.layoutGeneration;
      viewport.next();
      await t.pumpAndSettle();
      expect(viewport.layoutGeneration, layout);
      expect(
        viewport.capture()!.blockKey,
        isNot(first.anchor.position.blockKey),
      );
      await h.openMenu(t);
      expect(find.text('Add bookmark'), findsOneWidget);
      expect(find.text('Remove bookmark'), findsNothing);
      await feedbackScreenshot(t, h.boundary, 'bookmark-unmarked-page');
      await t.tap(find.text('Add bookmark'));
      await t.pumpAndSettle();
      expect((await h.snapshot(t)).bookmarks, hasLength(2));
      await h.menu(t, 'Remove bookmark');
      expect((await h.snapshot(t)).bookmarks.single.id, first.id);
      viewport.previous();
      await t.pumpAndSettle();
      await h.menu(t, 'Remove bookmark');
      expect((await h.snapshot(t)).bookmarks, isEmpty);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'progress scrubber noncanonical fractions can be added and cancelled',
    (t) async {
      final h = Harness();
      await h.pump(t);
      h.view(t).chrome!.value = true;
      await t.pumpAndSettle();
      t.widget<ReaderBottomBar>(find.byType(ReaderBottomBar)).onProgress!();
      await t.pumpAndSettle();
      // The scrubber can select between code points, unlike normal page starts.
      t.widget<Slider>(find.byType(Slider)).onChangeEnd!(
        (1 + .51) / h.view(t).content.blocks.length,
      );
      await t.pumpAndSettle();
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      final raw = h.view(t).viewportController!.capture()!;
      expect(raw.blockFraction, closeTo(.51, 1e-7));
      await h.menu(t, 'Add bookmark');
      final saved = (await h.snapshot(t)).bookmarks.single.anchor.position;
      expect(saved.blockFraction, isNot(raw.blockFraction));
      await h.openMenu(t);
      expect(find.text('Remove bookmark'), findsOneWidget);
      expect(find.text('Add bookmark'), findsNothing);
      await feedbackScreenshot(t, h.boundary, 'bookmark-scrubber-saved');
      await t.tap(find.text('Remove bookmark'));
      await t.pumpAndSettle();
      expect((await h.snapshot(t)).bookmarks, isEmpty);
      await h.menu(t, 'Add bookmark');
      expect((await h.snapshot(t)).bookmarks, hasLength(1));
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'auxiliary reader disables capture and leaves bookmark navigation to its owner',
    (t) async {
      final h = Harness();
      await h.pump(t, depth: 1);
      h.view(t).chrome!.value = true;
      await t.pumpAndSettle();
      await t.tap(find.byType(PopupMenuButton<ReaderCommand>));
      await t.pumpAndSettle();
      final add = find.byWidgetPredicate(
        (w) =>
            w is PopupMenuItem<ReaderCommand> &&
            w.value == ReaderCommand.toggleBookmark,
      );
      expect(t.widget<PopupMenuItem<ReaderCommand>>(add).enabled, isFalse);
      expect(find.text('My bookmarks'), findsNothing);
      expect(
        find.byTooltip(
          'A reliable position bookmark is unavailable on this page.',
        ),
        findsOneWidget,
      );
      expect((await h.snapshot(t)).bookmarks, isEmpty);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'menu add/cancel survives reflow; independent sheet has empty state and deletes',
    (t) async {
      final h = Harness();
      await h.pump(t);
      await h.menu(t, 'My bookmarks');
      expect(find.byType(ReaderBookmarksPanel), findsOneWidget);
      expect(
        find.text('No bookmarks yet. Add one from the reader menu.'),
        findsOneWidget,
      );
      expect(find.byType(ReaderContentsPanel), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      if (find.byType(ReaderBookmarksPanel).evaluate().isNotEmpty) {
        await t.tapAt(const Offset(10, 10));
        await t.pumpAndSettle();
      }
      await h.menu(t, 'Add bookmark');
      expect((await h.snapshot(t)).bookmarks.length, 1);
      final anchor = (await h.snapshot(t)).bookmarks.single.anchor.position;
      h
          .view(t)
          .preferences!
          .update(h.view(t).preferences!.value.copyWith(fontSize: 26));
      t.view.physicalSize = const Size(430, 880);
      await t.pumpAndSettle();
      expect(h.view(t).viewportController!.capture(), anchor);
      await h.menu(t, 'Remove bookmark');
      expect((await h.snapshot(t)).bookmarks, isEmpty);
      await h.menu(t, 'Add bookmark');
      await h.menu(t, 'My bookmarks');
      await feedbackScreenshot(t, h.boundary, 'bookmarks-warm');
      await t.tap(find.byTooltip('Delete bookmark'));
      await t.pumpAndSettle();
      expect((await h.snapshot(t)).bookmarks, isEmpty);
      expect(find.byType(ReaderBookmarksPanel), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'same and cross chapter jumps commit before sheet closes, list does not fetch',
    (t) async {
      final h = Harness();
      await h.pump(t, size: const Size(1040, 780));
      final first = h.view(t).content;
      await h.seed(t, first, 'first');
      final next = h.env.source.data.content(
        FixtureScenario.multiVolume,
        index: 1,
      );
      await h.seed(t, next, 'second');
      final calls = h.env.source.controls.calls[Operation.chapter];
      await h.menu(t, 'My bookmarks');
      expect(h.env.source.controls.calls[Operation.chapter], calls);
      await feedbackScreenshot(t, h.boundary, 'bookmarks-desktop');
      await t.tap(find.byKey(const ValueKey('bookmark-second')));
      await t.pumpAndSettle();
      expect(find.byType(ReaderBookmarksPanel), findsNothing);
      expect(h.view(t).content.key, next.key);
      await h.menu(t, 'My bookmarks');
      await t.tap(find.byKey(const ValueKey('bookmark-first')));
      await t.pumpAndSettle();
      expect(h.view(t).content.key, first.key);
      expect(find.byType(ReaderBookmarksPanel), findsNothing);
      await h.menu(t, 'My bookmarks');
      await t.tap(find.byKey(const ValueKey('bookmark-first')));
      await t.pumpAndSettle();
      expect(find.byType(ReaderBookmarksPanel), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets(
    'changed online content remains marked and never replaces the current page',
    (t) async {
      final h = Harness();
      await h.pump(t);
      final source = h.view(t).content.key;
      final target = h.env.source.data.content(
        FixtureScenario.multiVolume,
        index: 2,
      );
      final legacy = ChapterContent(
        key: target.key,
        title: target.title,
        blocks: [
          ParagraphBlock(
            text:
                'This unique original paragraph was completely removed from the chapter.',
          ),
        ],
      );
      await h.seed(t, legacy, 'invalid', state: BookmarkLocation.unavailable);
      h
          .view(t)
          .preferences!
          .update(
            h
                .view(t)
                .preferences!
                .value
                .copyWith(themeMode: ReaderThemeMode.dark),
          );
      await t.pumpAndSettle();
      await h.menu(t, 'My bookmarks');
      expect(find.textContaining('cannot be located reliably'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('bookmark-invalid')));
      await t.pumpAndSettle();
      expect(find.byType(ReaderBookmarksPanel), findsOneWidget);
      expect(find.textContaining('cannot be located reliably'), findsWidgets);
      expect(h.view(t).content.key, source);
      final b = (await h.snapshot(t)).bookmarks.single;
      expect(b.located, isFalse);
      expect(b.anchor.position.contentRevision, legacy.contentRevision);
      await feedbackScreenshot(t, h.boundary, 'bookmarks-unavailable');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'book removal closes its bookmark sheet and retires an in-flight jump',
    (t) async {
      final h = Harness();
      await h.pump(t);
      final next = h.env.source.data.content(
        FixtureScenario.multiVolume,
        index: 2,
      );
      await h.seed(t, next, 'second');
      h.env.source.controls.delays[Operation.chapter] = const Duration(
        seconds: 1,
      );
      await h.menu(t, 'My bookmarks');
      await t.tap(find.byKey(const ValueKey('bookmark-second')));
      await t.pump();
      await h.env.library.removeOnlineBook(
        fixtureNovelKey(FixtureScenario.multiVolume),
        cancellation: CancellationSource().token,
      );
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 2));
      expect(find.byType(ReaderBookmarksPanel), findsNothing);
      expect(find.byType(ReaderContentView), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'network failure keeps current page and bookmarks, cancellation cannot commit late',
    (t) async {
      final h = Harness();
      await h.pump(t);
      final source = h.view(t).content.key;
      final next = h.env.source.data.content(
        FixtureScenario.multiVolume,
        index: 2,
      );
      await h.seed(t, next, 'second');
      h.env.source.controls.failNext(
        AppFailure(
          kind: FailureKind.network,
          operation: Operation.chapter,
          retryPolicy: RetryPolicy.manual,
        ),
      );
      await h.menu(t, 'My bookmarks');
      await t.tap(find.byKey(const ValueKey('bookmark-second')));
      await t.pumpAndSettle();
      expect(find.byType(ReaderBookmarksPanel), findsOneWidget);
      expect(
        find.text('Could not open this bookmark. Please try again later.'),
        findsOneWidget,
      );
      expect(h.view(t).content.key, source);
      expect((await h.snapshot(t)).bookmarks.length, 1);
      h.env.source.controls.delays[Operation.chapter] = const Duration(
        seconds: 1,
      );
      await t.tap(find.byKey(const ValueKey('bookmark-second')));
      await t.tap(find.byKey(const ValueKey('bookmark-second')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 2));
      expect(find.byType(ReaderBookmarksPanel), findsNothing);
      expect(h.view(t).content.key, source);
      expect((await h.snapshot(t)).bookmarks.length, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
