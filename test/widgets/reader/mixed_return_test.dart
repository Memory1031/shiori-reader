import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/user_bookmark_repository.dart';
import 'package:shiori/domain/bookmark_position.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_bookmarks.dart';
import 'package:shiori/features/reader/reader_commands.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'local_search_test.dart' as s;
import 'link_return_test.dart' as f;

class MixedReader {
  MixedReader(this.reader, this.bookmarks);
  final f.ReturnReader reader;
  final LocalUserBookmarkRepository bookmarks;
  Future<void> lookup(WidgetTester t, String chapter, {int block = 0}) async {
    final id = block == 0 ? chapter : "$chapter-$block";
    final c = reader.book.chapters.firstWhere(
      (c) => c.key == reader.key(chapter),
    );
    final p = ReaderPosition(
      contentRevision: c.contentRevision,
      blockKey: c.blocks[block].blockKey,
      blockIndex: block,
      blockFraction: 0,
      chapterFraction: ReaderPosition.fractionFor(
        blockIndex: block,
        blockFraction: 0,
        blockCount: c.blocks.length,
      ),
    );
    await t.runAsync(() async {
      final before = await bookmarks.snapshot(c.key.novelKey);
      if (!before.bookmarks.any((b) => b.id == id)) {
        final result = await bookmarks.saveBookmark(
          UserBookmark(
            id: id,
            chapter: c.key,
            anchor: BookmarkPositionIndex([c]).capture(c.key, p)!,
            chapterTitle: c.title,
            createdAt: DateTime.utc(2026),
          ),
          revision: before.revision,
          cancellation: CancellationSource().token,
        );
        expect((result as Success<bool>).value, isTrue);
      }
    });
    await t.pumpAndSettle();
    reader.view(t).actions.showBookmarks!(
      t.element(find.byWidget(reader.view(t))),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('bookmark-$id')));
    await t.pumpAndSettle();
    expect(find.byType(ReaderBookmarksPanel), findsNothing);
    expect(reader.view(t).content.key, c.key);
  }

  Future<void> search(WidgetTester t, String chapter) async {
    final state = s.search(reader, t);
    reader.view(t).chrome!.value = true;
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('reader-search-open')));
    await t.pumpAndSettle();
    if (state.submitted != 'later') await s.submit(t, state, 'later');
    final index = List.generate(
      state.loadedCount,
      (i) => i,
    ).firstWhere((i) => state.hitAt(i)!.chapter == reader.key(chapter));
    await s.select(t, state, index);
  }
}

Future<MixedReader> mount(WidgetTester t, {double scale = 1}) async {
  await s.fonts(t);
  final db = UserDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = LocalUserBookmarkRepository(db);
  final reader = await f.mount(
    t,
    repositoryFactory: s.ReaderSearchRepository.new,
    bookmarks: repo,
    scale: scale,
  );
  await t.runAsync(
    () => db.customStatement(
      'INSERT INTO local_books(digest,format,title,imported_at,manifest_hash) VALUES(?,?,?,?,?)',
      [reader.book.detail.summary.key.novelId, 'epub', 'Book', 0, 'a' * 64],
    ),
  );
  return MixedReader(reader, repo);
}

Future<void> drive(WidgetTester tester, Future<void> navigation) async {
  await tester.pumpAndSettle();
  await navigation;
}

