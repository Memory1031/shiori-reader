import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/paragraph_flow.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import '../../data/local/epub_prose_semantics_test.dart' show paragraphs;
import '../../data/local/epub_table_test.dart' show tableHtml;
import 'paragraph_flow_test.dart' show style, chapter;

ChapterContent tableContent() {
  final blocks = paragraphs(
    tableHtml('''
<tr><td>Gate</td><td>第一行😀é正文</td></tr>
<tr class="gap"><td></td><td></td></tr>
<tr><td>Wide</td><td>${'长段正文😀é以及换行测试。' * 220}</td></tr>
<tr><td>End</td><td>最后一行</td></tr>
'''),
  );
  return ChapterContent(
    key: chapter(blocks.first).key,
    title: 'Table',
    blocks: [
      ParagraphBlock(text: 'Before'),
      ...blocks,
      ParagraphBlock(text: 'After'),
    ],
  );
}

void main() {
  testWidgets('boxed table gap cannot block a fresh page or following prose', (
    tester,
  ) async {
    for (final prefix in ['', '<p>Before</p>']) {
      for (final labelScale in [1, 2]) {
        final blocks = paragraphs(
          '$prefix<div style="background-color:white;padding:8px">${tableHtml('<tr><td><span style="font-size:${labelScale}em">A</span></td><td>短记录</td></tr>'
          '<tr style="height:4em"><td></td><td></td></tr>')}</div><p>After</p>',
        );
        final row = blocks.firstWhere((b) => b.tableRow != null);
        expect(row.box!.padding, 8);
        final content = ChapterContent(
          key: chapter(row).key,
          title: 'Boxed gap',
          blocks: blocks,
        );
        final layout = PageLayout(
          index: ChunkIndex(content),
          width: 320,
          height: 100,
          style: style,
          scaler: TextScaler.noScaling,
          direction: TextDirection.ltr,
        );
        var cursor = const PageCursor(0, 0);
        final joined = StringBuffer();
        var tableFragments = 0;
        for (var n = 0; n < 20; n++) {
          final page = layout.forward(cursor);
          if (page == null) break;
          expect(
            page.end.unit > cursor.unit || page.end.offset > cursor.offset,
            isTrue,
          );
          expect(
            page.fragments.fold<double>(0, (h, f) => h + f.height),
            lessThanOrEqualTo(100.01),
          );
          for (final fragment in page.fragments) {
            joined.write(fragment.text ?? '');
            if (fragment.flow == null) continue;
            tableFragments++;
            expect(fragment.boxTop, 8);
            expect(fragment.boxBottom, 8);
            expect(fragment.flow!.height, lessThanOrEqualTo(84.01));
          }
          cursor = page.end;
        }
        expect(tableFragments, 1);
        expect(joined.toString(), blocks.map((b) => b.text).join());
        expect(joined.toString(), endsWith('After'));
        expect(cursor.unit, layout.index.chunks.length);
      }
    }
  });

  testWidgets(
    'tall left label does not change right cell rhythm or overflow a page',
    (tester) async {
      final block = paragraphs(
        tableHtml(
          '<tr><td><span style="font-size:2em">A</span></td><td>${'右列连续正文测试。' * 12}</td></tr>',
        ),
      ).single;
      final flow = readerParagraphFlow(
        block: block,
        text: block.text,
        offset: 0,
        width: 320,
        style: style,
        scaler: TextScaler.noScaling,
      );
      final label = flow.lines.first.pieces.first;
      final right = flow.lines
          .expand((l) => l.pieces)
          .where((p) => p.rect.left > 0)
          .toList();
      expect(right.length, greaterThanOrEqualTo(3));
      expect(label.rect.height, greaterThan(right.first.rect.height));
      for (var i = 1; i < right.length; i++) {
        expect(right[i].rect.top, closeTo(right[i - 1].rect.bottom, .01));
      }
      expect(flow.height, closeTo(right.last.rect.bottom, .01));
      expect(flow.take(1).height, closeTo(label.rect.height, .01));
      expect(flow.take(2).height, closeTo(label.rect.height, .01));

      final content = chapter(block);
      final layout = PageLayout(
        index: ChunkIndex(content),
        width: 320,
        height: 75,
        style: style,
        scaler: TextScaler.noScaling,
        direction: TextDirection.ltr,
      );
      var cursor = const PageCursor(0, 0);
      var labelCount = 0;
      final joined = StringBuffer();
      for (var n = 0; n < 100; n++) {
        final page = layout.forward(cursor);
        if (page == null) break;
        expect(
          page.end.unit > cursor.unit || page.end.offset > cursor.offset,
          isTrue,
        );
        for (final fragment in page.fragments) {
          if (layout.index.chunks[fragment.unit].blockIndex != 0) continue;
          joined.write(fragment.text);
          final part = fragment.flow!;
          final pieces = part.lines.expand((l) => l.pieces).toList();
          expect(part.height, lessThanOrEqualTo(75.01));
          for (final piece in pieces) {
            if (piece.rect.left == 0) labelCount++;
            expect(piece.rect.bottom, lessThanOrEqualTo(part.height + .01));
          }
          if (labelCount == 1 && pieces.first.rect.left == 0) {
            expect(part.lines.length, 2);
          }
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 320,
                  child: ReaderLinkedText(
                    text: fragment.text!,
                    prefix: '',
                    blockOffset:
                        layout.index.chunks[fragment.unit].start +
                        fragment.start,
                    links: const [],
                    style: style,
                    align: TextAlign.left,
                    scaler: TextScaler.noScaling,
                    inlineStyles: block.inlineStyles,
                    flow: part,
                  ),
                ),
              ),
            ),
          );
          final parent = tester.getRect(find.byType(ReaderLinkedText).first);
          final leaves = tester
              .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
              .where((w) => w.flow == null)
              .toList();
          expect(leaves.length, pieces.length);
          for (var i = 0; i < leaves.length; i++) {
            final rect = tester.getRect(find.byWidget(leaves[i]));
            expect(rect.top - parent.top, closeTo(pieces[i].rect.top, .01));
            expect(rect.height, closeTo(pieces[i].rect.height, .01));
          }
        }
        cursor = page.end;
      }
      expect(labelCount, 1);
      expect(joined.toString(), block.text);
    },
  );

  testWidgets('short viewport gaps and tiny internal chunks always progress', (
    tester,
  ) async {
    final blocks = paragraphs(
      tableHtml(
        '<tr><td>A😀</td><td>正文</td></tr><tr style="height:4em"><td></td><td></td></tr><tr><td>Wide</td><td>尾行</td></tr>',
      ),
    );
    final content = ChapterContent(
      key: chapter(blocks.first).key,
      title: 'Gaps',
      blocks: blocks,
    );
    for (final width in [80.0, 320.0]) {
      final layout = PageLayout(
        index: ChunkIndex(content, maxCodePoints: 16),
        width: width,
        height: 40,
        style: style,
        scaler: TextScaler.noScaling,
        direction: TextDirection.ltr,
      );
      var cursor = const PageCursor(0, 0);
      var joined = '';
      for (var n = 0; n < 100; n++) {
        final page = layout.forward(cursor);
        if (page == null) break;
        joined += page.fragments.map((f) => f.text ?? '').join();
        if (width == 80) {
          expect(page.fragments.every((f) => f.flow == null), isTrue);
        }
        expect(
          page.fragments.fold<double>(0, (h, f) => h + f.height),
          lessThanOrEqualTo(40.01),
        );
        cursor = page.end;
      }
      expect(joined, blocks.map((b) => b.text).join());
    }
  });

  testWidgets(
    'parser through pagination and actual paint: stable columns, gaps, source coverage, reverse',
    (tester) async {
      final content = tableContent();
      expect((content.blocks[1] as ParagraphBlock).tableRow, isNotNull);
      for (final width in [320.0, 390.0, 500.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final columns in [1, 2]) {
            final layout = PageLayout(
              index: ChunkIndex(content, maxCodePoints: 256),
              width: width,
              height: 240,
              style: style,
              scaler: TextScaler.linear(scale),
              direction: TextDirection.ltr,
              columns: columns,
              paragraphSpacing: 20,
            );
            var cursor = const PageCursor(0, 0);
            final pages = <ReaderPage>[];
            final joined = <int, String>{};
            double? axis;
            var labels = 0;
            for (var n = 0; n < 1000; n++) {
              final page = layout.forward(cursor);
              if (page == null) break;
              expect(
                page.end.unit > cursor.unit || page.end.offset > cursor.offset,
                isTrue,
              );
              pages.add(page);
              for (final f in page.fragments) {
                final c = layout.index.chunks[f.unit];
                joined[c.blockIndex] =
                    (joined[c.blockIndex] ?? '') + (f.text ?? '');
                final flow = f.flow;
                if (flow == null) continue;
                axis ??= flow.dividerX!;
                expect(flow.dividerX, closeTo(axis, .001));
                expect(f.height, closeTo(flow.height, .001));
                for (final line in flow.lines) {
                  for (final piece in line.pieces) {
                    if (piece.rect.left == 0) {
                      labels++;
                      expect(c.start + f.start + piece.start, 0);
                      expect(
                        piece.rect.right,
                        lessThanOrEqualTo(flow.dividerX!),
                      );
                    } else {
                      expect(
                        piece.rect.left,
                        closeTo(axis + 2 + 10 * scale, .001),
                      );
                      expect(piece.rect.right, lessThanOrEqualTo(width + .01));
                    }
                  }
                }
              }
              cursor = page.end;
            }
            expect(pages.length, lessThan(1000));
            expect(labels, 3);
            for (var i = 0; i < content.blocks.length; i++) {
              expect(joined[i], (content.blocks[i] as ParagraphBlock).text);
            }
            final cold = PageLayout(
              index: layout.index,
              width: width,
              height: 240,
              style: style,
              scaler: TextScaler.linear(scale),
              direction: TextDirection.ltr,
              columns: columns,
              paragraphSpacing: 20,
            );
            for (final p in [pages[1], pages.last]) {
              final reverse = cold.backward(p.end)!;
              expect(
                (reverse.start.unit, reverse.start.offset),
                (p.start.unit, p.start.offset),
              );
            }
            final fragment = pages.first.fragments.firstWhere(
              (f) => f.flow != null,
            );
            final b =
                content.blocks[layout.index.chunks[fragment.unit].blockIndex];
            for (final brightness in [Brightness.light, Brightness.dark]) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: ThemeData(brightness: brightness),
                  home: Center(
                    child: SizedBox(
                      width: width,
                      child: ReaderLinkedText(
                        text: fragment.text!,
                        prefix: '',
                        blockOffset: 0,
                        links: const [],
                        style: style,
                        align: TextAlign.left,
                        scaler: TextScaler.linear(scale),
                        flow: fragment.flow,
                        inlineStyles: b.inlineStyles,
                      ),
                    ),
                  ),
                ),
              );
              final parent = tester.getRect(
                find.byType(ReaderLinkedText).first,
              );
              final children = tester
                  .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
                  .where((w) => w.flow == null)
                  .toList();
              final pieces = fragment.flow!.lines
                  .expand((l) => l.pieces)
                  .toList();
              expect(children.length, pieces.length);
              for (var i = 0; i < children.length; i++) {
                final rect = tester.getRect(find.byWidget(children[i]));
                expect(
                  rect.left - parent.left,
                  closeTo(pieces[i].rect.left, .01),
                );
                expect(rect.top - parent.top, closeTo(pieces[i].rect.top, .01));
              }
              final dividers = tester
                  .widgetList<Positioned>(find.byType(Positioned))
                  .where((w) => w.width == 2)
                  .toList();
              expect(dividers.length, 1);
              expect(dividers.single.height, fragment.flow!.height);
            }
          }
        }
      }
    },
  );
  testWidgets('resize and remount make actual target source piece visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final content = tableContent();
    final block = content.blocks[2] as ParagraphBlock;
    var controller = PagedReaderController();
    Widget view(
      double width,
      int columns,
      double scale,
      ReaderPosition initial,
    ) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: width,
          height: 360,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: PagedReaderViewport(
              content: content,
              controller: controller,
              initialPosition: initial,
              columns: columns,
              textStyle: style,
            ),
          ),
        ),
      ),
    );
    for (final cp in [
      1,
      block.tableRow!.rightStart + 2,
      block.text.runes.length ~/ 2,
    ]) {
      final target = ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: block.blockKey,
        blockIndex: 2,
        blockFraction: cp / block.text.runes.length,
        chapterFraction:
            (2 + cp / block.text.runes.length) / content.blocks.length,
      );
      void expectTargetVisible(double width, double scale) {
        expect(controller.usedFallback, isFalse);
        final leaf = tester
            .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
            .where(
              (w) =>
                  w.flow == null &&
                  w.blockOffset <= cp &&
                  w.blockOffset + w.text.runes.length > cp &&
                  String.fromCharCodes(
                        block.text.runes
                            .skip(w.blockOffset)
                            .take(w.text.runes.length),
                      ) ==
                      w.text,
            )
            .toList();
        expect(
          leaf,
          isNotEmpty,
          reason: 'target $cp at width=$width scale=$scale',
        );
        final viewport = tester.getRect(find.byType(PagedReaderViewport));
        expect(
          leaf.any((w) => viewport.overlaps(tester.getRect(find.byWidget(w)))),
          isTrue,
        );
        expect(controller.capture()!.blockKey, target.blockKey);
      }

      await tester.pumpWidget(const SizedBox());
      controller = PagedReaderController();
      await tester.pumpWidget(view(320, 1, 1, target));
      await tester.pumpAndSettle();
      controller.restore(target);
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(PagedReaderViewport));
      expectTargetVisible(320, 1);
      for (final (width, columns, scale) in [
        (1072.0, 2, 1.0),
        (390.0, 1, 2.0),
        (320.0, 1, 1.0),
      ]) {
        await tester.pumpWidget(view(width, columns, scale, target));
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(PagedReaderViewport)), same(state));
        expectTargetVisible(width, scale);
      }

      final saved = controller.capture()!;
      await tester.pumpWidget(const SizedBox());
      controller = PagedReaderController();
      await tester.pumpWidget(view(1072, 2, 1, saved));
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(PagedReaderViewport)),
        isNot(same(state)),
      );
      expectTargetVisible(1072, 1);
    }
  });
}
