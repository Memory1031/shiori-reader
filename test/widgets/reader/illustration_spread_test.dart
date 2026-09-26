import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/page_boundaries.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

import 'settings_test.dart' show Store;

const style = TextStyle(
  inherit: false,
  fontFamily: 'Ahem',
  fontSize: 20,
  height: 1,
);
ChapterContent chapter(List<ContentBlock> blocks) => ChapterContent(
  key: fixtureChapterKey(FixtureScenario.longChapter),
  title: 'Illustrations',
  blocks: blocks,
);
ImageBlock illustration(int n) =>
    ImageBlock(media: fixtureMediaRef(n), width: 500, height: 400);
PageLayout layout(ChapterContent content, {int columns = 2}) => PageLayout(
  index: ChunkIndex(content),
  width: 500,
  height: 600,
  style: style,
  scaler: TextScaler.noScaling,
  direction: TextDirection.ltr,
  paragraphSpacing: 0,
  columns: columns,
);
List<ReaderPage> pages(PageLayout layout) {
  final result = <ReaderPage>[];
  var cursor = const PageCursor(0, 0);
  while (true) {
    final page = layout.forward(cursor);
    if (page == null) return result;
    result.add(page);
    cursor = page.end;
  }
}

Object identity(ReaderPage p) => [
  (p.start.unit, p.start.offset),
  (p.end.unit, p.end.offset),
  p.columnBreak,
  p.fullWidth,
  p.centered,
  for (final f in p.fragments)
    (f.unit, f.start, f.end, f.text, f.height, f.boxTop, f.boxBottom),
];
List<List<int>> columnsOf(ReaderPage p) => [
  p.fragments
      .take(p.columnBreak ?? p.fragments.length)
      .map((f) => f.unit)
      .toList(),
  p.columnBreak == null
      ? []
      : p.fragments.skip(p.columnBreak!).map((f) => f.unit).toList(),
];
String visibleText(WidgetTester tester) => tester
    .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
    .map((w) => w.text)
    .join();
Widget view(
  ChapterContent content,
  PagedReaderController controller, {
  double width = 1072,
  int columns = 2,
  ReaderPosition? initial,
  bool end = false,
  TextDirection direction = TextDirection.ltr,
  Map<MediaRef, double> heights = const {},
}) => MaterialApp(
  home: Directionality(
    textDirection: direction,
    child: Center(
      child: SizedBox(
        width: width,
        height: 600,
        child: PagedReaderViewport(
          content: content,
          controller: controller,
          columns: columns,
          initialPosition: initial,
          startAtEnd: end,
          textStyle: style,
          paragraphSpacing: 0,
          imageHeights: heights,
          imageBuilder: (_, image) =>
              SizedBox.expand(key: ValueKey(image.media)),
        ),
      ),
    ),
  ),
);
Future<void> turn(
  WidgetTester tester,
  PagedReaderController controller,
  bool next,
) async {
  final pending = next ? controller.next() : controller.previous();
  await tester.pumpAndSettle();
  await pending;
}

