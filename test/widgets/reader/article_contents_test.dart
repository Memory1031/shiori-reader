import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'package:shiori/features/reader/article_contents.dart';
import 'package:shiori/features/reader/viewport/block_style.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/dev/viewport/reader_viewport.dart';

void main() {
  test(
    'CJK width balances spare space without changing explicit alignment',
    () {
      const style = TextStyle(fontSize: 20);
      for (final scale in [1.0, 1.5, 2.0]) {
        final scaler = TextScaler.linear(scale);
        final body = ParagraphBlock(text: '自然字距的中文正文');
        final width = readerBlockWidth(
          body,
          317,
          style,
          scaler,
          TextDirection.ltr,
        );
        expect(width, lessThanOrEqualTo(317));
        expect(width, greaterThan(317 - 20 * scale));
        expect(readerBlockAlign(body), TextAlign.start);
        for (final block in <ContentBlock>[
          HeadingBlock(text: '章节标题', level: 1),
          ParagraphBlock(text: '居中文本', alignment: ParagraphAlignment.center),
          ParagraphBlock(text: 'English text'),
        ]) {
          expect(
            readerBlockWidth(block, 317, style, scaler, TextDirection.ltr),
            317,
          );
        }
      }
    },
  );

  test(
    'chapter typography centers major headings and preserves explicit alignment',
    () {
      const base = TextStyle(fontSize: 20, height: 1.6);
      final heading = HeadingBlock(text: '（原）三年F组学号39号 吉田由希的证言', level: 1);
      expect(readerBlockAlign(heading), TextAlign.center);
      expect(readerBlockStyle(heading, base).fontSize, 28);
      expect(readerBlockStyle(heading, base).fontWeight, FontWeight.w700);
      expect(readerBlockSpacing(heading, 20), 84);
      expect(
        readerBlockAlign(ParagraphBlock(text: '【第一话】 章节标题')),
        TextAlign.center,
      );
      expect(
        readerBlockAlign(
          HeadingBlock(text: '署名', level: 1, alignment: ParagraphAlignment.end),
        ),
        TextAlign.end,
      );
      expect(
        readerBlockAlign(HeadingBlock(text: '较低层级', level: 3)),
        TextAlign.start,
      );
      expect(readerBlockAlign(ParagraphBlock(text: '普通正文')), TextAlign.start);
      expect(
        readerBlockAlign(ParagraphBlock(text: 'English prose')),
        TextAlign.start,
      );
      expect(
        readerBlockAlign(
          ParagraphBlock(text: '中文署名', alignment: ParagraphAlignment.end),
        ),
        TextAlign.end,
      );
      expect(
        readerBlockAlign(
          ParagraphBlock(text: '中文题记', alignment: ParagraphAlignment.center),
        ),
        TextAlign.center,
      );
      expect(readerBlockSpacing(ParagraphBlock(text: '普通正文'), 20), 20);
    },
  );

  test(
    'online body fallback preserves source data and paragraph boundaries',
    () {
      final online = fixtureChapterKey(FixtureScenario.shortChapter);
      final local = ChapterKey(
        novelKey: NovelKey(
          sourceId: LocalBookIdentity.sourceId,
          novelId: 'test',
        ),
        chapterId: 'one',
      );
      const style = TextStyle(fontSize: 20);
      String prefix(ContentBlock block, {bool start = true, ChapterKey? key}) =>
          readerIndentPrefix(
            block,
            start,
            320,
            style,
            TextScaler.noScaling,
            chapter: key ?? online,
          );
      final body = ParagraphBlock(text: '普通中文正文。');
      expect(prefix(body), '\u2003\u2003');
      expect(body.text, '普通中文正文。');
      expect(body.leadingIndent, 0);
      expect(prefix(body, start: false), isEmpty);
      expect(prefix(body, key: local), isEmpty);
      expect(prefix(ParagraphBlock(text: '已有缩进', leadingIndent: 1)), '\u2003');
      expect(prefix(ParagraphBlock(text: '　　已有空格')), isEmpty);
      expect(prefix(ParagraphBlock(text: '')), isEmpty);
      expect(prefix(ParagraphBlock(text: 'English prose')), isEmpty);
      expect(prefix(HeadingBlock(text: '章节标题', level: 1)), isEmpty);
      expect(prefix(ParagraphBlock(text: '【第一话】 标题')), isEmpty);
      for (final alignment in [
        ParagraphAlignment.center,
        ParagraphAlignment.end,
      ]) {
        expect(
          prefix(ParagraphBlock(text: '居中或靠右文字', alignment: alignment)),
          isEmpty,
        );
      }
    },
  );

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
