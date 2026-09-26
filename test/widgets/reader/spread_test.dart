import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/page_boundaries.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import 'settings_test.dart' show Store;

const style = TextStyle(fontSize: 20, height: 1.6);
ChapterContent chapter(List<ContentBlock> blocks) => ChapterContent(
  key: fixtureChapterKey(FixtureScenario.longChapter),
  title: 'Spread',
  blocks: blocks,
);
String textOf(ReaderPage page) =>
    page.fragments.map((f) => f.text ?? '').join();

void main() {
  testWidgets(
    'cover and centered title pages keep one capped page on wide screens',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final block in <ContentBlock>[
        ImageBlock(media: fixtureMediaRef(0), width: 600, height: 900),
        ParagraphBlock(text: 'Title', alignment: ParagraphAlignment.center),
      ]) {
        final store = Store()..value = ReaderSettings(controlsHintSeen: true);
        await tester.pumpWidget(
          ShioriApp(
            routes: AppRoutes(
              home: (_) =>
                  ReaderContentView(content: chapter([block]), settings: store),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
              .columns,
          1,
        );
        final rect = tester.getRect(find.byType(PagedReaderViewport));
        expect(rect.width, 680);
        expect(rect.center.dx, 900);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'chapter-end entry and reverse turns keep the final spread boundary',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final content = chapter([
        ParagraphBlock(text: 'Reading text. ' * 800 + 'THE_END'),
      ]);
      final controller = PagedReaderController();
      var boundary = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PagedReaderViewport(
            content: content,
            controller: controller,
            columns: 2,
            textStyle: style,
            startAtEnd: true,
            onBoundary: (value) => boundary += value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      String visible() => tester
          .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
          .map((w) => w.text)
          .join();
      final last = visible();
      expect(last, endsWith('THE_END'));
      final previous = controller.previous();
      await tester.pumpAndSettle();
      await previous;
      expect(visible(), isNot(contains('THE_END')));
      final next = controller.next();
      await tester.pumpAndSettle();
      await next;
      expect(visible(), last);
      await controller.next();
      expect(boundary, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test('a spread consumes consecutive columns including illustrations', () {
    final content = chapter([
      ParagraphBlock(text: 'Before image. ' * 90),
      ImageBlock(media: fixtureMediaRef(0), width: 300, height: 500),
      ParagraphBlock(text: 'After image. ' * 90),
    ]);
    PageLayout layout(int columns) => PageLayout(
      index: ChunkIndex(content),
      width: 300,
      height: 300,
      style: style,
      scaler: TextScaler.noScaling,
      direction: TextDirection.ltr,
      columns: columns,
    );
    final single = layout(1);
    final spreads = PageBoundaries(layout(2));
    var cursor = const PageCursor(0, 0);
    final pages = <ReaderPage>[];
    while (true) {
      final page = spreads.forward(cursor);
      if (page == null) break;
      pages.add(page);
      final left = single.forward(cursor)!;
      if (page.fullWidth) {
        expect(page.fragments, hasLength(1));
        expect(page.fragments.single.text, isNull);
        expect(page.columnBreak, isNull);
      } else if (page.columnBreak != null) {
        final right = single.forward(left.end)!;
        expect(textOf(page), textOf(left) + textOf(right));
        expect(page.columnBreak, left.fragments.length);
      } else {
        expect(textOf(page), textOf(left));
      }
      cursor = page.end;
      expect(pages.length, lessThan(100));
    }
    expect(pages.where((p) => p.fullWidth), isEmpty);
    expect(
      pages.map(textOf).join(),
      'Before image. ' * 90 + 'After image. ' * 90,
    );
    for (final original in pages.reversed) {
      final previous = spreads.backward(cursor)!;
      expect(textOf(previous), textOf(original));
      expect(previous.columnBreak, original.columnBreak);
      expect(previous.fullWidth, original.fullWidth);
      cursor = previous.start;
    }
    expect(spreads.backward(cursor), isNull);
  });

  testWidgets(
    'wide reader shows two capped columns, turns spreads and preserves resize anchor',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final content = chapter([
        ParagraphBlock(
          text: List.generate(800, (i) => 'Paragraph $i reading text. ').join(),
        ),
      ]);
      final store = Store()..value = ReaderSettings(controlsHintSeen: true);
      await tester.pumpWidget(
        ShioriApp(
          routes: AppRoutes(
            home: (_) => ReaderContentView(content: content, settings: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      PagedReaderViewport viewport() =>
          tester.widget(find.byType(PagedReaderViewport));
      expect(viewport().columns, 2);
      final outer = tester.getRect(find.byType(PagedReaderViewport));
      expect(outer.width, 1432);
      final gutter = tester.getRect(
        find.byKey(const ValueKey('reader-spread-gutter')),
      );
      expect(gutter.width, 72);
      expect(gutter.center.dx, outer.center.dx);
      final texts = find.byType(ReaderLinkedText);
      expect(texts, findsWidgets);
      final left = <ReaderLinkedText>[], right = <ReaderLinkedText>[];
      for (final element in texts.evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.width, lessThanOrEqualTo(680));
        (rect.center.dx < outer.center.dx ? left : right).add(
          element.widget as ReaderLinkedText,
        );
      }
      expect(left, isNotEmpty);
      expect(right, isNotEmpty);
      final visible = [...left, ...right].map((w) => w.text).join();
      expect(
        (content.blocks.single as ParagraphBlock).text.startsWith(visible),
        isTrue,
      );
      final controller = viewport().controller;
      final next = controller.next();
      await tester.pumpAndSettle();
      await next;
      final anchor = controller.capture()!;
      expect(anchor.blockFraction, greaterThan(0));
      expect(
        tester
            .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
            .first
            .blockOffset,
        visible.runes.length,
      );
      tester.view.physicalSize = const Size(800, 900);
      await tester.pumpAndSettle();
      expect(viewport().columns, 1);
      expect(find.byKey(const ValueKey('reader-spread-gutter')), findsNothing);
      expect(tester.getSize(find.byType(PagedReaderViewport)).width, 680);
      expect(controller.capture()!.blockFraction, anchor.blockFraction);
      tester.view.physicalSize = const Size(1800, 900);
      await tester.pumpAndSettle();
      expect(viewport().columns, 2);
      expect(controller.capture()!.blockFraction, anchor.blockFraction);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an illustration shares a spread with following prose', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1408, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final content = chapter([
      ImageBlock(media: fixtureMediaRef(0), width: 300, height: 500),
      ParagraphBlock(text: 'After image. ' * 300),
    ]);
    final controller = PagedReaderController();
    await tester.pumpWidget(
      MaterialApp(
        home: PagedReaderViewport(
          content: content,
          controller: controller,
          columns: 2,
          textStyle: style,
          imageBuilder: (_, _) => const ColoredBox(
            key: ValueKey('illustration'),
            color: Colors.blue,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const ValueKey('illustration')));
    expect(rect.width, 668);
    expect(rect.center.dx, 334);
    expect(find.byType(ReaderLinkedText), findsWidgets);
    expect(find.byKey(const ValueKey('reader-spread-gutter')), findsOneWidget);
    final next = controller.next();
    await tester.pumpAndSettle();
    await next;
    expect(find.byKey(const ValueKey('illustration')), findsNothing);
    expect(find.byType(ReaderLinkedText), findsWidgets);
    final previous = controller.previous();
    await tester.pumpAndSettle();
    await previous;
    expect(find.byKey(const ValueKey('illustration')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('object-replacement-only paragraphs do not count as prose', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // U+FFFC marks inline objects; a paragraph holding only markers is not
    // flowing text, so a wide window must stay on single pages.
    final content = chapter([
      for (var i = 0; i < 20; i++) ParagraphBlock(text: '\uFFFC \uFFFC'),
    ]);
    final store = Store()..value = ReaderSettings(controlsHintSeen: true);
    await tester.pumpWidget(
      ShioriApp(
        routes: AppRoutes(
          home: (_) => ReaderContentView(content: content, settings: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
          .columns,
      1,
    );
  });
}
