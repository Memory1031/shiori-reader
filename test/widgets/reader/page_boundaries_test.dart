import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

const style = TextStyle(
  inherit: false,
  fontFamily: 'Ahem',
  fontSize: 20,
  height: 1,
);
ChapterContent chapter(bool headings, {int count = 52}) => ChapterContent(
  key: fixtureChapterKey(FixtureScenario.shortChapter),
  title: 'Canonical',
  blocks: [
    for (var i = 0; i < count; i++) ...[
      if (headings && i % 9 == 0) HeadingBlock(text: 'Heading $i', level: 1),
      ParagraphBlock(text: 'Line $i'),
    ],
  ],
);
PageLayout layout(ChapterContent content, {double height = 200}) => PageLayout(
  index: ChunkIndex(content),
  width: 300,
  height: height,
  style: style,
  scaler: TextScaler.noScaling,
  direction: TextDirection.ltr,
  paragraphSpacing: 0,
);
List<ReaderPage> canonical(PageLayout layout) {
  final result = <ReaderPage>[];
  var cursor = const PageCursor(0, 0);
  while (true) {
    final page = layout.forward(cursor);
    if (page == null) return result;
    result.add(page);
    cursor = page.end;
  }
}

Widget view(
  ChapterContent content,
  PagedReaderController controller, {
  bool end = false,
  ReaderPosition? initial,
  double height = 200,
  void Function(ReaderPosition, bool)? onPosition,
}) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 300,
      height: height,
      child: PagedReaderViewport(
        content: content,
        controller: controller,
        startAtEnd: end,
        initialPosition: initial,
        textStyle: style,
        paragraphSpacing: 0,
        onPosition: onPosition,
      ),
    ),
  ),
);
String visible(WidgetTester tester) => tester
    .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
    .map((w) => w.text)
    .join('|');
String expected(ReaderPage page) =>
    page.fragments.where((f) => f.text != '').map((f) => f.text).join('|');
Future<void> turn(
  WidgetTester tester,
  PagedReaderController c,
  bool next,
) async {
  final future = next ? c.next() : c.previous();
  await tester.pumpAndSettle();
  await future;
}

void main() {
  testWidgets(
    'seek inside text after a full-page image uses canonical containing page',
    (tester) async {
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.shortChapter),
        title: 'Seek',
        blocks: [
          ...chapter(false, count: 35).blocks,
          ImageBlock(media: fixtureMediaRef(0), width: 300, height: 400),
          ParagraphBlock(text: 'Dialogue before request.'),
          ParagraphBlock(
            text: 'Here is the request followed by more prose. ' * 4,
          ),
          ...chapter(false, count: 20).blocks,
        ],
      );
      final l = layout(content);
      final pages = canonical(l);
      final target = l.position(const PageCursor(37, 5));
      final expectedIndex = pages.indexWhere(
        (p) =>
            p.fragments.any((f) => f.unit == 37 && f.start <= 5 && f.end > 5),
      );
      expect(expectedIndex, greaterThan(0));
      final c = PagedReaderController();
      await tester.pumpWidget(view(content, c));
      await tester.pumpAndSettle();
      c.restore(target);
      await tester.pumpAndSettle();
      expect(visible(tester), expected(pages[expectedIndex]));
      for (var i = expectedIndex - 1; i >= 0; i--) {
        await turn(tester, c, false);
        expect(c.capture(), l.position(pages[i].start));
      }
      final measured = c.measuredChunks;
      c.restore(target);
      await tester.pumpAndSettle();
      expect(visible(tester), expected(pages[expectedIndex]));
      expect(c.measuredChunks - measured, lessThan(10));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(view(content, c, initial: target));
      await tester.pumpAndSettle();
      expect(visible(tester), expected(pages[expectedIndex]));
    },
  );
  testWidgets('normal entry stays lazy and a later seek cancels pending seek', (
    tester,
  ) async {
    final content = chapter(false, count: 503);
    final l = layout(content);
    final c = PagedReaderController();
    await tester.pumpWidget(view(content, c));
    await tester.pumpAndSettle();
    expect(c.measuredChunks, lessThan(50));
    c.restore(l.position(const PageCursor(490, 2)));
    await tester.pump();
    expect(c.isRestoring, isTrue);
    c.restore(l.position(const PageCursor(21, 2)));
    await tester.pumpAndSettle();
    final page = canonical(
      l,
    ).firstWhere((p) => p.fragments.any((f) => f.unit == 21));
    expect(visible(tester), expected(page));
  });
  for (final headings in [false, true]) {
    testWidgets(
      'end entry and every reverse page equal forward chain (headings=$headings)',
      (tester) async {
        final content = chapter(headings);
        final l = layout(content);
        final pages = canonical(l);
        if (!headings) expect(pages.last.fragments, hasLength(2));
        final c = PagedReaderController();
        await tester.pumpWidget(view(content, c, end: true));
        await tester.pumpAndSettle();
        for (var i = pages.length - 1; i >= 0; i--) {
          expect(visible(tester), expected(pages[i]));
          expect(c.capture(), l.position(pages[i].start));
          expect(c.cachedPages, lessThanOrEqualTo(7));
          if (i > 0) await turn(tester, c, false);
        }
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'evicted pages and parent rebuild retain forward boundaries (headings=$headings)',
      (tester) async {
        final content = chapter(headings, count: 140);
        final pages = canonical(layout(content));
        expect(pages.length, greaterThan(7));
        final c = PagedReaderController();
        await tester.pumpWidget(view(content, c));
        await tester.pumpAndSettle();
        for (var i = 0; i < pages.length; i++) {
          expect(visible(tester), expected(pages[i]));
          if (i < pages.length - 1) await turn(tester, c, true);
        }
        final measured = c.measuredChunks;
        await tester.pumpWidget(view(content, c));
        await tester.pumpAndSettle();
        expect(c.measuredChunks, measured);
        for (var i = pages.length - 1; i >= 0; i--) {
          expect(visible(tester), expected(pages[i]));
          expect(c.cachedPages, lessThanOrEqualTo(7));
          if (i > 0) await turn(tester, c, false);
        }
      },
    );
  }
  testWidgets(
    'end seek yields, cancels on relayout and publishes only the final page',
    (tester) async {
      final content = chapter(false, count: 503);
      final c = PagedReaderController();
      final samples = <ReaderPosition>[];
      await tester.pumpWidget(
        view(content, c, end: true, onPosition: (p, _) => samples.add(p)),
      );
      expect(c.isRestoring, isTrue);
      expect(samples, isEmpty);
      expect(find.byType(ReaderLinkedText), findsNothing);
      expect(c.measuredChunks, lessThan(503));
      await tester.pumpWidget(
        view(
          content,
          c,
          end: true,
          height: 240,
          onPosition: (p, _) => samples.add(p),
        ),
      );
      await tester.pumpAndSettle();
      final l = layout(content, height: 240);
      expect(visible(tester), expected(canonical(l).last));
      expect(samples, [l.position(canonical(l).last.start)]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(view(content, c, end: true));
      expect(c.isRestoring, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
