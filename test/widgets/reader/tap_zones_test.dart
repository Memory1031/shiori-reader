import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_tap_zones.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

void main() {
  test('outer thirds turn pages and the middle toggles chrome', () {
    expect(readerTapZone(20, 300), ReaderTap.previous);
    expect(readerTapZone(150, 300), ReaderTap.center);
    expect(readerTapZone(280, 300), ReaderTap.next);
    expect(readerTapZone(280, 300, chromeVisible: true), ReaderTap.center);
  });

  testWidgets('side taps dismiss visible chrome instead of turning', (
    tester,
  ) async {
    final controller = PagedReaderController();
    final chrome = ValueNotifier(true);
    addTearDown(chrome.dispose);
    var centerTaps = 0;
    final content = ChapterContent(
      key: fixtureChapterKey(FixtureScenario.shortChapter),
      title: 'Taps',
      blocks: [
        for (var i = 0; i < 40; i++)
          ParagraphBlock(text: 'Paragraph $i with enough words to wrap.'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: PagedReaderViewport(
              content: content,
              controller: controller,
              chromeVisible: chrome,
              onCenterTap: () {
                centerTaps++;
                chrome.value = !chrome.value;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final start = controller.capture();
    final right =
        tester.getTopLeft(find.byType(PagedReaderViewport)) +
        const Offset(290, 200);
    await tester.tapAt(right);
    await tester.pumpAndSettle();
    expect(centerTaps, 1);
    expect(controller.capture(), start);
    await tester.tapAt(right);
    await tester.pumpAndSettle();
    expect(centerTaps, 1);
    expect(controller.capture(), isNot(start));
  });
}
