import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/page_boundaries.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/reader_box.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import '../../data/local/epub_authored_layout_test.dart' show authoredContent;
import '../../data/local/epub_blank_border_test.dart' show blankBorderCss;
import 'media_decorations_test.dart' show pixels;

ChapterContent blankBorders() => authoredContent(
  '<div style="width:14em;margin:3em auto 0 auto">'
  '<p>Author One</p><p class="line"><br/></p><p>Profile one.</p>'
  '<p>Author Two</p><p class="line"><br/></p><p>Profile two.</p></div>',
  blankBorderCss,
).chapters.first;

void main() {
  testWidgets('parsed blank borders are painted within the outer width', (
    tester,
  ) async {
    final content = blankBorders();
    final controller = PagedReaderController();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 600,
            child: PagedReaderViewport(
              content: content,
              controller: controller,
              textStyle: const TextStyle(fontSize: 20, height: 1.6),
              turnStyle: PageTurnStyle.none,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final frames = tester
        .widgetList<ReaderBoxFrame>(find.byType(ReaderBoxFrame))
        .where((f) => f.box?.borders?.top?.width.value == 1)
        .toList();
    expect(frames.length, 2);
    for (final frame in frames) {
      expect(frame.geometry!.width, 280);
      expect(frame.top, 9);
      expect(frame.bottom, 0);
      expect(frame.starts, isTrue);
      expect(frame.ends, isTrue);
    }
    final paint = (await tester.runAsync(() => pixels(frames.first.box!)))!;
    expect(paint(50, 0).last, 255);
    expect(paint(50, 79).last, 0);
    expect(paint(0, 40).last, 0);
    expect(tester.takeException(), isNull);
  });

  test(
    'blank borders remain counted once across large-font and spread pagination',
    () {
      final content = blankBorders();
      for (final config in [(320.0, 140.0, 28.0, 1), (220.0, 180.0, 20.0, 2)]) {
        final layout = PageLayout(
          index: ChunkIndex(content),
          width: config.$1,
          height: config.$2,
          columns: config.$4,
          style: TextStyle(fontSize: config.$3, height: 1.6),
          scaler: TextScaler.noScaling,
          direction: TextDirection.ltr,
        );
        final boundaries = PageBoundaries(layout);
        final pages = <ReaderPage>[];
        var cursor = const PageCursor(0, 0), borders = 0;
        final text = StringBuffer();
        for (var n = 0; n < 30; n++) {
          final page = boundaries.forward(cursor);
          if (page == null) break;
          pages.add(page);
          expect(
            page.end.unit > cursor.unit ||
                page.end.unit == cursor.unit && page.end.offset > cursor.offset,
            isTrue,
          );
          for (final f in page.fragments) {
            text.write(f.text ?? '');
            final block =
                content.blocks[layout.index.chunks[f.unit].blockIndex];
            if (block is ParagraphBlock && block.text.isEmpty) {
              expect(block.layout!.borders!.top!.width.value, 1);
              expect(f.boxTop, greaterThanOrEqualTo(1));
              borders++;
            }
          }
          cursor = page.end;
        }
        expect(cursor.unit, layout.index.chunks.length);
        expect(borders, 2);
        expect(
          text.toString(),
          content.blocks.whereType<ParagraphBlock>().map((b) => b.text).join(),
        );
        for (final page in pages.reversed) {
          final previous = boundaries.backward(page.end)!;
          expect(PageBoundaries.compare(previous.start, page.start), 0);
          expect(PageBoundaries.compare(previous.end, page.end), 0);
          expect(
            previous.fragments.map(
              (f) => (f.unit, f.start, f.end, f.boxTop, f.boxBottom),
            ),
            page.fragments.map(
              (f) => (f.unit, f.start, f.end, f.boxTop, f.boxBottom),
            ),
          );
        }
      }
    },
  );
}
