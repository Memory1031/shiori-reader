import 'package:drift/native.dart';
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
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ShioriApp(
          locale: const Locale('en'),
          homeBuilder: (context, _) => BookReaderScreen(
            chapter: fixtureChapterKey(FixtureScenario.multiVolume),
            repository: env.novels,
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

  Future<void> menu(WidgetTester t, String label) async {
    view(t).chrome!.value = true;
    await t.pumpAndSettle();
    await t.tap(find.byType(PopupMenuButton<ReaderCommand>));
    await t.pumpAndSettle();
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
