import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import 'inline_images_test.dart' as inline_images;
import 'local_links_test.dart' as links;
import 'local_reading_test.dart' as local_reading;
import 'page_boundaries_test.dart' as pagination;
import 'restore_test.dart' as restore;
import 'rich_reflow_test.dart' as rich_reflow;

// Reuse the semantic assertions at desktop sizes, including a scaled display.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  for (final display in [
    (const Size(1280, 720), 1.0),
    (const Size(1920, 1080), 1.0),
    (const Size(2560, 1440), 1.5),
  ]) {
    group('Desktop ${display.$1} at ${display.$2} DPR', () {
      setUp(() {
        binding.platformDispatcher.implicitView!
          ..physicalSize = display.$1
          ..devicePixelRatio = display.$2;
      });
      tearDown(() {
        binding.platformDispatcher.implicitView!
          ..resetPhysicalSize()
          ..resetDevicePixelRatio();
      });
      local_reading.main();
      links.main();
      inline_images.main();
      rich_reflow.main();
      pagination.main();
      restore.main();
    });
  }

  testWidgets('desktop resize and display scaling retain semantic position', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final content = ChapterContent(
      key: fixtureChapterKey(FixtureScenario.longChapter),
      title: 'Desktop resize',
      blocks: [
        for (var i = 0; i < 80; i++)
          ParagraphBlock(
            text: 'Paragraph $i. ${'Reading across a resize. ' * 30}',
          ),
      ],
    );
    final controller = PagedReaderController();
    await tester.pumpWidget(
      MaterialApp(
        home: PagedReaderViewport(
          content: content,
          controller: controller,
          textStyle: pagination.style,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final target = restore.anchor(content, 30, .4);
    controller.restore(target);
    await tester.pumpAndSettle();
    expect(controller.capture(), target);
    for (final display in [
      (const Size(1920, 1080), 1.0),
      (const Size(2560, 1440), 1.5),
      (const Size(1280, 720), 1.0),
    ]) {
      tester.view
        ..physicalSize = display.$1
        ..devicePixelRatio = display.$2;
      await tester.pumpAndSettle();
      expect(controller.isRestoring, isFalse);
      expect(controller.capture(), target);
      expect(tester.takeException(), isNull);
    }
    final turn = controller.next();
    await tester.pumpAndSettle();
    await turn;
    expect(
      controller.capture()!.chapterFraction,
      greaterThan(target.chapterFraction),
    );
  });
}
