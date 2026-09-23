import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_ruby.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/block_style.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double size) => size <= 20 ? size * 2 : size * 1.5;
  @override
  double get textScaleFactor => 2;
}

void main() {
  testWidgets('oversized ruby fits narrow pages without blocking pagination', (
    tester,
  ) async {
    final block = ParagraphBlock(
      text: '甲' * 64,
      inlineRuby: [InlineRuby(start: 0, length: 64, annotation: 'a' * 256)],
    );
    final key = LocalBookIdentity.chapter(
      LocalBookIdentity.book('a' * 64),
      'wide',
    );
    final content = ChapterContent(key: key, title: 'Wide', blocks: [block]);
    const style = TextStyle(fontSize: 32, height: 1.6);
    final scaler = TextScaler.linear(2);
    final layout = PageLayout(
      index: ChunkIndex(content),
      width: 160,
      height: 120,
      style: style,
      scaler: scaler,
      direction: TextDirection.ltr,
    );
    final page = layout.forward(const PageCursor(0, 0));
    expect(page, isNotNull);
    expect(page!.fragments.single.text, block.text);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 160,
            child: ReaderLinkedText(
              text: block.text,
              prefix: '',
              blockOffset: 0,
              inlineRuby: block.inlineRuby,
              links: const [],
              style: style,
              align: TextAlign.start,
              scaler: scaler,
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(ReaderRuby)).width,
      lessThanOrEqualTo(160.01),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(ReaderLinkedText),
        matching: find.byType(RichText),
      ),
    );
    expect(
      paragraph.size.height,
      closeTo(page.fragments.single.height - 16, .02),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'styled ruby shares a line with an image and remains a clickable link',
    (tester) async {
      final key = fixtureChapterKey(FixtureScenario.shortChapter);
      final block = ParagraphBlock(
        text: '头脑风暴\uFFFC尾',
        inlineRuby: [InlineRuby(start: 0, length: 4, annotation: 'buresuto')],
        inlineImages: [
          InlineImage(
            offset: 4,
            media: fixtureMediaRef(0),
            widthEm: 1,
            heightEm: 1,
          ),
        ],
        inlineStyles: [
          InlineTextStyle(start: 0, length: 2, fontScale: 1.3, bold: true),
        ],
      );
      final link = LocalContentLink(
        source: key,
        sourceBlockKey: block.blockKey,
        label: '头脑风暴',
        sourceOffset: 0,
        sourceLength: 4,
        target: key,
      );
      LocalContentLink? tapped;
      const style = TextStyle(fontSize: 20, height: 1.6);
      const scaler = _NonlinearScaler();
      final layout = PageLayout(
        index: ChunkIndex(
          ChapterContent(key: key, title: 'Ruby', blocks: [block]),
        ),
        width: 240,
        height: 400,
        style: style,
        scaler: scaler,
        direction: TextDirection.ltr,
      );
      final fragment = layout.forward(const PageCursor(0, 0))!.fragments.single;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 240,
              child: ReaderLinkedText(
                text: block.text,
                prefix: readerIndentPrefix(
                  block,
                  true,
                  240,
                  style,
                  scaler,
                  chapter: key,
                ),
                blockOffset: 0,
                inlineRuby: block.inlineRuby,
                inlineImages: block.inlineImages,
                inlineStyles: block.inlineStyles,
                links: [link],
                onLink: (value) => tapped = value,
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
      expect(paragraph.size.height, closeTo(fragment.height - 16, .02));
      await tester.tap(find.byType(ReaderRuby));
      expect(tapped, same(link));
      expect(tester.takeException(), isNull);
    },
  );
  for (final scaler in [
    TextScaler.noScaling,
    TextScaler.linear(2),
    const _NonlinearScaler(),
  ]) {
    for (final width in [240.0, 500.0]) {
      testWidgets('ruby pagination matches paint at $width and $scaler', (
        tester,
      ) async {
        final unit = '😀讨论头脑风暴之后，继续阅读。';
        final text = List.filled(20, unit).join();
        final ruby = [
          for (var i = 0; i < 20; i++)
            InlineRuby(
              start: i * unit.runes.length + 3,
              length: 4,
              annotation: 'buresuto',
            ),
        ];
        final block = ParagraphBlock(text: text, inlineRuby: ruby);
        final content = ChapterContent(
          key: fixtureChapterKey(FixtureScenario.shortChapter),
          title: 'Ruby',
          blocks: [block],
        );
        final index = ChunkIndex(content, maxCodePoints: 32);
        for (final chunk in index.chunks) {
          expect(
            ruby.any((r) => r.start < chunk.end && chunk.end < r.end),
            isFalse,
          );
        }
        const style = TextStyle(fontSize: 20, height: 1.6);
        final layout = PageLayout(
          index: index,
          width: width,
          height: 250,
          style: style,
          scaler: scaler,
          direction: TextDirection.ltr,
        );
        var cursor = const PageCursor(0, 0);
        final seen = StringBuffer();
        var pages = 0;
        while (cursor.unit < index.chunks.length) {
          final page = layout.forward(cursor);
          expect(page, isNotNull, reason: 'must make progress');
          expect(++pages, lessThan(150));
          for (final fragment in page!.fragments) {
            seen.write(fragment.text);
            final offset = index.chunks[fragment.unit].start + fragment.start;
            final end = index.chunks[fragment.unit].start + fragment.end;
            expect(ruby.any((r) => r.start < end && end < r.end), isFalse);
            await tester.pumpWidget(
              MaterialApp(
                home: Center(
                  child: SizedBox(
                    width: width,
                    child: ReaderLinkedText(
                      text: fragment.text!,
                      prefix: readerIndentPrefix(
                        block,
                        offset == 0,
                        width,
                        style,
                        scaler,
                        chapter: content.key,
                      ),
                      blockOffset: offset,
                      inlineRuby: ruby,
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
            expect(paragraph.size.height, closeTo(fragment.height - 16, .02));
            for (final element in find.byType(ReaderRuby).evaluate()) {
              final widget = element.widget as ReaderRuby;
              final rect = tester.getRect(find.byWidget(widget));
              expect(
                rect.width,
                closeTo(widget.layout.metrics.size.width, .02),
              );
              expect(
                rect.height,
                closeTo(widget.layout.metrics.size.height, .02),
              );
            }
            expect(tester.takeException(), isNull);
          }
          cursor = page.end;
        }
        expect(seen.toString(), text);
        final backwards = <String>[];
        while (cursor.unit > 0 || cursor.offset > 0) {
          final page = layout.backward(cursor);
          expect(page, isNotNull);
          backwards.add(page!.fragments.map((f) => f.text ?? '').join());
          cursor = page.start;
        }
        expect(backwards.reversed.join(), text);
      });
    }
  }
}
