import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/page_turn.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

ChapterContent _chapter() => ChapterContent(
  key: fixtureChapterKey(FixtureScenario.longChapter),
  title: 'Turns',
  blocks: [
    for (var i = 0; i < 60; i++)
      ParagraphBlock(text: 'Paragraph $i with enough words to wrap twice.'),
  ],
);

Future<PagedReaderController> _pump(
  WidgetTester tester,
  PageTurnStyle style,
) async {
  final controller = PagedReaderController();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 400,
          child: PagedReaderViewport(
            content: _chapter(),
            controller: controller,
            turnStyle: style,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// Horizontal offsets of the page slots mid-turn, leaving page first.
List<double> _slotOffsets(WidgetTester tester) => tester
    .widgetList<PageTurnSlot>(find.byType(PageTurnSlot))
    .map((slot) => slot.frame.offset(slot.role, 300))
    .toList();

void main() {
  test('settings from before page-turn styles keep the curl', () {
    final json = ReaderSettings(fontSize: 22).toJson()
      ..['schemaVersion'] = 3
      ..remove('pageTurn');
    final migrated = ReaderSettings.fromJson(json);
    expect(migrated.pageTurn, PageTurnStyle.curl);
    expect(migrated.fontSize, 22);
    final cover = ReaderSettings(pageTurn: PageTurnStyle.cover);
    expect(ReaderSettings.fromJson(cover.toJson()), cover);
  });

  test('cover and slide place pages per direction', () {
    PageTurnFrame frame(PageTurnStyle style, int direction) =>
        PageTurnFrame(style: style, progress: .25, direction: direction);
    const w = 400.0;
    // Forward cover: the next page enters on top from the right edge.
    final forward = frame(PageTurnStyle.cover, 1);
    expect(forward.enteringOnTop, isTrue);
    expect(forward.offset(PageTurnRole.entering, w), 300);
    expect(forward.offset(PageTurnRole.leaving, w), 0);
    // Backward cover: the current page slides off, revealing the previous.
    final back = frame(PageTurnStyle.cover, -1);
    expect(back.enteringOnTop, isFalse);
    expect(back.offset(PageTurnRole.leaving, w), 100);
    expect(back.offset(PageTurnRole.entering, w), 0);
    // Slide: both pages move together.
    final slide = frame(PageTurnStyle.slide, 1);
    expect(slide.offset(PageTurnRole.leaving, w), -100);
    expect(slide.offset(PageTurnRole.entering, w), 300);
    expect(
      frame(PageTurnStyle.slide, -1).offset(PageTurnRole.entering, w),
      -300,
    );
  });

  for (final style in [PageTurnStyle.cover, PageTurnStyle.slide]) {
    testWidgets('$style moves live pages mid-turn and commits', (tester) async {
      final controller = await _pump(tester, style);
      final start = controller.capture();
      final next = controller.next();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final offsets = _slotOffsets(tester);
      expect(offsets, hasLength(2));
      expect(offsets.any((dx) => dx != 0), isTrue);
      await tester.pumpAndSettle();
      await next;
      expect(controller.capture(), isNot(start));
      expect(find.byType(PageTurnSlot), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no-animation style turns in a single frame', (tester) async {
    final controller = await _pump(tester, PageTurnStyle.none);
    final start = controller.capture();
    final next = controller.next();
    await tester.pump();
    await tester.pump();
    await next;
    expect(controller.capture(), isNot(start));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
