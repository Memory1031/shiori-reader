import '../../data/local/epub_prose_semantics_test.dart' show paragraphs;
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/dev/viewport/reader_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/viewport/paragraph_flow.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

const style = TextStyle(fontSize: 20, height: 1.5);
ChapterContent chapter(ParagraphBlock block) => ChapterContent(
  key: ChapterKey(
    novelKey: NovelKey(sourceId: SourceId('local'), novelId: 'flow'),
    chapterId: '1',
  ),
  title: 'Flow',
  blocks: [
    block,
    ParagraphBlock(text: 'Next message'),
  ],
);
ParagraphFlow flow(
  ParagraphBlock block,
  double width, {
  double scale = 1,
  int offset = 0,
}) => readerParagraphFlow(
  block: block,
  text: String.fromCharCodes(block.text.runes.skip(offset)),
  offset: offset,
  width: width,
  style: style,
  scaler: TextScaler.linear(scale),
);
void main() {
  testWidgets(
    'label-only flow keeps authored whitespace and narrow indent limits',
    (tester) async {
      for (final (body, indent, width, scale, expected) in [
        ('正文内容', 8, 320.0, 1.0, 40.0),
        ('　正文内容', 2, 320.0, 1.0, 0.0),
        ('正文内容', 2, 70.0, 2.0, 0.0),
      ]) {
        final block = paragraphs(
          '<p style="text-indent:${indent}em;clear:both">$body<span style="float:right;text-indent:0">-09:41</span></p>',
        ).single;
        final measured = flow(block, width, scale: scale);
        expect(measured.lines.first.pieces.first.rect.left, expected);
        expect(measured.end, block.text.runes.length);
        for (final line in measured.lines.skip(1)) {
          for (final piece in line.pieces.where((p) => !p.label)) {
            expect(piece.rect.left, 0);
          }
        }
      }
    },
  );
  testWidgets(
    'parsed trailing labels preserve ordinary first-line indent in layout and paint',
    (tester) async {
      for (final body in ['正文。', '普通正文😀é内容。' * 100]) {
        const css = 'text-indent:2em;clear:both';
        final block = paragraphs(
          '<p style="$css">$body<span style="float:right;text-indent:0">-09:41</span></p><p>${'后续正文' * 900}</p>',
        ).first;
        final plain = paragraphs(
          '<p style="$css">$body<span style="text-indent:0">-09:41</span></p>',
        ).single;
        expect(block.leadingIndent, 2);
        expect(block.hangingIndentEm, isNull);
        expect(block.trailingLabelStart, body.runes.length);
        expect(block.text, plain.text);
        expect(block.blockKey, plain.blockKey);
        for (final scale in [1.0, 2.0]) {
          for (final columns in [1, 2]) {
            const width = 320.0;
            final content = chapter(block);
            final layout = PageLayout(
              index: ChunkIndex(content),
              width: width,
              height: 170,
              style: style,
              scaler: TextScaler.linear(scale),
              direction: TextDirection.ltr,
              columns: columns,
            );
            var cursor = const PageCursor(0, 0);
            final fragments = <PageFragment>[];
            while (true) {
              final page = layout.forward(cursor);
              if (page == null) break;
              fragments.addAll(
                page.fragments.where(
                  (f) => layout.index.chunks[f.unit].blockIndex == 0,
                ),
              );
              cursor = page.end;
            }
            expect(fragments.map((f) => f.text).join(), block.text);
            var labels = 0;
            for (final fragment in fragments) {
              final sourceOffset =
                  layout.index.chunks[fragment.unit].start + fragment.start;
              for (final line in fragment.flow!.lines) {
                for (final piece in line.pieces) {
                  if (piece.label) {
                    labels++;
                    expect(piece.rect.right, closeTo(width, .01));
                  } else {
                    expect(
                      piece.rect.left,
                      sourceOffset + piece.start == 0 ? 40 * scale : 0,
                    );
                  }
                }
                if (line.pieces.length == 2) {
                  expect(
                    line.pieces.first.rect.overlaps(line.pieces.last.rect),
                    isFalse,
                  );
                }
              }
            }
            expect(labels, 1);
            for (final fragment in {fragments.first, fragments.last}) {
              final sourceOffset =
                  layout.index.chunks[fragment.unit].start + fragment.start;
              await tester.pumpWidget(
                MaterialApp(
                  home: Center(
                    child: SizedBox(
                      width: width,
                      child: ReaderLinkedText(
                        text: fragment.text!,
                        prefix: '',
                        blockOffset: sourceOffset,
                        links: const [],
                        style: style,
                        align: TextAlign.left,
                        scaler: TextScaler.linear(scale),
                        flow: fragment.flow,
                      ),
                    ),
                  ),
                ),
              );
              final root = tester.getRect(find.byType(ReaderLinkedText).first);
              final painted = tester
                  .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
                  .where((w) => w.flow == null)
                  .toList();
              final pieces = fragment.flow!.lines
                  .expand((l) => l.pieces)
                  .toList();
              expect(painted.length, pieces.length);
              for (var i = 0; i < pieces.length; i++) {
                final rect = tester.getRect(find.byWidget(painted[i]));
                expect(
                  rect.left - root.left,
                  closeTo(pieces[i].rect.left, .01),
                );
                expect(rect.top - root.top, closeTo(pieces[i].rect.top, .01));
                expect(painted[i].blockOffset, sourceOffset + pieces[i].start);
              }
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    },
  );
  testWidgets(
    'label moves to the next page and narrow labels wrap without loss',
    (tester) async {
      final block = ParagraphBlock(
        text: '${'正文' * 7}-09:41',
        hangingIndentEm: 7,
        trailingLabelStart: 14,
      );
      final content = chapter(block);
      final layout = PageLayout(
        index: ChunkIndex(content),
        width: 320,
        height: 46,
        style: style,
        scaler: TextScaler.noScaling,
        direction: TextDirection.ltr,
        paragraphSpacing: 16,
      );
      final first = layout.forward(const PageCursor(0, 0))!;
      expect(first.fragments.single.text, '正文' * 7);
      final second = layout.forward(first.end)!;
      expect(second.fragments.single.text, '-09:41');
      expect(
        second.fragments.single.flow!.lines.single.pieces.single.label,
        isTrue,
      );
      expect(
        second.fragments.single.flow!.lines.single.pieces.single.rect.right,
        320,
      );
      final narrow = ParagraphBlock(
        text: '甲😀é消息${'标签' * 12}',
        hangingIndentEm: 7,
        trailingLabelStart: 6,
      );
      final measured = flow(narrow, 80, scale: 2);
      expect(measured.lines.first.pieces.first.rect.left, 0);
      expect(
        measured.lines.where((l) => l.pieces.any((p) => p.label)).length,
        greaterThan(1),
      );
      expect(
        measured.lines
            .map(
              (l) => String.fromCharCodes(
                narrow.text.runes.skip(l.start).take(l.end - l.start),
              ),
            )
            .join(),
        narrow.text,
      );
      for (final line in measured.lines) {
        for (final p in line.pieces) {
          expect(p.rect.left, greaterThanOrEqualTo(0));
          expect(p.rect.right, lessThanOrEqualTo(80.01));
        }
      }
    },
  );
  testWidgets(
    'flow preserves clickable source ranges and clamps inline image paint',
    (tester) async {
      final block = ParagraphBlock(
        text: '甲正文\n\uFFFC链接-09:41',
        hangingIndentEm: 7,
        trailingLabelStart: 7,
        inlineImages: [
          InlineImage(
            offset: 4,
            media: MediaRef(sourceId: SourceId('local'), mediaId: 'icon'),
            widthEm: 8,
            heightEm: 1,
          ),
        ],
      );
      final key = chapter(block).key;
      final link = LocalContentLink(
        source: key,
        sourceBlockKey: block.blockKey,
        label: '链接',
        target: key,
        sourceOffset: 5,
        sourceLength: 2,
      );
      final measured = flow(block, 200, scale: 2);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              child: ReaderLinkedText(
                text: block.text,
                prefix: '',
                blockOffset: 0,
                links: [link],
                style: style,
                align: TextAlign.left,
                scaler: const TextScaler.linear(2),
                inlineImages: block.inlineImages,
                flow: measured,
                onLink: (_) => taps++,
              ),
            ),
          ),
        ),
      );
      final root = tester.getRect(find.byType(ReaderLinkedText).first);
      final p = measured.lines
          .expand((l) => l.pieces)
          .firstWhere((p) => p.start <= 5 && p.end > 5);
      await tester.tapAt(
        root.topLeft + Offset(p.rect.left + 5, p.rect.top + p.rect.height / 2),
      );
      expect(taps, 1);
      for (final render in tester.renderObjectList<RenderBox>(
        find.byType(RichText),
      )) {
        expect(render.size.width, lessThanOrEqualTo(200.01));
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'metadata-only update reflows; resize, columns and remount retain exact source',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final body = '甲　　${'正文😀é阅读恢复。' * 100}';
      final flat = chapter(ParagraphBlock(text: '$body-09:41'));
      final styled = chapter(
        ParagraphBlock(
          text: '$body-09:41',
          hangingIndentEm: 7,
          trailingLabelStart: body.runes.length,
        ),
      );
      expect(flat.contentRevision, styled.contentRevision);
      var controller = PagedReaderController();
      var restores = 0;
      Widget view(
        ChapterContent c,
        double width,
        int columns, {
        ReaderPosition? initial,
      }) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            height: 320,
            child: PagedReaderViewport(
              content: c,
              controller: controller,
              columns: columns,
              initialPosition: initial,
              onRestoreStart: () => restores++,
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(flat, 320, 1));
      await tester.pumpAndSettle();
      final initialRestores = restores;
      await tester.pumpWidget(view(styled, 320, 1));
      await tester.pumpAndSettle();
      expect(restores, greaterThan(initialRestores));
      expect(
        tester
            .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
            .any((w) => w.flow != null),
        isTrue,
      );
      for (final cp in [body.runes.length ~/ 2, body.runes.length + 2]) {
        final target = ReaderPosition(
          contentRevision: styled.contentRevision,
          blockKey: styled.blocks.first.blockKey,
          blockIndex: 0,
          blockFraction:
              cp / (styled.blocks.first as ParagraphBlock).text.runes.length,
          chapterFraction:
              cp /
              (styled.blocks.first as ParagraphBlock).text.runes.length /
              2,
        );
        controller.restore(target);
        await tester.pumpAndSettle();
        for (final (width, columns) in [(1072.0, 2), (390.0, 1)]) {
          await tester.pumpWidget(view(styled, width, columns));
          await tester.pumpAndSettle();
          expect(controller.capture()!.blockKey, target.blockKey);
          expect(controller.capture()!.blockFraction, target.blockFraction);
          expect(controller.usedFallback, isFalse);
        }
        final captured = controller.capture();
        await tester.pumpWidget(const SizedBox());
        controller = PagedReaderController();
        await tester.pumpWidget(view(styled, 320, 1, initial: captured));
        await tester.pumpAndSettle();
        expect(controller.capture()!.blockFraction, target.blockFraction);
        expect(controller.usedFallback, isFalse);
      }
    },
  );
  testWidgets('development viewport shares hanging paint and source mapping', (
    tester,
  ) async {
    final block = ParagraphBlock(
      text: '甲　　${'合成正文。' * 60}标签',
      hangingIndentEm: 3,
      trailingLabelStart: 303,
    );
    final content = chapter(block);
    final controller = ReaderViewportController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 300,
          child: ReaderViewport(content: content, controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
          .any((w) => w.flow != null),
      isTrue,
    );
    final target = ReaderPosition(
      contentRevision: content.contentRevision,
      blockKey: block.blockKey,
      blockIndex: 0,
      blockFraction: .5,
      chapterFraction: .25,
    );
    controller.restore(target);
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockKey, target.blockKey);
    expect(controller.capture()!.blockFraction, closeTo(.5, .1));
    expect(controller.usedFallback, isFalse);
  });
  testWidgets('first and continuation lines use shared bounded geometry', (
    tester,
  ) async {
    for (final width in [320.0, 390.0, 500.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final em in [3.0, 7.0]) {
          final block = ParagraphBlock(
            text: '甲同学　　${'这是一条合成消息。' * 30}-09:41',
            hangingIndentEm: em,
          );
          final layout = flow(block, width, scale: scale);
          final inset = (em * 20 * scale).clamp(0, width - 80 * scale);
          expect(layout.lines.first.pieces.first.rect.left, 0);
          expect(layout.lines.length, greaterThan(3));
          for (final line in layout.lines.skip(1)) {
            expect(line.pieces.first.rect.left, inset);
            expect(
              line.pieces.first.rect.right,
              lessThanOrEqualTo(width + .01),
            );
          }
          final resumed = flow(
            block,
            width,
            scale: scale,
            offset: layout.lines[1].start,
          );
          expect(resumed.lines.first.pieces.first.rect.left, inset);
          expect(
            layout.lines
                .map(
                  (l) => String.fromCharCodes(
                    block.text.runes.skip(l.start).take(l.end - l.start),
                  ),
                )
                .join(),
            block.text,
          );
        }
      }
    }
  });
  testWidgets('suffix shares a fitting row or owns a right-aligned later row', (
    tester,
  ) async {
    for (final body in ['短', '正文' * 7]) {
      final block = ParagraphBlock(
        text: '$body-09:41',
        hangingIndentEm: 3,
        trailingLabelStart: body.runes.length,
      );
      final layout = flow(block, 320);
      final label = layout.lines.last.pieces.last;
      expect(label.label, isTrue);
      expect(label.rect.right, closeTo(320, .01));
      expect(layout.lines.length, body == '短' ? 1 : 2);
      for (final line in layout.lines) {
        if (line.pieces.length == 2) {
          expect(
            line.pieces.first.rect.overlaps(line.pieces.last.rect),
            isFalse,
          );
        }
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              child: ReaderLinkedText(
                text: block.text,
                prefix: '',
                blockOffset: 0,
                links: const [],
                style: style,
                align: TextAlign.left,
                scaler: TextScaler.noScaling,
                flow: layout,
              ),
            ),
          ),
        ),
      );
      final rendered = tester.getRect(find.text('-09:41'));
      final parent = tester.getRect(find.byType(ReaderLinkedText).first);
      expect(rendered.right, closeTo(parent.right, .01));
      expect(rendered.top, closeTo(parent.top + label.rect.top, .01));
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'canonical cold reverse, columns, long chunks and source coverage',
    (tester) async {
      final body = '甲　　${'合成😀é消息测试。' * 240}';
      final block = ParagraphBlock(
        text: '$body-09:41',
        hangingIndentEm: 7,
        trailingLabelStart: body.runes.length,
      );
      final content = chapter(block);
      for (final columns in [1, 2]) {
        PageLayout make() => PageLayout(
          index: ChunkIndex(content),
          width: 320,
          height: 175,
          style: style,
          scaler: TextScaler.noScaling,
          direction: TextDirection.ltr,
          columns: columns,
          paragraphSpacing: 16,
        );
        final layout = make();
        final pages = <ReaderPage>[];
        var cursor = const PageCursor(0, 0);
        while (true) {
          final page = layout.forward(cursor);
          if (page == null) break;
          expect(
            page.end.unit > cursor.unit || page.end.offset > cursor.offset,
            isTrue,
          );
          pages.add(page);
          cursor = page.end;
          expect(pages.length, lessThan(500));
        }
        expect(
          pages.map((p) => p.fragments.map((f) => f.text ?? '').join()).join(),
          '${block.text}Next message',
        );
        var labels = 0;
        for (final page in pages) {
          for (final f in page.fragments) {
            final chunk = layout.index.chunks[f.unit];
            if (chunk.blockIndex != 0) continue;
            for (final line in f.flow!.lines) {
              labels += line.pieces.where((p) => p.label).length;
              for (final p in line.pieces.where((p) => !p.label)) {
                expect(
                  p.rect.left,
                  chunk.start + f.start + p.start == 0 ? 0 : 140,
                );
              }
            }
          }
        }
        expect(labels, 1);
        for (final i in [1, pages.length ~/ 2, pages.length - 1]) {
          final reverse = make().backward(pages[i].end)!;
          expect(reverse.start.unit, pages[i].start.unit);
          expect(reverse.start.offset, pages[i].start.offset);
          expect(
            reverse.fragments.map((f) => f.text),
            pages[i].fragments.map((f) => f.text),
          );
        }
      }
    },
  );
  testWidgets('rich source units and explicit breaks survive flow', (
    tester,
  ) async {
    final text = '甲😀é漢字\n${'后续正文' * 20}\uFFFC-09:41';
    final block = ParagraphBlock(
      text: text,
      hangingIndentEm: 7,
      trailingLabelStart: text.runes.length - 6,
      inlineRuby: [InlineRuby(start: 4, length: 2, annotation: 'かんじ')],
      inlineStyles: [
        InlineTextStyle(start: 0, length: 4, fontScale: 1.4, bold: true),
      ],
      inlineImages: [
        InlineImage(
          offset: text.runes.length - 7,
          media: MediaRef(sourceId: SourceId('local'), mediaId: 'icon'),
          widthEm: 1,
          heightEm: 1,
        ),
      ],
    );
    final layout = flow(block, 320);
    expect(layout.end, text.runes.length);
    expect(layout.lines.every((l) => l.height > 0), isTrue);
    expect(layout.lines.any((l) => l.end == 5), isFalse);
    for (final l in layout.lines) {
      expect(l.start == 2 || l.end == 2 || l.start == 3 || l.end == 3, isFalse);
    }
  });
}
