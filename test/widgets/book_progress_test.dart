import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/bookshelf/library_controller.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/history/history_screen.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/widgets/book_cover.dart';

Future<void> seed(
  FixtureLibraryRepository repo,
  NovelSummary summary,
  BookProgressSnapshot? snapshot,
) async {
  final token = CancellationSource().token;
  await repo.putBookshelf(
    BookshelfEntry(snapshot: summary, addedAt: DateTime.utc(2026)),
    cancellation: token,
  );
  final gen =
      (await repo.beginProgressSession(summary.key, cancellation: token)
              as Success<int>)
          .value;
  await repo.saveProgress(
    ReadingProgress(
      snapshot: summary,
      chapterKey: ChapterKey(novelKey: summary.key, chapterId: 'chapter'),
      chapterOrdinalSnapshot: 75,
      catalogRevision: 'catalog',
      position: ReaderPosition(
        contentRevision: 'content',
        blockKey: 'block',
        blockIndex: 0,
        blockFraction: .42,
        chapterFraction: .42,
      ),
      completed: false,
      lastReadAt: DateTime.utc(2026),
      bookProgress: snapshot,
    ),
    stamp: ProgressWriteStamp(generation: gen, sequence: 0),
    cancellation: token,
  );
}

void main() {
  ReadingProgress progress(
    String id,
    int day,
    BookTerminalState? terminal, {
    bool completed = false,
    double fraction = .45,
  }) {
    final key = NovelKey(sourceId: SourceId('fixture'), novelId: id);
    return ReadingProgress(
      snapshot: NovelSummary(key: key, title: id),
      chapterKey: ChapterKey(novelKey: key, chapterId: 'chapter'),
      chapterOrdinalSnapshot: 0,
      catalogRevision: 'catalog',
      position: ReaderPosition(
        contentRevision: 'content',
        blockKey: 'block',
        blockIndex: 0,
        blockFraction: 0,
        chapterFraction: completed ? 1 : .45,
      ),
      completed: completed,
      lastReadAt: DateTime.utc(2026, 1, day),
      bookProgress: terminal == null
          ? null
          : BookProgressSnapshot(
              fraction: terminal == BookTerminalState.reading ? fraction : 1,
              chapterCount: 10,
              terminal: terminal,
            ),
    );
  }

  LibraryController controller(
    List<ReadingProgress> history,
    List<ReadingProgress> shelf,
  ) {
    final repo = FixtureLibraryRepository();
    final value = LibraryController(repo)
      ..recent = List.unmodifiable(history)
      ..books = List.unmodifiable(
        shelf.map(
          (p) =>
              BookshelfEntry(snapshot: p.snapshot, addedAt: DateTime.utc(2026)),
        ),
      );
    addTearDown(() async {
      value.onDelete();
      value.dispose();
      await repo.close();
    });
    return value;
  }

  for (final terminal in [
    BookTerminalState.finished,
    BookTerminalState.caughtUp,
    BookTerminalState.currentEnd,
  ]) {
    test(
      'continue prefers an older reading book over $terminal without reordering',
      () {
        final older = progress('older', 1, BookTerminalState.reading),
            latest = progress('latest', 2, terminal);
        final value = controller([latest, older], [older, latest]);
        expect(value.continueReadingProgress, same(older));
        expect(value.recent, [latest, older]);
        expect(value.books.map((b) => b.snapshot.key), [
          older.novelKey,
          latest.novelKey,
        ]);
        expect(value.sorted.map((b) => b.snapshot.key), [
          latest.novelKey,
          older.novelKey,
        ]);
      },
    );
  }
  for (final states in [
    (BookTerminalState.reading, BookTerminalState.reading),
    (BookTerminalState.finished, BookTerminalState.caughtUp),
    (BookTerminalState.currentEnd, BookTerminalState.finished),
    (BookTerminalState.reading, null),
  ]) {
    test(
      'continue keeps recent order within priority ${states.$1}/${states.$2}',
      () {
        final older = progress('older', 1, states.$1),
            latest = progress('latest', 2, states.$2);
        expect(
          controller([latest, older], [older, latest]).continueReadingProgress,
          same(latest),
        );
      },
    );
  }
  test(
    'legacy progress remains preferred even when its chapter is completed',
    () {
      final legacy = progress('legacy', 1, null, completed: true),
          latest = progress('latest', 2, BookTerminalState.finished);
      expect(
        controller([latest, legacy], [legacy, latest]).continueReadingProgress,
        same(legacy),
      );
    },
  );
  for (final sample in [(true, .45), (false, 1.0)]) {
    test(
      'continue uses terminal rather than completed=${sample.$1} or fraction=${sample.$2}',
      () {
        final older = progress(
              'reading',
              1,
              BookTerminalState.reading,
              completed: sample.$1,
              fraction: sample.$2,
            ),
            latest = progress('latest', 2, BookTerminalState.finished);
        expect(
          controller([latest, older], [older, latest]).continueReadingProgress,
          same(older),
        );
      },
    );
  }
  test('a lone finished book remains a valid fallback', () {
    final finished = progress('finished', 1, BookTerminalState.finished);
    expect(
      controller([finished], [finished]).continueReadingProgress,
      same(finished),
    );
  });
  test(
    'continue skips history outside the shelf for both priority and fallback',
    () {
      final removed = progress('removed', 3, null),
          finished = progress('finished', 2, BookTerminalState.finished),
          reading = progress('reading', 1, BookTerminalState.reading);
      expect(
        controller(
          [removed, finished, reading],
          [finished, reading],
        ).continueReadingProgress,
        same(reading),
      );
      expect(
        controller([removed, finished], [finished]).continueReadingProgress,
        same(finished),
      );
    },
  );
  for (final empty in ['shelf', 'history', 'matching history']) {
    test('continue returns null without $empty', () {
      final saved = progress('saved', 1, BookTerminalState.reading),
          other = progress('other', 2, BookTerminalState.reading);
      expect(
        controller(
          empty == 'history' ? [] : [saved],
          empty == 'shelf' ? [] : [other],
        ).continueReadingProgress,
        isNull,
      );
    });
  }
  testWidgets(
    'grid has only cover source and title; list retains progress text',
    (tester) async {
      final repo = FixtureLibraryRepository();
      final controller = LibraryController(repo)..onStart();
      final books = [
        NovelSummary(key: LocalBookIdentity.book('a' * 64), title: 'EPUB book'),
        NovelSummary(key: LocalBookIdentity.book('b' * 64), title: 'TXT book'),
        NovelSummary(
          key: NovelKey(sourceId: SourceId('online'), novelId: 'book'),
          title: 'Online book',
        ),
      ];
      await seed(
        repo,
        books[0],
        BookProgressSnapshot(fraction: .6399, chapterCount: 120),
      );
      await seed(
        repo,
        books[1],
        BookProgressSnapshot(
          fraction: 1,
          chapterCount: 1,
          terminal: BookTerminalState.finished,
        ),
      );
      await seed(
        repo,
        books[2],
        BookProgressSnapshot(
          fraction: 1,
          chapterCount: 120,
          terminal: BookTerminalState.caughtUp,
        ),
      );
      controller.localFormats = {
        books[0].key: LocalBookFormat.epub,
        books[1].key: LocalBookFormat.txt,
      };
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BookshelfView(
              controller: controller,
              onOpen: (_) {},
              onSearch: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final labels = ['epub', 'txt', null];
      for (var i = 0; i < books.length; i++) {
        final card = find.byKey(ValueKey(books[i].key));
        final texts = find.descendant(of: card, matching: find.byType(Text));
        expect(tester.widgetList<Text>(texts).map((text) => text.data), [
          ?labels[i],
          books[i].title,
        ]);
        final cover = tester.getRect(
          find.descendant(of: card, matching: find.byType(BookCover)),
        );
        expect(cover.height / cover.width, closeTo(1.5, .001));
        if (labels[i] case final label?) {
          final badge = tester.getRect(find.text(label));
          expect(badge.left - cover.left, closeTo(10, .001));
          expect(cover.bottom - badge.bottom, closeTo(8, .001));
        }
        final title = tester.widget<Text>(find.text(books[i].title));
        expect(title.maxLines, 2);
        expect(title.overflow, TextOverflow.ellipsis);
      }
      expect(find.textContaining('63%'), findsNothing);
      expect(find.textContaining('已读完'), findsNothing);
      expect(find.textContaining('已读至最新'), findsNothing);
      for (var i = 0; i < 2; i++) {
        if (i == 1) {
          expect(find.text('epub · 阅读进度 63%'), findsOneWidget);
          expect(find.text('txt · 已读完'), findsOneWidget);
          expect(find.text('已读至最新'), findsOneWidget);
        }
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(Chip), findsNothing);
        expect(find.textContaining('76 / 120'), findsNothing);
        expect(find.textContaining('42%'), findsNothing);
        if (i == 0) {
          await tester.tap(find.byTooltip('列表'));
          await tester.pumpAndSettle();
        }
      }
      await tester.pumpWidget(const SizedBox());
      controller.onDelete();
      controller.dispose();
      await repo.close();
    },
  );
  testWidgets(
    'home and history show book snapshot without requesting catalog',
    (tester) async {
      final env = FixtureEnvironment();
      await seed(
        env.library,
        env.source.data.summary(FixtureScenario.shortChapter),
        BookProgressSnapshot(fraction: .6399, chapterCount: 120),
      );
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          homeBuilder: (_, _) => ReadingHome(
            repository: env.novels,
            library: env.library,
            sources: [env.source.descriptor],
            environmentLabel: 'Test',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reading progress 63%'), findsOneWidget);
      expect(find.textContaining('42%'), findsNothing);
      expect(env.source.controls.calls, isEmpty);
      final controller = LibraryController(env.library)..onStart();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HistoryScreen(controller: controller, onContinue: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reading progress 63%'), findsOneWidget);
      expect(env.source.controls.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      controller.onDelete();
      controller.dispose();
      await env.close();
    },
  );
}