void main() {
  final a = ParagraphBlock(text: 'Text A');
  final b = ParagraphBlock(text: 'Text B');
  final scenarios = <String, (List<ContentBlock>, List<List<List<int>>>)>{
    'text/image/text': (
      [a, illustration(0), b],
      [
        [
          [0],
          [1],
        ],
        [
          [2],
          [],
        ],
      ],
    ),
    'image/text': (
      [illustration(0), a],
      [
        [
          [0],
          [1],
        ],
      ],
    ),
    'text/image': (
      [a, illustration(0)],
      [
        [
          [0],
          [1],
        ],
      ],
    ),
    'image/image/text': (
      [illustration(0), illustration(1), a],
      [
        [
          [0],
          [1],
        ],
        [
          [2],
          [],
        ],
      ],
    ),
    'final image/blank': (
      [a, illustration(0), illustration(1)],
      [
        [
          [0],
          [1],
        ],
        [
          [2],
          [],
        ],
      ],
    ),
  };
  for (final entry in scenarios.entries) {
    test('column pairing: ${entry.key}', () {
      final l = layout(chapter(entry.value.$1));
      final spreads = pages(l);
      expect(spreads.map(columnsOf).toList(), entry.value.$2);
      expect(spreads.every((p) => !p.fullWidth), isTrue);
      for (final p in spreads) {
        if (p.columnBreak != null) expect(p.centered, isFalse);
      }
    });
  }
  test('image-only remains full width; small images still mix with prose', () {
    final only = layout(
      chapter([illustration(0)]),
    ).forward(const PageCursor(0, 0))!;
    expect(only.fullWidth, isTrue);
    expect(only.centered, isTrue);
    final small = chapter([
      a,
      ImageBlock(media: fixtureMediaRef(0), width: 500, height: 100),
      b,
    ]);
    expect(columnsOf(pages(layout(small)).single), [
      [0, 1, 2],
      [],
    ]);
    final single = pages(layout(chapter([a, illustration(0), b]), columns: 1));
    expect(single.map((p) => p.fragments.map((f) => f.unit).toList()), [
      [0],
      [1],
      [2],
    ]);
    expect(single[1].centered, isTrue);
  });

  for (final trailingImage in [false, true]) {
    test(
      'cold backward equals forward, including every fragment ($trailingImage)',
      () {
        final content = chapter([
          ParagraphBlock(text: 'A numbered reading line. ' * 73),
          illustration(0),
          ParagraphBlock(text: 'B different line lengths. ' * 91),
          illustration(1),
          illustration(2),
          HeadingBlock(text: 'Heading', level: 2),
          ParagraphBlock(text: 'C last prose. ' * 79),
          if (trailingImage) illustration(3),
        ]);
        final forward = pages(layout(content));
        // Neither instance has ever received a forward call. Also make a fresh
        // layout for each end cursor to exclude any hidden warm-cache dependency.
        final coldBoundaries = PageBoundaries(layout(content));
        for (final original in forward.reversed) {
          expect(
            identity(layout(content).backward(original.end)!),
            identity(original),
          );
          expect(
            identity(coldBoundaries.backward(original.end)!),
            identity(original),
          );
        }
        expect(coldBoundaries.backward(const PageCursor(0, 0)), isNull);
      },
    );
  }

  for (final direction in TextDirection.values) {
    for (final order in ['text/image', 'image/text', 'image/image']) {
      testWidgets('$order centers only image columns ($direction)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1500, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final content = chapter([
          order.startsWith('text') ? a : illustration(0),
          order.endsWith('text') ? b : illustration(1),
        ]);
        await tester.pumpWidget(
          view(content, PagedReaderController(), direction: direction),
        );
        await tester.pumpAndSettle();
        final outer = tester.getRect(find.byType(PagedReaderViewport));
        final gutter = tester.getRect(
          find.byKey(const ValueKey('reader-spread-gutter')),
        );
        expect(gutter.width, 72);
        for (var i = 0; i < content.blocks.length; i++) {
          final block = content.blocks[i];
          if (block is! ImageBlock) continue;
          final image = tester.getRect(find.byKey(ValueKey(block.media)));
          expect(image.width, 500);
          expect(image.height, 400);
          expect(image.center.dy, outer.center.dy);
          expect(
            image.center.dx,
            i == 0 ? outer.left + 250 : outer.right - 250,
          );
          expect(
            i == 0 ? image.right <= gutter.left : image.left >= gutter.right,
            isTrue,
          );
        }
        for (final e in find.byType(ReaderLinkedText).evaluate()) {
          expect(
            tester.getTopLeft(find.byWidget(e.widget)).dy,
            closeTo(outer.top, 1),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'final illustration occupies the left column and does not cross chapter',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = PagedReaderController();
      final content = chapter([a, illustration(0), illustration(1)]);
      await tester.pumpWidget(view(content, c, end: true));
      await tester.pumpAndSettle();
      final outer = tester.getRect(find.byType(PagedReaderViewport));
      final last = tester.getRect(find.byKey(ValueKey(fixtureMediaRef(1))));
      expect(last.center, Offset(outer.left + 250, outer.center.dy));
      expect(find.byKey(ValueKey(fixtureMediaRef(0))), findsNothing);
      expect(c.capture()!.blockIndex, 2);
      await turn(tester, c, false);
      expect(visibleText(tester), 'Text A');
      expect(find.byKey(ValueKey(fixtureMediaRef(0))), findsOneWidget);
      await turn(tester, c, true);
      expect(c.capture()!.blockIndex, 2);
    },
  );

  for (final imageFirst in [false, true]) {
    testWidgets(
      'mixed spread keeps semantic anchor through resize and remount ($imageFirst)',
      (tester) async {
        tester.view.physicalSize = const Size(1500, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final content = chapter([
          if (!imageFirst) a,
          illustration(0),
          ParagraphBlock(text: 'Following text. ' * 150),
        ]);
        final c = PagedReaderController();
        // Restoring directly to the image covers a right-column anchor too.
        final anchor = layout(
          content,
        ).position(PageCursor(imageFirst ? 0 : 1, 0));
        await tester.pumpWidget(view(content, c, initial: anchor));
        await tester.pumpAndSettle();
        final original = visibleText(tester);
        expect(c.capture(), anchor);
        expect(find.byKey(ValueKey(fixtureMediaRef(0))), findsOneWidget);
        await tester.pumpWidget(view(content, c, width: 500, columns: 1));
        await tester.pumpAndSettle();
        expect(c.capture(), anchor);
        expect(visibleText(tester), isEmpty);
        await tester.pumpWidget(view(content, c));
        await tester.pumpAndSettle();
        expect(c.capture(), anchor);
        expect(visibleText(tester), original);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(view(content, c, initial: anchor));
        await tester.pumpAndSettle();
        expect(c.capture(), anchor);
        expect(visibleText(tester), original);
        await turn(tester, c, true);
        final following = visibleText(tester);
        expect(following, isNotEmpty);
        await turn(tester, c, false);
        expect(visibleText(tester), original);
        expect(find.byKey(ValueKey(fixtureMediaRef(0))), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'ReaderContentView keeps a deep image anchor through automatic column changes',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final content = chapter([
        ParagraphBlock(text: 'Prose before illustration. ' * 220),
        illustration(0),
        ParagraphBlock(text: 'Prose after illustration. ' * 160),
      ]);
      final c = PagedReaderController();
      final store = Store()..value = ReaderSettings(controlsHintSeen: true);
      Widget reader([ReaderPosition? initial]) => ShioriApp(
        routes: AppRoutes(
          home: (_) => ReaderContentView(
            content: content,
            settings: store,
            viewportController: c,
            initialPosition: initial,
          ),
        ),
      );
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();
      final anchor = ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks[1].blockKey,
        blockIndex: 1,
        blockFraction: 0,
        chapterFraction: 1 / 3,
      );
      c.restore(anchor);
      await tester.pumpAndSettle();
      final original = visibleText(tester);
      expect(c.capture(), anchor);
      PagedReaderViewport viewport() =>
          tester.widget(find.byType(PagedReaderViewport));
      expect(viewport().columns, 2);
      tester.view.physicalSize = const Size(800, 800);
      await tester.pumpAndSettle();
      expect(viewport().columns, 1);
      expect(c.capture(), anchor);
      expect(visibleText(tester), isEmpty);
      tester.view.physicalSize = const Size(1600, 800);
      await tester.pumpAndSettle();
      expect(viewport().columns, 2);
      expect(c.capture(), anchor);
      expect(visibleText(tester), original);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(reader(anchor));
      await tester.pumpAndSettle();
      expect(c.capture(), anchor);
      expect(visibleText(tester), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'target illustration dimensions apply only after the active turn',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = PagedReaderController();
      final content = chapter([illustration(0), a, illustration(1), b]);
      await tester.pumpWidget(view(content, c));
      await tester.pumpAndSettle();
      final initial = c.capture();
      final next = c.next();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester.getSize(find.byKey(ValueKey(fixtureMediaRef(1)))).height,
        400,
      );
      await tester.pumpWidget(
        view(content, c, heights: {fixtureMediaRef(1): 510}),
      );
      expect(
        tester.getSize(find.byKey(ValueKey(fixtureMediaRef(1)))).height,
        400,
      );
      expect(c.capture(), initial);
      expect(c.isRestoring, isFalse);
      await tester.pumpAndSettle();
      await next;
      expect(
        tester.getSize(find.byKey(ValueKey(fixtureMediaRef(1)))).height,
        510,
      );
      expect(c.capture()!.blockIndex, 2);
      expect(visibleText(tester), 'Text B');
      await turn(tester, c, false);
      expect(c.capture(), initial);
      expect(visibleText(tester), 'Text A');
      await turn(tester, c, true);
      expect(visibleText(tester), 'Text B');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real narrow spread does not use 680px for the standalone threshold',
    (tester) async {
      tester.view.physicalSize = const Size(1132, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final image = ImageBlock(
        media: fixtureMediaRef(0),
        width: 1000,
        height: 700,
      );
      final content = chapter([a, image, b]);
      final store = Store()
        ..value = ReaderSettings(horizontalPadding: 30, controlsHintSeen: true);
      await tester.pumpWidget(
        ShioriApp(
          routes: AppRoutes(
            home: (_) => ReaderContentView(content: content, settings: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      final bounds = tester.getRect(find.byType(PagedReaderViewport));
      expect(viewport.columns, 2);
      expect((bounds.width - 72) / 2, 500);
      expect(viewport.imageExtent!(image), lessThan(bounds.height * .6));
      expect(680 * .7, greaterThan(bounds.height * .6));
      // At the real width this image fits between the two short paragraphs in
      // the LEFT column. A 680px extent incorrectly isolates it on the right.
      expect(find.byType(ReaderLinkedText), findsNWidgets(2));
      for (final e in find.byType(ReaderLinkedText).evaluate()) {
        expect(
          tester.getCenter(find.byWidget(e.widget)).dx,
          lessThan(bounds.center.dx),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1132.0, 1600.0]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'real Reader measures image and caption at column width ($width/$direction)',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final env = FixtureEnvironment();
          env.source.controls.delays[Operation.media] = const Duration(days: 1);
          final repo = MemoryImageRepository(resolve: (_) => env.source);
          final image = ImageBlock(
            media: fixtureMediaRef(0),
            width: 1000,
            height: 800,
            caption: 'W' * 40,
          );
          final content = chapter([
            image,
            ParagraphBlock(text: 'Readable prose. ' * 100),
          ]);
          final store = Store()
            ..value = ReaderSettings(
              horizontalPadding: 30,
              controlsHintSeen: true,
            );
          await tester.pumpWidget(
            ShioriApp(
              routes: AppRoutes(
                home: (_) => Directionality(
                  textDirection: direction,
                  child: ReaderContentView(
                    content: content,
                    settings: store,
                    images: repo,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          final viewport = tester.widget<PagedReaderViewport>(
            find.byType(PagedReaderViewport),
          );
          expect(viewport.columns, 2);
          final bounds = tester.getRect(find.byType(PagedReaderViewport));
          final columnWidth = (bounds.width - 72) / 2;
          expect(columnWidth, width == 1132 ? 500 : 680);
          final expected = readerImageExtent(
            image,
            width: columnWidth,
            maxHeight: bounds.height,
            scaler: TextScaler.noScaling,
            direction: direction,
          );
          final imageWidget = tester.widget<ReaderImage>(
            find.byType(ReaderImage),
          );
          final rect = tester.getRect(find.byType(ReaderImage));
          expect(viewport.imageExtent!(image), expected.height);
          expect(imageWidget.captionHeight, expected.caption);
          expect(rect.width, columnWidth);
          expect(rect.height, expected.height);
          expect(rect.center.dy, bounds.center.dy);
          if (columnWidth == 500) {
            final wrong = readerImageExtent(
              image,
              width: 680,
              maxHeight: bounds.height,
              scaler: TextScaler.noScaling,
              direction: direction,
            );
            expect(expected.height, isNot(wrong.height));
            expect(expected.caption, greaterThan(wrong.caption));
          }
          expect(find.text(image.caption!), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          expect(repo.pendingCount, 0);
          expect(repo.retainedBytes, 0);
          repo.close();
          await env.close();
        },
      );
    }
  }
}
