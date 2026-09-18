import 'dart:ui' as ui;
import 'package:shiori/features/reader/reader_authored_colors.dart';
import 'package:flutter/material.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:flutter/gestures.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/viewport/block_style.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import 'package:shiori/features/reader/viewport/reader_box.dart';

void main() {
  for (final width in [240.0, 800.0]) {
    for (final centered in [false, true]) {
      testWidgets('box placement at width $width, centered=$centered', (
        tester,
      ) async {
        final content = ChapterContent(
          key: fixtureChapterKey(FixtureScenario.shortChapter),
          title: 'Contents',
          blocks: [
            for (final text in ['CONTENTS', 'Chapter'])
              ParagraphBlock(
                text: text,
                alignment: ParagraphAlignment.center,
                box: BlockBox(
                  group: 0,
                  width: 304,
                  maxWidthFraction: 1,
                  centered: centered,
                ),
              ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: width,
                height: 400,
                child: PagedReaderViewport(
                  content: content,
                  controller: PagedReaderController(),
                  textStyle: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final frames = find.byWidgetPredicate(
          (w) => w is ReaderBoxFrame && w.box != null,
        );
        expect(frames, findsNWidgets(2));
        for (final frame in frames.evaluate()) {
          final frameFinder = find.byWidget(frame.widget);
          final text = find.descendant(
            of: frameFinder,
            matching: find.byType(ReaderLinkedText),
          );
          final outer = tester.getRect(frameFinder);
          final inner = tester.getRect(text);
          expect(inner.width, closeTo(outer.width.clamp(0, 304), .01));
          if (centered) {
            expect(inner.center.dx, closeTo(outer.center.dx, .01));
          } else {
            expect(inner.left, closeTo(outer.left, .01));
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  test(
    'box children use authored gaps instead of reader paragraph spacing',
    () {
      final box = BlockBox(group: 0, padding: 5, borderWidth: 1);
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.shortChapter),
        title: 'Box',
        blocks: [
          ParagraphBlock(text: 'First', box: box),
          ParagraphBlock(text: '', box: box, authoredGapEm: .4),
          ParagraphBlock(text: 'Last', box: box),
        ],
      );
      PageLayout make(double spacing) => PageLayout(
        index: ChunkIndex(content),
        width: 300,
        height: 500,
        style: const TextStyle(fontSize: 20, height: 1),
        scaler: TextScaler.linear(2),
        direction: TextDirection.ltr,
        paragraphSpacing: spacing,
      );
      final compact = make(0).forward(const PageCursor(0, 0))!;
      final spaced = make(40).forward(const PageCursor(0, 0))!;
      expect(
        spaced.fragments.map((f) => f.height),
        compact.fragments.map((f) => f.height),
      );
      expect(spaced.fragments[1].height, 16);
      expect(readerBlockSpacing(ParagraphBlock(text: 'Outside'), 40), 40);
    },
  );

  testWidgets(
    'reader paper fills the page while authored background stays inside its box',
    (tester) async {
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.shortChapter),
        title: 'Paper',
        blocks: [
          ParagraphBlock(text: 'Plain text'),
          ParagraphBlock(
            text: 'Card',
            box: BlockBox(
              group: 0,
              width: 180,
              padding: 8,
              borderWidth: 1,
              borderColor: 0xffdccedf,
              backgroundColor: 0xfffefafb,
            ),
          ),
        ],
      );
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final theme = readerTheme(
          ReaderSettings(paper: ReaderPaper.warm),
          brightness,
        );
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(scaffoldBackgroundColor: const Color(0xfffef7ff)),
            home: Theme(
              data: theme,
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: 300,
                    height: 400,
                    child: PagedReaderViewport(
                      content: content,
                      controller: PagedReaderController(),
                      textStyle: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final card = find.byWidgetPredicate(
          (w) => w is ReaderBoxFrame && w.box != null,
        );
        final local =
            tester.getTopLeft(card) - tester.getTopLeft(find.byKey(key));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          int pixel(int x, int y) {
            final i = (y * image.width + x) * 4;
            return (bytes.getUint8(i + 3) << 24) |
                (bytes.getUint8(i) << 16) |
                (bytes.getUint8(i + 1) << 8) |
                bytes.getUint8(i + 2);
          }

          expect(pixel(299, 399), theme.scaffoldBackgroundColor.toARGB32());
          expect(
            pixel(local.dx.toInt() + 3, local.dy.toInt() + 3),
            ReaderAuthoredColors(theme)
                .resolve(const Color(0xfffefafb), ReaderColorRole.background)
                .toARGB32(),
          );
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets('styled links retain typography and their tap recognizer', (
    tester,
  ) async {
    final chapter = fixtureChapterKey(FixtureScenario.shortChapter);
    final block = ParagraphBlock(
      text: 'ABCD',
      inlineStyles: [
        InlineTextStyle(
          start: 1,
          length: 2,
          fontScale: 1.3,
          bold: true,
          italic: true,
        ),
      ],
    );
    final link = LocalContentLink(
      source: chapter,
      sourceBlockKey: block.blockKey,
      label: 'BC',
      target: chapter,
      sourceOffset: 1,
      sourceLength: 2,
    );
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderLinkedText(
          text: block.text,
          prefix: '',
          blockOffset: 0,
          links: [link],
          inlineStyles: block.inlineStyles,
          style: const TextStyle(fontSize: 20),
          align: TextAlign.start,
          scaler: TextScaler.noScaling,
          onLink: (_) => taps++,
        ),
      ),
    );
    final rich = tester.widget<RichText>(
      find.descendant(
        of: find.byType(ReaderLinkedText),
        matching: find.byType(RichText),
      ),
    );
    TextSpan? linked;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) linked = span;
      return true;
    });
    expect(linked, isNotNull);
    expect(linked!.style!.fontSize, 26);
    expect(linked!.style!.fontWeight, FontWeight.bold);
    expect(linked!.style!.fontStyle, FontStyle.italic);
    (linked!.recognizer! as TapGestureRecognizer).onTap!();
    expect(taps, 1);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'rich inline text and box fit measured pages at text scale $scale',
      (tester) async {
        final text = List.generate(30, (i) => '文字😀\uFFFC后文$i。').join();
        final runes = text.runes.toList();
        final block = ParagraphBlock(
          text: text,
          box: BlockBox(
            group: 0,
            width: 240,
            padding: 5,
            borderWidth: 2,
            borderColor: 0xff9161a4,
          ),
          inlineStyles: [
            for (var i = 0; i < runes.length; i += 11)
              InlineTextStyle(
                start: i,
                length: (runes.length - i).clamp(1, 11),
                fontScale: i % 2 == 0 ? 1.3 : .8,
                color: 0xff9161a4,
                bold: i % 2 == 0,
                italic: i % 3 == 0,
              ),
          ],
          inlineImages: [
            for (var i = 0; i < runes.length; i++)
              if (runes[i] == 0xfffc)
                InlineImage(
                  offset: i,
                  media: fixtureMediaRef(0),
                  widthEm: .75,
                  heightEm: 1,
                ),
          ],
        );
        final content = ChapterContent(
          key: fixtureChapterKey(FixtureScenario.shortChapter),
          title: 'Inline',
          blocks: [block],
        );
        const style = TextStyle(fontSize: 20, height: 1.6);
        final scaler = TextScaler.linear(scale);
        final layout = PageLayout(
          index: ChunkIndex(content, maxCodePoints: 32),
          width: 300,
          height: 220,
          style: style,
          scaler: scaler,
          direction: TextDirection.ltr,
          paragraphSpacing: 16,
        );
        var cursor = const PageCursor(0, 0);
        final seen = StringBuffer();

        var pages = 0;
        while (true) {
          final page = layout.forward(cursor);
          if (page == null) break;
          expect(++pages, lessThan(100));
          for (final fragment in page.fragments) {
            final chunk = layout.index.chunks[fragment.unit];
            seen.write(fragment.text);
            final width = readerBlockWidth(
              block,
              300,
              style,
              scaler,
              TextDirection.ltr,
              chapter: content.key,
            );
            await tester.pumpWidget(
              MaterialApp(
                home: Center(
                  child: SizedBox(
                    width: width,
                    child: ReaderLinkedText(
                      text: fragment.text!,
                      prefix: '',
                      blockOffset: chunk.start + fragment.start,
                      inlineImages: block.inlineImages,
                      inlineStyles: block.inlineStyles,
                      links: const [],
                      style: style,
                      align: TextAlign.start,
                      scaler: scaler,
                    ),
                  ),
                ),
              ),
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.byType(ReaderLinkedText),
                matching: find.byType(RichText),
              ),
            );
            expect(
              paragraph.size.height,
              lessThanOrEqualTo(
                fragment.height -
                    readerBlockSpacing(block, 16) -
                    fragment.boxTop -
                    fragment.boxBottom +
                    .01,
              ),
            );
            for (final box in paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: fragment.text!.length),
            )) {
              expect(box.bottom, lessThanOrEqualTo(fragment.height + .01));
            }
            expect(tester.takeException(), isNull);
          }
          cursor = page.end;
        }
        expect(seen.toString(), text);
        expect(readerBoxOuterWidth(block, 300), 254);
        final reverse = <String>[];
        while (true) {
          final page = layout.backward(cursor);
          if (page == null) break;
          reverse.add(page.fragments.map((f) => f.text ?? '').join());
          cursor = page.start;
          expect(reverse.length, lessThan(100));
        }
        expect(reverse.reversed.join(), text);
      },
    );
  }
}
