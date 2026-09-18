import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/rendering.dart';
import 'package:shiori/features/reader/viewport/block_style.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/domain/models/models.dart';
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
  for (final route in ['same', 'main', 'auxiliary']) {
    testWidgets(
      'fragment backlink seeks the page containing an inline anchor: $route',
      (tester) async {
        final files = linkedEpub();
        final targetPath = route == 'auxiliary'
            ? 'OPS/notes.xhtml'
            : 'OPS/text/a.xhtml';
        final targetHref = route == 'auxiliary'
            ? 'notes.xhtml'
            : 'text/a.xhtml';
        // Keep the target beyond the first spread even on a wide desktop.
        final body =
            '<p>PARAGRAPH_START ${'正文😀跨页内容。' * 480}<a id="b5" href="#note">MARKER5</a>${'后文。' * 50}</p>';
        files[targetPath] = utf8.encode(
          '<html><body>$body<p id="note"><a href="#b5">BACK</a></p></body></html>',
        );
        if (route != 'same') {
          files['OPS/last.xhtml'] = utf8.encode(
            '<html><body><p><a href="$targetHref#b5">BACK</a></p></body></html>',
          );
        }
        final c = EpubParser(
          zipFiles(files),
          linkBookKey,
          'book',
        ).parse().content;
        final source = route == 'same' ? c.chapters.first : c.chapters.last;
        final repo = LocalReadingRepository(
          online: ForbiddenOnline(),
          local: MemoryBooks(
            LocalBookRecord(
              content: c,
              format: LocalBookFormat.epub,
              importedAt: DateTime.utc(2025),
            ),
          ),
        );
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
                chapter: source.key,
                repository: repo,
                initialBlockKey: source.blocks.last.blockKey,
                startAtBeginning: true,
                settings: settings,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final back = find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == 'BACK',
        );
        final render = tester.renderObject<RenderParagraph>(back);
        final rect = render
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 4),
            )
            .first
            .toRect();
        await tester.tapAt(render.localToGlobal(rect.center));
        await tester.pumpAndSettle();
        final displayed = tester
            .widgetList<RichText>(find.byType(RichText))
            .map((w) => w.text.toPlainText())
            .join();
        expect(displayed, contains('MARKER5'));
        expect(displayed, isNot(contains('PARAGRAPH_START')));
        final viewport = tester.widget<PagedReaderViewport>(
          find.byType(PagedReaderViewport),
        );
        expect(viewport.controller.capture()!.blockFraction, greaterThan(0));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'authored TOC lines navigate directly and same-chapter links retain session',
    (tester) async {
      final files = linkedEpub();
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<html><body><a href="../last.xhtml"><p>【第三话】</p><p>Subtitle</p></a><p><a href="#end">Within chapter</a></p>${List.filled(20, '<p>Filler text.</p>').join()}<p id="end">Destination</p></body></html>',
      );
      final c = EpubParser(
        zipFiles(files),
        linkBookKey,
        'book',
      ).parse().content;
      final repo = LocalReadingRepository(
        online: ForbiddenOnline(),
        local: MemoryBooks(
          LocalBookRecord(
            content: c,
            format: LocalBookFormat.epub,
            importedAt: DateTime.utc(2025),
          ),
        ),
      );
      final library = FixtureLibraryRepository();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: c.chapters.first.key,
              repository: repo,
              library: library,
              settings: FixtureSettingsStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      ReaderContentView view() =>
          tester.widget<ReaderContentView>(find.byType(ReaderContentView));
      final session = view().session;
      final links = c.links
          .where((l) => l.source == c.chapters.first.key)
          .toList();
      expect(links.where((l) => l.target == c.chapters.last.key), hasLength(2));
      Future<void> click(String text) async {
        final finder = find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == text,
        );
        final render = tester.renderObject<RenderParagraph>(finder);
        final box = render
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: text.length),
            )
            .first;
        await tester.tapAt(render.localToGlobal(box.toRect().center));
        await tester.pumpAndSettle();
      }

      await click('Within chapter');
      expect(view().session, same(session));
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      expect(
        viewport.controller.capture()!.blockKey,
        c.chapters.first.blocks.last.blockKey,
      );
      viewport.controller.restore(
        ReaderPosition(
          contentRevision: c.chapters.first.contentRevision,
          blockKey: c.chapters.first.blocks.first.blockKey,
          blockIndex: 0,
          blockFraction: 0,
          chapterFraction: 0,
        ),
      );
      await tester.pumpAndSettle();
      await click('Subtitle');
      expect(view().content.key, c.chapters.last.key);
      expect(view().session!.library, same(library));
      expect(find.byType(BookReaderScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await library.close();
    },
  );

  test(
    'local paragraphs retain authored style while semantic headings remain large',
    () {
      final chapter = LocalBookIdentity.chapter(linkBookKey, 'epub:toc');
      final paragraph = ParagraphBlock(text: '【第三话】', leadingIndent: 2);
      const style = TextStyle(fontSize: 20);
      expect(readerBlockStyle(paragraph, style, chapter: chapter), style);
      expect(readerBlockAlign(paragraph, chapter: chapter), TextAlign.start);
      expect(readerBlockSpacing(paragraph, 20, chapter: chapter), 20);
      expect(
        readerIndentPrefix(
          paragraph,
          true,
          300,
          style,
          TextScaler.noScaling,
          chapter: chapter,
        ),
        '\u2003\u2003',
      );
      expect(
        readerBlockStyle(
          HeadingBlock(text: '【第三话】', level: 1),
          style,
          chapter: chapter,
        ).fontSize,
        28,
      );
    },
  );
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
