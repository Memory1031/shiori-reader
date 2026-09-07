import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/reader_viewport.dart';

ReaderPosition at(ChapterContent content, int block, [double fraction = 0]) =>
    ReaderPosition(
      contentRevision: content.contentRevision,
      blockKey: content.blocks[block].blockKey,
      blockIndex: block,
      blockFraction: fraction,
      chapterFraction: ReaderPosition.fractionFor(
        blockIndex: block,
        blockFraction: fraction,
        blockCount: content.blocks.length,
      ),
    );

void main() {
  testWidgets(
    'unknown image height settles around the same fractional anchor',
    (tester) async {
      final heights = ValueNotifier<double>(180);
      addTearDown(heights.dispose);
      final content = const FixtureData().content(
        FixtureScenario.unknownImageSize,
      );
      final controller = ReaderViewportController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderViewport(
              content: content,
              controller: controller,
              initialPosition: at(content, 0, .5),
              imageBuilder: (_, image) => ValueListenableBuilder<double>(
                valueListenable: heights,
                builder: (_, height, child) => SizedBox(
                  height: height,
                  child: const ColoredBox(color: Colors.pink),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockFraction, closeTo(.5, .01));
      heights.value = 700;
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockFraction, closeTo(.5, .01));
      expect(controller.blockTop(0), closeTo(-350, 1));
      final gesture = await tester.startGesture(const Offset(300, 200));
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      heights.value = 850;
      await tester.pump();
      expect(controller.isRestoring, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'visible semantic labels keep source order across reverse and forward slivers',
    (tester) async {
      final handle = tester.ensureSemantics();

      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.shortChapter),
        title: 'Semantics',
        blocks: [
          for (var i = 0; i < 2000; i++)
            ParagraphBlock(text: 'P${i.toString().padLeft(4, '0')}'),
        ],
      );
      final controller = ReaderViewportController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderViewport(
              content: content,
              controller: controller,
              initialPosition: at(content, 1499),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 150));
      await tester.pumpAndSettle();
      final ids = <int>[];
      void visit(SemanticsNode node) {
        for (final match in RegExp(
          r'P(\d{4})',
        ).allMatches(node.getSemanticsData().label)) {
          ids.add(int.parse(match[1]!));
        }
        for (final child in node.debugListChildrenInOrder(
          DebugSemanticsDumpOrder.traversalOrder,
        )) {
          visit(child);
        }
      }

      visit(tester.getSemantics(find.byType(CustomScrollView)));
      expect(ids.length, greaterThan(2));
      expect(ids, orderedEquals(ids.toList()..sort()));
      expect(ids.toSet().length, ids.length);
      handle.dispose();
    },
  );
  testWidgets(
    'native pivot enters blocks 1500 and 2000 without laying out prefix',
    (tester) async {
      final content = const FixtureData().content(FixtureScenario.longChapter);
      final controller = ReaderViewportController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderViewport(
              content: content,
              controller: controller,
              initialPosition: at(content, 1499),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockIndex, 1499);
      expect(controller.mountedCount, lessThan(25));
      expect(controller.buildCount, lessThan(40));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockIndex, lessThan(1499));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockIndex, greaterThan(1499));
      controller.restore(at(content, 1999));
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockIndex, 1999);
      expect(controller.blockTop(1999)!.abs(), lessThanOrEqualTo(34));
      controller.restore(at(content, 0));
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockIndex, 0);
    },
  );

  testWidgets(
    'same layout stays within one line, rechunk resize and scale preserve long paragraph',
    (tester) async {
      final content = const FixtureData().content(
        FixtureScenario.extremeParagraph,
      );
      final controller = ReaderViewportController();
      Widget app(double width, double font, int chunk, double scale) =>
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: 500,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: ReaderViewport(
                      content: content,
                      controller: controller,
                      initialPosition: at(content, 0, .753),
                      maxChunkCodePoints: chunk,
                      textStyle: TextStyle(fontSize: font, height: 1.7),
                    ),
                  ),
                ),
              ),
            ),
          );
      await tester.pumpWidget(app(360, 20, 800, 1));
      await tester.pumpAndSettle();
      final before = controller.capture()!;
      expect(before.blockFraction, closeTo(.753, .0005));
      controller.restore(before);
      await tester.pumpAndSettle();
      double actualLineError(ReaderPosition anchor, int chunkSize) {
        final chunks = ChunkIndex(content, maxCodePoints: chunkSize);
        final unit = chunks.resolve(anchor).chunk;
        final chunk = chunks.chunks[unit];
        final cp = (anchor.blockFraction * chunk.total).floor() - chunk.start;
        final utf16 = String.fromCharCodes(chunk.text!.runes.take(cp)).length;
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byKey(ValueKey('reader-text-$unit')),
            matching: find.byType(RichText),
          ),
        );
        final caret = paragraph.getOffsetForCaret(
          TextPosition(offset: utf16),
          Rect.zero,
        );
        final y =
            paragraph.localToGlobal(caret).dy -
            tester.getTopLeft(find.byType(ReaderViewport)).dy;
        return y.abs();
      }

      expect(actualLineError(before, 800), lessThanOrEqualTo(34));
      expect(
        controller.capture()!.blockFraction,
        closeTo(before.blockFraction, .0003),
      );
      await tester.pumpWidget(app(600, 28, 256, 1.5));
      await tester.pumpAndSettle();
      expect(actualLineError(before, 256), lessThanOrEqualTo(500));
      expect(controller.capture()!.blockIndex, 0);
      expect(
        controller.capture()!.blockFraction,
        closeTo(before.blockFraction, .003),
      );
      expect(controller.mountedCount, lessThan(20));
      expect(tester.takeException(), isNull);
    },
  );
}
