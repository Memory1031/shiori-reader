import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/media/local_image_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/shared/source_image.dart';

import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import '../../data/local/support/epub_fixtures.dart';
import 'local_reading_test.dart' show MemoryBooks;
import 'restore_test.dart' show anchor;
import 'settings_test.dart' show Store;
import 'source_image_test.dart' show frames;

// Core pagination, persistence and rich-text contracts run in their own files.
// Here the real Reader chooses its columns from the window's logical width.
void expectGeometry(
  WidgetTester tester, {
  required Size physical,
  required double dpr,
  required int columns,
  required double width,
}) {
  final viewport = find.byType(PagedReaderViewport);
  final context = tester.element(viewport);
  final logical = physical / dpr;
  expect(tester.view.physicalSize, physical);
  expect(tester.view.devicePixelRatio, dpr);
  expect(MediaQuery.sizeOf(context), logical);
  expect(MediaQuery.devicePixelRatioOf(context), dpr);
  expect(tester.getSize(find.byType(ReaderContentView)), logical);
  expect(tester.widget<PagedReaderViewport>(viewport).columns, columns);
  expect(tester.getSize(viewport).width, closeTo(width, .01));
}

// A retained capture alone can hide stale paint. Locate the actual source
// character in a rendered fragment and require its glyph box inside the page.
Rect expectSourceVisible(WidgetTester tester, ParagraphBlock block, int cp) {
  final source = block.text.runes.toList();
  final fragment = find.byWidgetPredicate(
    (w) =>
        w is ReaderLinkedText &&
        w.flow == null &&
        w.blockOffset <= cp &&
        w.blockOffset + w.text.runes.length > cp &&
        w.text ==
            String.fromCharCodes(
              source.skip(w.blockOffset).take(w.text.runes.length),
            ),
  );
  expect(fragment, findsOneWidget);
  final text = tester.widget<ReaderLinkedText>(fragment);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: fragment, matching: find.byType(RichText)),
  );
  final start =
      text.prefix.length +
      String.fromCharCodes(source.sublist(text.blockOffset, cp)).length;
  final end = start + String.fromCharCode(source[cp]).length;
  final box = paragraph
      .getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end))
      .single
      .toRect()
      .shift(paragraph.localToGlobal(Offset.zero));
  final viewport = tester.getRect(find.byType(PagedReaderViewport));
  expect(box.isEmpty, isFalse);
  expect(viewport.contains(box.topLeft), isTrue);
  expect(viewport.contains(box.bottomRight), isTrue);
  return box;
}

