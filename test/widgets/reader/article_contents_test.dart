import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/article_contents.dart';
import 'package:shiori/features/reader/viewport/block_style.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/reader_viewport.dart';

void main() {
  test(
    'source whitespace is not compounded and UI indentation is at most two em',
    () {
      const style = TextStyle(fontSize: 18, height: 1.7);
      String prefix(ParagraphBlock block) =>
          readerIndentPrefix(block, true, 320, style, TextScaler.noScaling);
      final padded = ParagraphBlock(text: '　　合成正文', leadingIndent: 4);
      expect(prefix(padded), isEmpty);
      expect(padded.text, '　　合成正文');
      expect(prefix(ParagraphBlock(text: '合成正文', leadingIndent: 8)).length, 2);
      expect(
        prefix(ParagraphBlock(text: '【第一话】 合成标题', leadingIndent: 2)),
        isEmpty,
      );
      expect(
        readerBlockStyle(ParagraphBlock(text: '【第一话】 合成标题'), style).fontSize,
        greaterThan(18),
      );
      expect(
        readerBlockStyle(ParagraphBlock(text: '(Day176)'), style).fontSize,
        lessThan(18),
      );
      expect(readerBlockStyle(ParagraphBlock(text: '普通正文。'), style), style);
    },
  );
  test(
    'bracketed episode titles and separate day markers keep original targets',
    () {
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.shortChapter),
        title: 'Synthetic bracket samples',
        blocks: [
          ParagraphBlock(text: '【第一话】 掷骰子问题'),
          ParagraphBlock(text: '【尾声】'),
          ParagraphBlock(text: '【第一话】 合成标题\n(Day176)'),
          ParagraphBlock(text: '[第２話]合成标题'),
          ParagraphBlock(text: '【第一话] 括号不匹配'),
          ParagraphBlock(text: '他说【第一话】很好看。'),
          ParagraphBlock(text: '【第一话】\n这是一段普通正文。'),
        ],
      );
      final entries = articleContents(content);
      expect(entries.map((e) => e.position.blockIndex), [0, 1, 2, 3]);
      expect(entries.first.title, '【第一话】 掷骰子问题');
      expect(entries.first.position.blockKey, content.blocks.first.blockKey);
    },
  );
  test('article headings retain opaque block positions and reject prose', () {
    final content = ChapterContent(
      key: fixtureChapterKey(FixtureScenario.shortChapter),
      title: 'Volume',
      blocks: [
        ParagraphBlock(text: '序章'),
        ParagraphBlock(text: '第一话中的人物如此说道。'),
        ParagraphBlock(text: '第一话 开始'),
        HeadingBlock(text: '相遇', level: 2),
        ParagraphBlock(text: '后记'),
        ParagraphBlock(text: '后记'),
      ],
    );
    final entries = articleContents(content);
    expect(entries.map((e) => e.position.blockIndex), [0, 2, 3, 4, 5]);
    expect(entries[3].position.blockKey, isNot(entries[4].position.blockKey));
    expect(entries.every((e) => e.position.blockFraction == 0), isTrue);
  });
  for (final paged in [false, true]) {
    testWidgets(
      'only first line indents; article target restores in paged=$paged',
      (tester) async {
        final content = ChapterContent(
          key: fixtureChapterKey(FixtureScenario.shortChapter),
          title: 'Volume',
          blocks: [
            ParagraphBlock(text: 'abcdefghij' * 30, leadingIndent: 2),
            HeadingBlock(text: '第二话 目的地', level: 2),
            ParagraphBlock(text: 'After target'),
          ],
        );
        final pages = PagedReaderController();
        final scroll = ReaderViewportController();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 280,
                height: 400,
                child: paged
                    ? PagedReaderViewport(
                        content: content,
                        controller: pages,
                        textStyle: const TextStyle(fontSize: 20, height: 1.5),
                      )
                    : ReaderViewport(
                        content: content,
                        controller: scroll,
                        textStyle: const TextStyle(fontSize: 20, height: 1.5),
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rich = find.byWidgetPredicate(
          (w) =>
              w is RichText && w.text.toPlainText().startsWith('\u2003\u2003'),
        );
        final render = tester.renderObject<RenderParagraph>(rich.first);
        expect(render.size.width, 280);
        final first = render
            .getBoxesForSelection(
              const TextSelection(baseOffset: 2, extentOffset: 3),
            )
            .first;
        final next = render.getPositionForOffset(Offset(0, first.bottom + 8));
        final second = render
            .getBoxesForSelection(
              TextSelection(
                baseOffset: next.offset,
                extentOffset: next.offset + 1,
              ),
            )
            .first;
        expect(second.left, lessThan(first.left));
        final target = articleContents(content).single.position;
        if (paged) {
          pages.restore(target);
        } else {
          scroll.restore(target);
        }
        await tester.pumpAndSettle();
        expect(
          (paged ? pages.capture() : scroll.capture())!.blockKey,
          target.blockKey,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
