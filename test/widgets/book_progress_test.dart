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
        BookProgressSnapshot(fraction: .63, chapterCount: 120),
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
        BookProgressSnapshot(fraction: .63, chapterCount: 120),
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