void main() {
  testWidgets(
    'bookmark data refresh failure does not undo confirmed navigation or its origin',
    (t) async {
      final m = await mount(t), r = m.reader;
      final a = r.position(t);
      await m.lookup(t, 'b');
      await r.back(t);
      final stored = await t.runAsync(
        () => m.bookmarks.snapshot(r.book.detail.summary.key),
      );
      final b = stored!.bookmarks.single;
      await t.runAsync(
        () => m.bookmarks.saveBookmark(
          b.resolved(b.chapter, b.anchor, BookmarkLocation.unavailable),
          revision: stored.revision,
          cancellation: CancellationSource().token,
        ),
      );
      await t.pumpAndSettle();
      await t.runAsync(
        () => m.bookmarks.db.customStatement(
          "CREATE TRIGGER fail_refresh BEFORE UPDATE ON user_bookmarks BEGIN SELECT RAISE(ABORT,'test refresh failure'); END",
        ),
      );
      await m.lookup(t, 'b');
      expect(r.view(t).content.key, r.key('b'));
      expect(r.view(t).actions.previousLocation, isNotNull);
      final after = await t.runAsync(
        () => m.bookmarks.snapshot(r.book.detail.summary.key),
      );
      expect(after!.bookmarks.single.location, BookmarkLocation.unavailable);
      await r.back(t);
      expect(r.position(t), a);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'return consumes the layer after ordinary reading reaches its origin',
    (t) async {
      final m = await mount(t), r = m.reader;
      final a = r.position(t);
      await m.lookup(t, 'a', block: 10);
      for (var i = 0; i < 30 && r.position(t) != a; i++) {
        unawaited(r.view(t).viewportController!.previous());
        await t.pumpAndSettle();
      }
      expect(r.position(t), a);
      expect(r.view(t).actions.previousLocation, isNotNull);
      await r.back(t);
      expect(r.position(t), a);
      expect(r.view(t).actions.previousLocation, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'bookmark return label stays available after the quick hint expires',
    (t) async {
      final m = await mount(t, scale: 1.4), r = m.reader;
      await m.lookup(t, 'b');
      await t.pump(const Duration(seconds: 9));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reader-location-return')).hitTestable(),
        findsNothing,
      );
      r.view(t).chrome!.value = true;
      await t.pumpAndSettle();
      await t.tap(find.byType(PopupMenuButton<ReaderCommand>));
      await t.pumpAndSettle();
      expect(find.text('Back to before bookmark navigation'), findsOneWidget);
      await f.snapshot(t, r, 'bookmark-return-menu-phone-en-large');
      await t.tap(find.text('Back to before bookmark navigation'));
      await t.pumpAndSettle();
      expect(r.view(t).content.key, r.key('a'));
      expect(r.view(t).actions.previousLocation, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  for (final race in ['delete', 'background', 'close']) {
    testWidgets(
      'uncommitted bookmark $race cancels a controlled candidate without a return layer',
      (t) async {
        final m = await mount(t), r = m.reader;
        await m.lookup(t, 'b');
        await r.back(t);
        final a = r.position(t);
        final gate = Completer<void>(), entered = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        r.repository
          ..blocked = r.key('b')
          ..wait = gate
          ..entered = entered;
        r.view(t).actions.showBookmarks!(t.element(find.byWidget(r.view(t))));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('bookmark-b')));
        for (var i = 0; i < 20 && !entered.isCompleted; i++) {
          await t.pump();
          await t.runAsync(() => Future<void>.delayed(Duration.zero));
        }
        expect(entered.isCompleted, isTrue);
        // A second tap remains disabled while the first candidate owns the panel.
        await t.tap(
          find.byKey(const ValueKey('bookmark-b')),
          warnIfMissed: false,
        );
        if (race == 'delete') {
          final before = await t.runAsync(
            () => m.bookmarks.snapshot(r.book.detail.summary.key),
          );
          await t.runAsync(
            () => m.bookmarks.deleteBookmark(
              before!.bookmarks.single,
              cancellation: CancellationSource().token,
            ),
          );
          await t.pump();
        } else if (race == 'background') {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await t.pump();
        } else {
          await t.tapAt(const Offset(5, 5));
          await t.pump();
        }
        gate.complete();
        await t.pumpAndSettle();
        if (race == 'background') {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await t.pumpAndSettle();
        }
        expect(r.position(t), a);
        expect(r.view(t).actions.previousLocation, isNull);
        expect(find.byType(PagedReaderViewport), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'rapid return consumes once only after the controlled target confirms',
    (t) async {
      final m = await mount(t), r = m.reader;
      final a = r.position(t);
      await m.lookup(t, 'b');
      final gate = Completer<void>(), entered = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      r.repository
        ..blocked = r.key('a')
        ..wait = gate
        ..entered = entered;
      final back = r.view(t).actions.previousLocation!;
      back();
      back();
      for (var i = 0; i < 20 && !entered.isCompleted; i++) {
        await t.pump();
        await t.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(entered.isCompleted, isTrue);
      expect(r.view(t).content.key, r.key('b'));
      expect(r.view(t).actions.previousLocation, isNotNull);
      back();
      gate.complete();
      await t.pumpAndSettle();
      expect(r.position(t), a);
      expect(r.view(t).actions.previousLocation, isNull);
      expect(find.byType(PagedReaderViewport), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'same chapter bookmark restores its semantic origin in the existing viewport',
    (t) async {
      final m = await mount(t), r = m.reader;
      final a = r.position(t),
          viewport = t.state(find.byType(PagedReaderViewport));
      await m.lookup(t, 'a', block: 1);
      expect(r.position(t), isNot(a));
      expect(r.view(t).content.key, r.key('a'));
      await r.back(t);
      expect(r.position(t), a);
      expect(t.state(find.byType(PagedReaderViewport)), same(viewport));
      expect(r.view(t).actions.previousLocation, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  for (final type in ['search', 'bookmark']) {
    testWidgets('$type separated by a link starts a new lookup layer', (
      t,
    ) async {
      final m = await mount(t), r = m.reader;
      final a = r.position(t);
      if (type == 'search') {
        await m.search(t, 'b');
      } else {
        await m.lookup(t, 'b');
      }
      final b = r.position(t);
      await r.link(t, 'C');
      final c = r.position(t);
      if (type == 'search') {
        await m.search(t, 'd');
      } else {
        await m.lookup(t, 'd');
      }
      await r.back(t);
      expect(r.position(t), c);
      await r.back(t);
      expect(r.position(t), b);
      await r.back(t);
      expect(r.position(t), a);
      expect(r.view(t).actions.previousLocation, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    });
  }

  testWidgets('search then link returns to link origin then search origin', (
    t,
  ) async {
    final m = await mount(t), r = m.reader;
    final a = r.position(t);
    await m.search(t, 'b');
    final b = r.position(t);
    await r.link(t, 'C');
    expect(r.view(t).actions.previousLocationLabel, isNull);
    expect(s.search(r, t).highlight.value, isNull);
    await r.back(t);
    expect(r.position(t), b);
    expect(r.view(t).actions.previousLocationLabel, 'Back to search start');
    await r.back(t);
    expect(r.position(t), a);
    expect(r.view(t).actions.previousLocation, isNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets('link then consecutive search hits preserve both outer origins', (
    t,
  ) async {
    final m = await mount(t), r = m.reader;
    final a = r.position(t);
    await r.link(t, 'B');
    final b = r.position(t);
    await m.search(t, 'c');
    await m.search(t, 'd');
    await r.back(t);
    expect(r.position(t), b);
    await r.back(t);
    expect(r.position(t), a);
    expect(r.view(t).actions.previousLocation, isNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets(
    'bookmark search bookmark only merges the current top and deletes no origins',
    (t) async {
      final m = await mount(t), r = m.reader;
      final a = r.position(t);
      await m.lookup(t, 'b');
      final b = r.position(t);
      await m.search(t, 'c');
      final c = r.position(t);
      await m.lookup(t, 'd');
      expect(
        r.view(t).actions.previousLocationLabel,
        'Back to before bookmark navigation',
      );
      final stored = await t.runAsync(
        () => m.bookmarks.snapshot(r.book.detail.summary.key),
      );
      for (final mark in stored!.bookmarks) {
        await t.runAsync(
          () => m.bookmarks.deleteBookmark(
            mark,
            cancellation: CancellationSource().token,
          ),
        );
        await t.pumpAndSettle();
      }
      await t.pumpAndSettle();
      await r.back(t);
      expect(r.position(t), c);
      await r.back(t);
      expect(r.position(t), b);
      await r.back(t);
      expect(r.position(t), a);
      expect(r.view(t).actions.previousLocation, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'continuous bookmarks keep A; ordinary reading is the next link origin',
    (t) async {
      final m = await mount(t), r = m.reader;
      final a = r.position(t);
      await m.lookup(t, 'b');
      await m.lookup(t, 'c');
      unawaited(r.view(t).viewportController!.next());
      await t.pumpAndSettle();
      final prime = r.position(t);
      await r.link(t, 'D');
      await r.back(t);
      expect(r.position(t), prime);
      await r.back(t);
      expect(r.position(t), a);
      expect(r.view(t).actions.previousLocation, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'no-op explicit selection preserves a lookup but a real seek ends it',
    (t) async {
      final m = await mount(t), r = m.reader;
      await m.lookup(t, 'b');
      await drive(
        t,
        r.view(t).actions.navigatePosition!(r.position(t), () => true),
      );
      await t.pumpAndSettle();
      expect(r.view(t).actions.previousLocation, isNotNull);
      final c = r.view(t).content;
      final next = ReaderPosition(
        contentRevision: c.contentRevision,
        blockKey: c.blocks[3].blockKey,
        blockIndex: 3,
        blockFraction: 0,
        chapterFraction: ReaderPosition.fractionFor(
          blockIndex: 3,
          blockFraction: 0,
          blockCount: c.blocks.length,
        ),
      );
      await drive(t, r.view(t).actions.navigatePosition!(next, () => true));
      await t.pumpAndSettle();
      expect(r.view(t).actions.previousLocation, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
