import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

import 'viewport_test.dart' show at;

void main() {
  testWidgets('target image state survives turn commit and reverse turn', (
    tester,
  ) async {
    final controller = PagedReaderController();
    var mounts = 0;
    var disposals = 0;
    final content = ChapterContent(
      key: fixtureChapterKey(FixtureScenario.shortChapter),
      title: 'Image turn',
      blocks: [
        ParagraphBlock(text: 'Before the picture'),
        ImageBlock(media: fixtureMediaRef(0), width: 400, height: 900),
        ParagraphBlock(text: 'After the picture'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 600,
            child: PagedReaderViewport(
              content: content,
              controller: controller,
              imageHeights: {fixtureMediaRef(0): 580},
              imageBuilder: (_, _) => _ImageMountProbe(
                onMount: () => mounts++,
                onDispose: () => disposals++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(mounts, 0);
    final next = controller.next();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(mounts, 1);
    expect(disposals, 0);
    await tester.pumpAndSettle();
    await next;
    expect(controller.capture()!.blockIndex, 1);
    expect(mounts, 1);
    expect(disposals, 0);
    final previous = controller.previous();
    await tester.pumpAndSettle();
    await previous;
    expect(mounts, 1);
    expect(disposals, 1);
  });

  testWidgets('chapter-end entry survives delayed image size and rebuilds', (
    tester,
  ) async {
    final controller = PagedReaderController();
    final content = ChapterContent(
      key: fixtureChapterKey(FixtureScenario.shortChapter),
      title: 'Synthetic chapter ending with an illustration',
      blocks: [
        ParagraphBlock(text: 'Last paragraph before the illustration.'),
        ImageBlock(media: fixtureMediaRef(0)),
      ],
    );
    Widget view(double imageHeight) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 600,
          child: PagedReaderViewport(
            content: content,
            controller: controller,
            startAtEnd: true,
            imageHeights: {fixtureMediaRef(0): imageHeight},
            imageBuilder: (_, _) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpWidget(view(180));
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockIndex, 0);
    await tester.pumpWidget(view(426));
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockIndex, 1);
    await tester.pumpWidget(view(426));
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockIndex, 1);

    final turn = controller.previous();
    await tester.pumpAndSettle();
    await turn;
    expect(controller.capture()!.blockIndex, 0);
    await tester.pumpWidget(view(430));
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockIndex, 0);
  });

  testWidgets('heading moves with body and large illustration stays alone', (
    tester,
  ) async {
    final base = const FixtureData().content(FixtureScenario.shortChapter);
    ChapterContent content(List<ContentBlock> blocks) =>
        ChapterContent(key: base.key, title: 'pagination', blocks: blocks);
    PageLayout layout(ChapterContent c, {double height = 200}) => PageLayout(
      index: ChunkIndex(c),
      width: 300,
      height: height,
      style: const TextStyle(fontSize: 20, height: 1.5),
      scaler: TextScaler.noScaling,
      direction: TextDirection.ltr,
      paragraphSpacing: 20,
    );
    final headings = layout(
      content([
        ParagraphBlock(text: 'Before'),
        ParagraphBlock(text: 'Before two'),
        HeadingBlock(text: 'Chapter title', level: 1),
        ParagraphBlock(
          text:
              'Body follows this chapter title with enough text for several lines.',
        ),
      ]),
      height: 260,
    );
    final first = headings.forward(const PageCursor(0, 0))!;
    expect(first.end.unit, 2);
    final second = headings.forward(first.end)!;
    expect(second.fragments.first.unit, 2);
    expect(second.fragments.last.unit, 3);
    final media = const FixtureData()
        .content(FixtureScenario.twentyImages)
        .blocks
        .whereType<ImageBlock>()
        .first;
    final illustrations = layout(
      content([
        ParagraphBlock(text: 'Before'),
        media,
        ParagraphBlock(text: 'After'),
      ]),
    );
    final before = illustrations.forward(const PageCursor(0, 0))!;
    final picture = illustrations.forward(before.end)!;
    expect(picture.fragments, hasLength(1));
    expect(picture.fragments.single.unit, 1);
    final back = illustrations.backward(picture.end)!;
    expect(back.fragments, hasLength(1));
    expect(back.fragments.single.unit, 1);
  });

  testWidgets('entering previous chapter lays out its final page', (
    tester,
  ) async {
    final c = PagedReaderController();
    final base = const FixtureData().content(FixtureScenario.shortChapter);
    final content = ChapterContent(
      key: base.key,
      title: 'long',
      blocks: [
        for (var i = 0; i < 100; i++) ParagraphBlock(text: 'Paragraph $i'),
      ],
    );
    final turns = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 400,
            child: PagedReaderViewport(
              content: content,
              controller: c,
              startAtEnd: true,
              onBoundary: turns.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.capture()!.blockIndex, greaterThan(85));
    await c.next();
    expect(turns, [1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single-page boundaries respond to tap and swipe once', (
    tester,
  ) async {
    final c = PagedReaderController();
    final base = const FixtureData().content(FixtureScenario.shortChapter);
    final content = ChapterContent(
      key: base.key,
      title: 'single',
      blocks: [ParagraphBlock(text: 'Only page')],
    );
    final turns = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 500,
            child: PagedReaderViewport(
              content: content,
              controller: c,
              onBoundary: turns.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(turns, isEmpty);
    await c.next();
    expect(turns, [1]);
    await c.previous();
    expect(turns, [1, -1]);
    final area = find.byType(PagedReaderViewport);
    await tester.drag(area, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(turns, [1, -1, 1]);
    await tester.drag(area, const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(turns, [1, -1, 1, -1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'paged image reflow and large text keep anchor and source semantics',
    (tester) async {
      final handle = tester.ensureSemantics();
      final base = const FixtureData().content(
        FixtureScenario.unknownImageSize,
      );
      final media = (base.blocks.single as ImageBlock).media;
      final content = ChapterContent(
        key: base.key,
        title: 'Mixed',
        blocks: [
          base.blocks.single,
          for (var i = 0; i < 30; i++)
            ParagraphBlock(text: 'P${i.toString().padLeft(3, '0')}\n汉字かな😀。'),
        ],
      );
      final controller = PagedReaderController();
      Widget app(double height, double font) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 400,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: PagedReaderViewport(
                content: content,
                controller: controller,
                textStyle: TextStyle(fontSize: font, height: 1.7),
                imageHeights: {media: height},
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(100, 20));
      await tester.pumpAndSettle();
      final anchor = controller.capture()!;
      await tester.pumpWidget(app(700, 32));
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockKey, anchor.blockKey);
      final advance = controller.next();
      await tester.pumpAndSettle();
      await advance;
      final ids = <int>[];
      void visit(SemanticsNode node) {
        for (final match in RegExp(
          r'P(\d{3})',
        ).allMatches(node.getSemanticsData().label)) {
          ids.add(int.parse(match[1]!));
        }
        for (final child in node.debugListChildrenInOrder(
          DebugSemanticsDumpOrder.traversalOrder,
        )) {
          visit(child);
        }
      }

      visit(
        tester.getSemantics(find.byKey(const ValueKey('paper-reader-pages'))),
      );
      expect(ids, isNotEmpty);
      expect(ids, orderedEquals(ids.toList()..sort()));
      expect(tester.takeException(), isNull);
      handle.dispose();
    },
  );
  testWidgets(
    'local pages cover every Unicode character exactly once in both directions',
    (tester) async {
      final text = List.filled(90, '汉字かなe\u0301😀，测试。').join();
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.typography),
        title: 'Pages',
        blocks: [ParagraphBlock(text: text, leadingIndent: 2)],
      );
      final engine = PageLayout(
        index: ChunkIndex(content, maxCodePoints: 80),
        width: 300,
        height: 360,
        style: const TextStyle(fontSize: 20, height: 1.7),
        scaler: TextScaler.noScaling,
        direction: TextDirection.ltr,
      );
      var cursor = const PageCursor(0, 0);
      final parts = <String>[];
      var count = 0;
      while (true) {
        final page = engine.forward(cursor);
        if (page == null) break;
        parts.addAll(page.fragments.map((f) => f.text ?? ''));
        cursor = page.end;
        expect(++count, lessThan(100));
      }
      expect(parts.join(), text);
      final reverse = <String>[];
      while (true) {
        final page = engine.backward(cursor);
        if (page == null) break;
        reverse.insert(0, page.fragments.map((f) => f.text ?? '').join());
        cursor = page.start;
        expect(++count, lessThan(200));
      }
      expect(reverse.join(), text);
    },
  );
  testWidgets('horizontal pivot opens deep page lazily and swipes both ways', (
    tester,
  ) async {
    final content = const FixtureData().content(FixtureScenario.longChapter);
    final controller = PagedReaderController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedReaderViewport(
            content: content,
            controller: controller,
            initialPosition: at(content, 1499),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockIndex, 1499);
    expect(controller.measuredChunks, lessThan(50));
    final previous = controller.previous();
    await tester.pumpAndSettle();
    await previous;
    expect(controller.capture()!.blockIndex, lessThan(1499));
    final next = controller.next();
    await tester.pumpAndSettle();
    await next;
    expect(controller.capture()!.blockIndex, 1499);
    await tester.drag(
      find.byKey(const ValueKey('paper-reader-pages')),
      const Offset(-700, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockIndex, greaterThan(1499));
    await tester.drag(
      find.byKey(const ValueKey('paper-reader-pages')),
      const Offset(700, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockIndex, 1499);
    controller.restore(at(content, 1999));
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockIndex, 1999);
    await tester.drag(
      find.byKey(const ValueKey('paper-reader-pages')),
      const Offset(-700, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockIndex, 1999);
    expect(controller.cachedPages, lessThanOrEqualTo(7));
    controller.restore(at(content, 1999, 1));
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockIndex, 1999);
    expect(find.byType(Text), findsWidgets);
    controller.restore(at(content, 0));
    await tester.pumpAndSettle();
    final noPrevious = controller.previous();
    await tester.pumpAndSettle();
    await noPrevious;
    expect(controller.capture()!.blockIndex, 0);
    final rect = tester.getRect(
      find.byKey(const ValueKey('paper-reader-pages')),
    );
    await tester.tapAt(Offset(rect.right - 10, rect.center.dy));
    await tester.pumpAndSettle();
    expect(controller.capture()!.blockIndex, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'paged long-paragraph anchor survives width, font, scale and chunk changes',
    (tester) async {
      final content = const FixtureData().content(
        FixtureScenario.extremeParagraph,
      );
      final controller = PagedReaderController();
      Widget app(double width, double font, int chunk, double scale) =>
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: width,
                height: 500,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: PagedReaderViewport(
                    content: content,
                    controller: controller,
                    initialPosition: at(content, 0, .753),
                    maxChunkCodePoints: chunk,
                    textStyle: TextStyle(fontSize: font, height: 1.7),
                  ),
                ),
              ),
            ),
          );
      await tester.pumpWidget(app(360, 20, 800, 1));
      await tester.pumpAndSettle();
      final anchor = controller.capture()!;
      expect(anchor.blockFraction, closeTo(.753, .00001));
      await tester.pumpWidget(app(600, 28, 256, 1.5));
      await tester.pumpAndSettle();
      expect(
        controller.capture()!.blockFraction,
        closeTo(anchor.blockFraction, .00001),
      );
      expect(controller.measuredChunks, lessThan(12));
      expect(tester.takeException(), isNull);
    },
  );
}

class _ImageMountProbe extends StatefulWidget {
  const _ImageMountProbe({required this.onMount, required this.onDispose});
  final VoidCallback onMount;
  final VoidCallback onDispose;
  @override
  State<_ImageMountProbe> createState() => _ImageMountProbeState();
}

class _ImageMountProbeState extends State<_ImageMountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.blue);
}
