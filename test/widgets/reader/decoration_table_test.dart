import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_authored_colors.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/reader_box.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import '../../data/local/epub_decoration_table_test.dart'
    show decorationTable, parseDecoration;

const style = TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1.5);
ChapterContent content(String html) =>
    parseDecoration(html).content.chapters.first;

void main() {
  testWidgets(
    'column geometry shares CSS ratios and falls back at narrow widths',
    (tester) async {
      final chapter = content(decorationTable(leading: 20, trailing: 30));
      final block = chapter.blocks.single;
      final boxes = readerBlockBoxes(block, 320, style, TextScaler.noScaling);
      expect(boxes.outer, isNotNull);
      expect(
        boxes.local!.marginLeft,
        closeTo(boxes.outer!.contentWidth * .2, .01),
      );
      expect(
        boxes.local!.marginRight,
        closeTo(boxes.outer!.contentWidth * .3, .01),
      );
      expect(boxes.local!.width, closeTo(boxes.outer!.contentWidth * .5, .01));
      expect(boxes.innerWidth, closeTo(boxes.local!.width - 40, .01));
      for (final (width, scaler) in [
        (120.0, TextScaler.noScaling),
        (320.0, TextScaler.linear(3)),
      ]) {
        final fallback = readerBlockBoxes(block, width, style, scaler);
        expect(fallback.outer, isNull);
        expect(fallback.local!.marginLeft, 0);
        expect(fallback.local!.width, width);
        final edges = readerBoxEdges(
          chapter,
          0,
          width: width,
          style: style,
          scaler: scaler,
        );
        expect(edges.outerTop, 0);
        expect(edges.outerBottom, 0);
      }
    },
  );

  testWidgets(
    'two bottom arms leave the center open and only close the last slice',
    (tester) async {
      final block = content(
        decorationTable(leading: 20, trailing: 30),
      ).blocks.single;
      final g = readerBlockBoxes(
        block,
        320,
        style,
        TextScaler.noScaling,
      ).outer!;
      await tester.runAsync(() async {
        for (final dark in [false, true]) {
          for (final ends in [false, true]) {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            ReaderBoxPainter(
              block.box!,
              g,
              true,
              ends,
              ReaderAuthoredColors(dark ? ThemeData.dark() : ThemeData.light()),
            ).paint(canvas, const Size(320, 80));
            final picture = recorder.endRecording();
            final image = await picture.toImage(320, 80);
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            int alpha(int x, int y) => rgba.getUint8((y * 320 + x) * 4 + 3);
            expect(alpha(3, 40), 255);
            expect(alpha(317, 40), 255);
            expect(alpha(10, 78), ends ? 255 : 0);
            expect(alpha(260, 78), ends ? 255 : 0);
            expect(alpha(100, 78), 0);
            expect(alpha(160, 78), 0);
            image.dispose();
            picture.dispose();
          }
        }
      });
    },
  );

  testWidgets(
    'native pages preserve all text and slice edges while reflowing',
    (tester) async {
      final chapter = content(
        '${decorationTable(text: 'Native decoration text ' * 8)}<p>Tail</p>',
      );
      for (final (width, height, scaler) in [
        (320.0, 150.0, TextScaler.noScaling),
        (180.0, 100.0, TextScaler.linear(2)),
        (480.0, 240.0, TextScaler.noScaling),
      ]) {
        final layout = PageLayout(
          index: ChunkIndex(chapter),
          width: width,
          height: height,
          style: style,
          scaler: scaler,
          direction: TextDirection.ltr,
        );
        var cursor = const PageCursor(0, 0);
        final text = StringBuffer();
        final fragments = <PageFragment>[];
        for (var n = 0; n < 200; n++) {
          final page = layout.forward(cursor);
          if (page == null) break;
          expect(
            page.end.unit > cursor.unit || page.end.offset > cursor.offset,
            isTrue,
          );
          expect(
            page.fragments.fold<double>(0, (h, f) => h + f.height),
            lessThanOrEqualTo(height + .01),
          );
          for (final fragment in page.fragments) {
            text.write(fragment.text ?? '');
            if (layout.index.chunks[fragment.unit].blockIndex == 0) {
              fragments.add(fragment);
            }
          }
          cursor = page.end;
        }
        expect(
          text.toString(),
          chapter.blocks.map((b) => b.toJson()['text']).join(),
        );
        expect(cursor.unit, layout.index.chunks.length);
        expect(fragments, isNotEmpty);
        if (width == 320) {
          expect(fragments.length, greaterThan(1));
          expect(
            fragments.take(fragments.length - 1).every((f) => f.boxBottom == 0),
            isTrue,
          );
          expect(fragments.last.boxBottom, greaterThanOrEqualTo(6));
        }
      }
    },
  );

  testWidgets(
    'production viewport paints native decoration and preserves a link tap',
    (tester) async {
      final parsed = parseDecoration(
        '${decorationTable(text: '4<a href="#target">Go</a>')}<p id="target">Tail</p>',
      );
      final chapter = parsed.content.chapters.first;
      final controller = PagedReaderController();
      final boundary = GlobalKey();
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 200,
                child: RepaintBoundary(
                  key: boundary,
                  child: PagedReaderViewport(
                    content: chapter,
                    textStyle: style,
                    controller: controller,
                    contentLinks: parsed.content.links,
                    onLink: (_) {
                      taps++;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final frames = tester
          .widgetList<ReaderBoxFrame>(find.byType(ReaderBoxFrame))
          .where((f) => f.box?.decorationColumns != null)
          .toList();
      expect(frames, hasLength(1));
      expect(frames.single.ends, isTrue);
      final anchor = controller.capture()!;
      expect(anchor.blockKey, chapter.blocks.first.blockKey);
      final rich = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('4Go'),
      );
      final paragraph = tester.renderObject<RenderParagraph>(rich);
      final selection = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 1, extentOffset: 3),
          )
          .single;
      await tester.tapAt(paragraph.localToGlobal(selection.toRect().center));
      await tester.pumpAndSettle();
      expect(taps, 1);
      final screenshotDir =
          Platform.environment['SHIORI_DECORATION_SCREENSHOTS'];
      if (screenshotDir != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(screenshotDir).create(recursive: true);
          await File(
            '$screenshotDir/synthetic.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 120,
              height: 200,
              child: PagedReaderViewport(
                content: chapter,
                textStyle: style,
                controller: controller,
                initialPosition: anchor,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widgetList<ReaderBoxFrame>(find.byType(ReaderBoxFrame))
            .any((f) => f.box?.decorationColumns != null),
        isFalse,
      );
      expect(controller.capture()!.blockKey, anchor.blockKey);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 720,
              height: 200,
              child: PagedReaderViewport(
                content: chapter,
                textStyle: style,
                controller: controller,
                columns: 2,
                initialPosition: anchor,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.capture()!.blockKey, anchor.blockKey);
      final wideFrame = tester
          .widgetList<ReaderBoxFrame>(find.byType(ReaderBoxFrame))
          .firstWhere((f) => f.box?.decorationColumns != null);
      expect(wideFrame.geometry!.width, lessThan(360));
    },
  );
}
