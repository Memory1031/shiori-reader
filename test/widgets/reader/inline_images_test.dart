import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_inline_images.dart';
import 'package:shiori/features/reader/viewport/block_style.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double size) => size <= 20 ? size * 2 : size * 1.5;
  @override
  double get textScaleFactor => 2;
}

void main() {
  test(
    'unspecified inline weight inherits reader style; explicit reset wins',
    () {
      const base = TextStyle(
        fontWeight: FontWeight.w700,
        fontStyle: FontStyle.italic,
      );
      final inherited = readerAuthoredStyle(base, [
        InlineTextStyle(start: 0, length: 1, color: 0xff880088),
      ], 0);
      expect(inherited.fontWeight, FontWeight.w700);
      expect(inherited.fontStyle, FontStyle.italic);
      final reset = readerAuthoredStyle(base, [
        InlineTextStyle(start: 0, length: 1, bold: false, italic: false),
      ], 0);
      expect(reset.fontWeight, FontWeight.normal);
      expect(reset.fontStyle, FontStyle.normal);
    },
  );
  for (final scaler in [TextScaler.linear(2), const _NonlinearScaler()]) {
    testWidgets('painted inline image matches placeholder with $scaler', (
      tester,
    ) async {
      const base = TextStyle(fontSize: 20);
      final picture = InlineImage(
        offset: 0,
        media: fixtureMediaRef(0),
        widthEm: .75,
        heightEm: 1,
      );
      final styles = [InlineTextStyle(start: 0, length: 1, fontScale: 1.3)];
      const imageKey = ValueKey('inline-picture');
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              child: Text.rich(
                TextSpan(
                  style: base,
                  children: readerInlineSpans(
                    text: '\uFFFC',
                    offset: 0,
                    images: [picture],
                    styles: styles,
                    style: base,
                    imageBuilder: (_) =>
                        const ColoredBox(key: imageKey, color: Colors.red),
                  ),
                ),
                textScaler: scaler,
              ),
            ),
          ),
        ),
      );
      final painted = tester.renderObject<RenderBox>(find.byKey(imageKey));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText).first,
      );
      final rect = MatrixUtils.transformRect(
        painted.getTransformTo(paragraph),
        Offset.zero & painted.size,
      );
      final measured = readerInlineDimensions(
        maxWidth: 300,
        offset: 0,
        length: 1,
        images: [picture],
        styles: styles,
        style: base,
        scaler: scaler,
      ).single.size;
      expect(rect.width, closeTo(measured.width, .001));
      expect(rect.height, closeTo(measured.height, .001));
      expect(rect.height, closeTo(scaler.scale(26), .001));
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('inline images fit measured pages at text scale $scale', (
      tester,
    ) async {
      final text = List.generate(30, (i) => '文字😀\uFFFC后文$i。').join();
      final runes = text.runes.toList();
      final block = ParagraphBlock(
        text: text,
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
      var placeholders = 0;
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
            lessThanOrEqualTo(fragment.height - 16 + .01),
          );
          for (final box in paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: fragment.text!.length),
          )) {
            expect(box.bottom, lessThanOrEqualTo(fragment.height + .01));
          }
          final images = find.descendant(
            of: find.byType(ReaderLinkedText),
            matching: find.byType(SizedBox),
          );
          for (final element in images.evaluate()) {
            final size = (element.widget as SizedBox);
            if (size.width == 15 && size.height == 20) placeholders++;
          }
          expect(tester.takeException(), isNull);
        }
        cursor = page.end;
      }
      expect(seen.toString(), text);
      expect(placeholders, 30);
      final reverse = <String>[];
      while (true) {
        final page = layout.backward(cursor);
        if (page == null) break;
        reverse.add(page.fragments.map((f) => f.text ?? '').join());
        cursor = page.start;
        expect(reverse.length, lessThan(100));
      }
      expect(reverse.reversed.join(), text);
    });
  }
}
