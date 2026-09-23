import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

void main() {
  testWidgets('a short image-only cover centers on its page', (tester) async {
    final content = ChapterContent(
      key: fixtureChapterKey(FixtureScenario.singleImage),
      title: 'Cover',
      blocks: [ImageBlock(media: fixtureMediaRef(0), width: 300, height: 180)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 600,
              child: PagedReaderViewport(
                content: content,
                controller: PagedReaderController(),
                imageBuilder: (_, _) =>
                    const SizedBox.expand(key: ValueKey('cover-image')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final page = tester.getRect(find.byType(PagedReaderViewport));
    final image = tester.getRect(find.byKey(const ValueKey('cover-image')));
    expect(image.height, lessThan(page.height * .6));
    expect(image.top - page.top, closeTo(page.bottom - image.bottom, .5));
  });

  testWidgets('standalone image pages center vertically, text pages do not', (
    tester,
  ) async {
    final content = ChapterContent(
      key: fixtureChapterKey(FixtureScenario.singleImage),
      title: 'Centered',
      blocks: [
        ParagraphBlock(text: 'Intro line stays at the top of its page.'),
        // 100x160 at a 300px column renders 480px: above the 60% threshold
        // but short of the 600px page, so the centered gap is observable.
        ImageBlock(media: fixtureMediaRef(0), width: 100, height: 160),
      ],
    );
    final controller = PagedReaderController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 600,
              child: PagedReaderViewport(
                content: content,
                controller: controller,
                imageBuilder: (_, image) =>
                    const SizedBox.expand(key: ValueKey('standalone-image')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final page = tester.getRect(find.byType(PagedReaderViewport));
    final text = tester.getRect(find.byType(Text).first);
    expect(text.top - page.top, lessThan(30));

    await tester.tapAt(
      tester.getTopLeft(find.byType(PagedReaderViewport)) +
          const Offset(280, 300),
    );
    await tester.pumpAndSettle();
    final image = tester.getRect(
      find.byKey(const ValueKey('standalone-image')),
    );
    expect(image.height, lessThan(page.height));
    expect(image.top - page.top, closeTo(page.bottom - image.bottom, .5));
  });
}