void main() {
  testWidgets(
    'desktop resize and display scaling retain visible semantic position',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.longChapter),
        title: 'Desktop resize',
        blocks: [
          for (var i = 0; i < 80; i++)
            ParagraphBlock(
              text: 'Paragraph $i. ${'Reading paragraph $i. ' * 30}',
            ),
        ],
      );
      final controller = PagedReaderController();
      await tester.pumpWidget(
        ShioriApp(
          routes: AppRoutes(
            home: (_) => ReaderContentView(
              content: content,
              viewportController: controller,
              settings: Store()..value = ReaderSettings(controlsHintSeen: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = anchor(content, 30, .4);
      final block = content.blocks[30] as ParagraphBlock;
      final cp = (block.text.runes.length * .4).round();
      controller.restore(target);
      await tester.pumpAndSettle();
      final readerState = tester.state(find.byType(ReaderContentView));
      final viewportState = tester.state(find.byType(PagedReaderViewport));
      expectGeometry(
        tester,
        physical: const Size(1280, 720),
        dpr: 1,
        columns: 2,
        width: 1220,
      );
      expect(controller.capture(), target);
      expectSourceVisible(tester, block, cp);
      final originalText = tester
          .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
          .map((w) => (w.blockOffset, w.text))
          .toList();

      // First change only DPR: 1920/1.5 = 1280, 1080/1.5 = 720.
      // Later change logical width, including an actual double -> single ->
      // double page transition. Never remount the Reader during these changes.
      for (final display in [
        (const Size(1920, 1080), 1.5, 2, 1220.0),
        (const Size(1920, 1080), 1.0, 2, 1432.0),
        (const Size(2560, 1440), 1.5, 2, 1432.0),
        (const Size(900, 720), 1.0, 1, 680.0),
        (const Size(1280, 720), 1.0, 2, 1220.0),
      ]) {
        tester.view
          ..physicalSize = display.$1
          ..devicePixelRatio = display.$2;
        await tester.pumpAndSettle();
        expectGeometry(
          tester,
          physical: display.$1,
          dpr: display.$2,
          columns: display.$3,
          width: display.$4,
        );
        expect(tester.state(find.byType(ReaderContentView)), same(readerState));
        expect(
          tester.state(find.byType(PagedReaderViewport)),
          same(viewportState),
        );
        expect(
          tester
              .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
              .controller,
          same(controller),
        );
        expect(controller.isRestoring, isFalse);
        expect(controller.capture(), target);
        expectSourceVisible(tester, block, cp);
        final page = tester.getRect(find.byType(PagedReaderViewport));
        final textRects = [
          for (final element in find.byType(ReaderLinkedText).evaluate())
            tester.getRect(find.byWidget(element.widget)),
        ];
        if (display.$3 == 2) {
          expect(textRects.any((r) => r.right <= page.center.dx), isTrue);
          expect(textRects.any((r) => r.left >= page.center.dx), isTrue);
        } else {
          expect(textRects.every((r) => r.width > 660), isTrue);
          expect(
            tester
                .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
                .map((w) => (w.blockOffset, w.text))
                .toList(),
            isNot(originalText),
          );
        }
        if (display.$1 == const Size(1920, 1080) && display.$2 == 1.5) {
          expect(
            tester
                .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
                .map((w) => (w.blockOffset, w.text))
                .toList(),
            originalText,
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      final next = controller.capture()!;
      expect(next.chapterFraction, greaterThan(target.chapterFraction));
      final nextBlock = content.blocks[next.blockIndex] as ParagraphBlock;
      expectSourceVisible(
        tester,
        nextBlock,
        (nextBlock.text.runes.length * next.blockFraction).round(),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expectSourceVisible(tester, block, cp);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Windows wide rich link hits and opens the containing spread',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 1.5;
      addTearDown(tester.view.reset);
      final files = epubFiles();
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<html><body><p>PARAGRAPH_START ${'Before the destination. ' * 240}'
        '<a id="target" href="b.xhtml"><strong><em>MARKER</em></strong></a>'
        '${'After the destination. ' * 150}</p></body></html>',
      );
      files['OPS/text/b.xhtml'] = utf8.encode(
        '<html><body><p><a href="a.xhtml#target"><strong>BACK</strong></a></p></body></html>',
      );
      final book = EpubParser(
        zipFiles(files),
        LocalBookIdentity.book('d' * 64),
        'desktop-links.epub',
      ).parse().content;
      final repo = LocalReadingRepository(
        local: MemoryBooks(
          LocalBookRecord(
            content: book,
            format: LocalBookFormat.epub,
            importedAt: DateTime.utc(2026),
          ),
        ),
        online: ForbiddenOnline(),
      );
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: book.chapters.last.key,
              repository: repo,
              settings: Store()..value = ReaderSettings(controlsHintSeen: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectGeometry(
        tester,
        physical: const Size(1920, 1080),
        dpr: 1.5,
        columns: 2,
        width: 1220,
      );
      final backBlock = book.chapters.last.blocks.single as ParagraphBlock;
      // Use glyph hit testing, not a recognizer callback or a navigation action.
      await tester.tapAt(expectSourceVisible(tester, backBlock, 1).center);
      await tester.pumpAndSettle();
      final view = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView),
      );
      expect(view.content.key, book.chapters.first.key);
      expectGeometry(
        tester,
        physical: const Size(1920, 1080),
        dpr: 1.5,
        columns: 2,
        width: 1220,
      );
      final targetBlock = book.chapters.first.blocks.single as ParagraphBlock;
      final cp = targetBlock.text.indexOf('MARKER'); // ASCII fixture offsets.
      final marker = expectSourceVisible(tester, targetBlock, cp);
      expect(
        find.textContaining('PARAGRAPH_START', findRichText: true),
        findsNothing,
      );
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      expect(viewport.controller.capture()!.blockFraction, greaterThan(0));
      final rich = tester.widgetList<RichText>(find.byType(RichText));
      TextSpan? marked;
      for (final text in rich) {
        text.text.visitChildren((span) {
          if (span is TextSpan && span.text == 'MARKER') marked = span;
          return true;
        });
      }
      expect(marked, isNotNull);
      expect(marked!.style!.fontWeight, FontWeight.bold);
      expect(marked!.style!.fontStyle, FontStyle.italic);
      await tester.tapAt(marker.center);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaderContentView>(find.byType(ReaderContentView))
            .content
            .key,
        book.chapters.last.key,
      );
      expectSourceVisible(tester, backBlock, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'DPR alone redecodes inline and block images without moving the spread',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final files = epubFiles();
      files['OPS/images/星 空.png'] = fixturePng(1024, 1024, 7);
      final parsed = EpubParser(
        zipFiles(files),
        LocalBookIdentity.book('e' * 64),
        'desktop-images.epub',
      ).parse();
      final ref = parsed.content.chapters.first.blocks
          .whereType<ImageBlock>()
          .single
          .media;
      final store = MemoryBooks(
        LocalBookRecord(
          content: parsed.content,
          format: LocalBookFormat.epub,
          importedAt: DateTime.utc(2026),
        ),
        media: parsed.media,
      );
      final images = LocalImageRepository(
        local: store,
        online: ForbiddenOnline(),
      );
      final content = ChapterContent(
        key: parsed.content.chapters.first.key,
        title: 'Desktop images',
        blocks: [
          ParagraphBlock(
            text: 'Inline \uFFFC picture',
            inlineImages: [
              InlineImage(offset: 7, media: ref, widthEm: 2, heightEm: 1),
            ],
          ),
          ImageBlock(media: ref, width: 1024, height: 1024),
          ParagraphBlock(text: 'Following prose. ' * 120),
        ],
      );
      final controller = PagedReaderController();
      await tester.pumpWidget(
        ShioriApp(
          routes: AppRoutes(
            home: (_) => ReaderContentView(
              content: content,
              images: images,
              viewportController: controller,
              settings: Store()..value = ReaderSettings(controlsHintSeen: true),
            ),
          ),
        ),
      );
      await frames(tester);
      expectGeometry(
        tester,
        physical: const Size(1280, 720),
        dpr: 1,
        columns: 2,
        width: 1220,
      );
      final sources = find.byType(SourceImage);
      expect(sources, findsNWidgets(2));
      final states = [
        for (final e in sources.evaluate())
          tester.state(find.byWidget(e.widget)),
      ];
      final bounds = [
        for (final e in sources.evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];
      expect(bounds.map((r) => r.width), [40, 574]);
      List<int> decodedWidths() => tester
          .widgetList<RawImage>(find.byType(RawImage))
          .map((w) => w.image!.width)
          .toList();
      expect(decodedWidths(), [40, 574]);
      final position = controller.capture();
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 1.5;
      await frames(tester);
      expectGeometry(
        tester,
        physical: const Size(1920, 1080),
        dpr: 1.5,
        columns: 2,
        width: 1220,
      );
      expect(sources, findsNWidgets(2));
      expect(decodedWidths(), [60, 861]);
      final elements = sources.evaluate().toList();
      for (var i = 0; i < elements.length; i++) {
        final source = find.byWidget(elements[i].widget);
        expect(tester.state(source), same(states[i]));
        expect(tester.getRect(source), bounds[i]);
      }
      expect(controller.capture(), position);
      expect(find.textContaining('Inline', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
    },
  );
}
