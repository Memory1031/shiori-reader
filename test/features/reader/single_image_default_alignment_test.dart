import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_image.dart';

void main() {
  ReaderImageGeometry measure(
    ImageBlock block, {
    required double height,
    bool standalone = true,
    Size? knownSize,
  }) => readerImageForColumn(
    block,
    width: 680,
    height: height,
    style: const TextStyle(fontSize: 20),
    scaler: TextScaler.noScaling,
    direction: TextDirection.ltr,
    content: ChapterContent(
      key: fixtureChapterKey(FixtureScenario.longChapter),
      title: 'Synthetic',
      blocks: [
        block,
        if (!standalone) ParagraphBlock(text: 'Body.'),
      ],
    ),
    blockIndex: 0,
    knownSize: knownSize,
  );
  test(
    'single-image default only changes alignment, not role, fit or size',
    () {
      final block = ImageBlock(
        media: fixtureMediaRef(0),
        width: 1401,
        height: 2000,
        sizing: ImageSizing(role: ImageRole.flow),
      );
      for (final height in [262.0, 912.0]) {
        final single = measure(block, height: height);
        final mixed = measure(block, height: height, standalone: false);
        expect(single.alignment, Alignment.center);
        expect(mixed.alignment, AlignmentDirectional.centerStart);
        expect(single.size, mixed.size);
        expect(single.height, mixed.height);
        expect(single.fit, mixed.fit);
        expect(block.sizing!.role, ImageRole.flow);
      }
      // Late intrinsic decoding still changes geometry through the same path.
      final loaded = measure(
        block,
        height: 262,
        knownSize: const Size(2000, 1401),
      );
      expect(loaded.alignment, Alignment.center);
      expect(
        loaded.size,
        measure(
          block,
          height: 262,
          standalone: false,
          knownSize: const Size(2000, 1401),
        ).size,
      );
    },
  );
  test('explicit start, center and end alignment override the new default', () {
    for (final (alignment, expected) in [
      (ParagraphAlignment.start, AlignmentDirectional.centerStart),
      (ParagraphAlignment.center, Alignment.center),
      (ParagraphAlignment.end, AlignmentDirectional.centerEnd),
    ]) {
      final block = ImageBlock(
        media: fixtureMediaRef(0),
        width: 80,
        height: 200,
        sizing: ImageSizing(role: ImageRole.flow, alignment: alignment),
      );
      expect(measure(block, height: 262).alignment, expected);
    }
  });
}
