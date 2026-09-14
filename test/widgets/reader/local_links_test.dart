import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import '../../data/local/epub_links_test.dart';
import '../../data/local/support/epub_fixtures.dart';
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import 'local_reading_test.dart' show MemoryBooks;

void main() {
  for (final lang in ['en', 'zh']) {
    testWidgets(
      'auxiliary return preserves origin state and history in $lang',
      (tester) async {
        final content = EpubParser(
          zipFiles(linkedEpub(repeated: true)),
          linkBookKey,
          'book',
        ).parse().content;
        final repository = LocalReadingRepository(
          local: MemoryBooks(
            LocalBookRecord(
              content: content,
              format: LocalBookFormat.epub,
              importedAt: DateTime.utc(2025),
            ),
          ),
          online: ForbiddenOnline(),
        );
        final library = FixtureLibraryRepository();
        await tester.pumpWidget(
          ShioriApp(
            locale: Locale(lang),
            routes: AppRoutes(
              home: (_) => BookReaderScreen(
                chapter: content.chapters[1].key,
                repository: repository,
                library: library,
                settings: FixtureSettingsStore(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final originState = tester.state(find.byType(ReaderContentView));
        final origin = tester.widget<ReaderContentView>(
          find.byType(ReaderContentView),
        );
        await origin.session!.flushProgress();
        final before = await library.getProgress(
          linkBookKey,
          cancellation: CancellationSource().token,
        );
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(lang == 'en' ? 'Chapter links' : '本章链接'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('note'));
        await tester.pumpAndSettle();
        final note = tester.widget<ReaderContentView>(
          find.byType(ReaderContentView),
        );
        expect(note.content.key, content.auxiliaryChapters.single.key);
        expect(note.session!.library, isNull);
        expect(note.onNextChapter, isNull);
        expect(note.onPreviousChapter, isNull);
        if (find
            .text(lang == 'en' ? 'Return to reading' : '返回原位置')
            .evaluate()
            .isEmpty) {
          await tester.tapAt(tester.getCenter(find.byType(ReaderContentView)));
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.text(lang == 'en' ? 'Return to reading' : '返回原位置'),
        );
        await tester.pumpAndSettle();
        expect(
          identical(tester.state(find.byType(ReaderContentView)), originState),
          isTrue,
        );
        expect(
          tester
              .widget<ReaderContentView>(find.byType(ReaderContentView))
              .content
              .key,
          content.chapters[1].key,
        );
        final after = await library.getProgress(
          linkBookKey,
          cancellation: CancellationSource().token,
        );
        expect((after as Success).value, (before as Success).value);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await library.close();
      },
    );
  }
  testWidgets(
    'continuous next skips linear=no and unavailable link keeps page',
    (tester) async {
      final c = EpubParser(
        zipFiles(linkedEpub()),
        linkBookKey,
        'book',
      ).parse().content;
      final repo = LocalReadingRepository(
        local: MemoryBooks(
          LocalBookRecord(
            content: c,
            format: LocalBookFormat.epub,
            importedAt: DateTime.utc(2025),
          ),
        ),
        online: ForbiddenOnline(),
      );
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: c.chapters.first.key,
              repository: repo,
              settings: FixtureSettingsStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<ReaderContentView>(find.byType(ReaderContentView)).onLinks!(
        tester.element(find.byType(ReaderContentView)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('external'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('external'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaderContentView>(find.byType(ReaderContentView))
            .content
            .key,
        c.chapters.first.key,
      );
      expect(find.textContaining('Link unavailable'), findsOneWidget);
      tester
          .widget<ReaderContentView>(find.byType(ReaderContentView))
          .onNextChapter!();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaderContentView>(find.byType(ReaderContentView))
            .content
            .key,
        c.chapters.last.key,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('nested link limit leaves current page intact', (tester) async {
    final c = EpubParser(
      zipFiles(linkedEpub()),
      linkBookKey,
      'book',
    ).parse().content;
    final repo = LocalReadingRepository(
      local: MemoryBooks(
        LocalBookRecord(
          content: c,
          format: LocalBookFormat.epub,
          importedAt: DateTime.utc(2025),
        ),
      ),
      online: ForbiddenOnline(),
    );
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: c.chapters.first.key,
            repository: repo,
            linkDepth: 8,
            settings: FixtureSettingsStore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(ReaderContentView));
    tester.widget<ReaderContentView>(find.byType(ReaderContentView)).onLinks!(
      tester.element(find.byType(ReaderContentView)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('note'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Link depth limit'), findsOneWidget);
    expect(
      identical(state, tester.state(find.byType(ReaderContentView))),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
