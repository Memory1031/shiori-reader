import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

import '../../data/local/support/epub_fixtures.dart';

void main() {
  for (final selector in ['.cover', 'img']) {
    for (final columns in [1, 2]) {
      testWidgets(
        'stored EPUB cover with zero edges on $selector centers in $columns columns',
        (tester) async {
          final files = epubFiles();
          files['OPS/text/a.xhtml'] = utf8.encode(
            '<html><head><title>Cover</title><style>'
            '$selector {margin:0px;padding:0px;text-align:center;}'
            '</style></head><body><div><div class="cover duokan-image-single">'
            '<img alt="" src="../images/%E6%98%9F%20%E7%A9%BA.png"/>'
            '</div></div></body></html>',
          );
          final parsed = EpubParser(
            zipFiles(files),
            NovelKey(sourceId: SourceId('local'), novelId: 'zero-edge-cover'),
            'cover.epub',
          ).parse().content.chapters.first;
          // Imported books retain these boxes; exercise a cold stored read.
          final content = ChapterContent.fromJson(
            jsonDecode(jsonEncode(parsed.toJson())) as Map<String, dynamic>,
          );
          final image = content.blocks.single as ImageBlock;
          expect(selector == '.cover' ? image.box : image.layout, isNotNull);
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: columns == 1 ? 300 : 750,
                  height: 600,
                  child: PagedReaderViewport(
                    content: content,
                    controller: PagedReaderController(),
                    columns: columns,
                    imageExtent: (_) => 180,
                    imageBuilder: (_, _) =>
                        const SizedBox.expand(key: ValueKey('cover-image')),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final page = tester.getRect(find.byType(PagedReaderViewport));
          final picture = tester.getRect(
            find.byKey(const ValueKey('cover-image')),
          );
          expect(picture.height, 180);
          expect(picture.center.dy, closeTo(page.center.dy, .5));
          expect(picture.center.dx, closeTo(page.center.dx, .5));
          expect(picture.width, columns == 1 ? 300 : 680);
        },
      );
    }
  }

  for (final (selector, property) in [
    ('.cover', 'max-width'),
    ('img', 'max-width'),
    ('.cover', 'width'),
    ('img', 'width'),
  ]) {
    for (final columns in [1, 2]) {
      testWidgets(
        'stored responsive EPUB cover with $property on $selector centers in $columns columns',
        (tester) async {
          final files = epubFiles();
          files['OPS/text/a.xhtml'] = utf8.encode(
            '<html><head><style>'
            '$selector {$property:100%;margin:0;padding:0;text-align:center;}'
            '</style></head><body><div class="cover">'
            '<img src="../images/%E6%98%9F%20%E7%A9%BA.png"/>'
            '</div></body></html>',
          );
          final parsed = EpubParser(
            zipFiles(files),
            NovelKey(sourceId: SourceId('local'), novelId: 'responsive-cover'),
            'cover.epub',
          ).parse().content.chapters.first;
          final content = ChapterContent.fromJson(
            jsonDecode(jsonEncode(parsed.toJson())) as Map<String, dynamic>,
          );
          final image = content.blocks.single as ImageBlock;
          final box = selector == '.cover' ? image.box! : image.layout!;
          expect(
            property == 'width' ? box.widthFraction : box.maxWidthFraction,
            1,
          );
          expect(
            property == 'width' ? box.widthLength : box.maxWidthLength,
            LayoutLength(1, LayoutUnit.fraction),
          );
          final controller = PagedReaderController();
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: columns == 1 ? 300 : 750,
                  height: 600,
                  child: PagedReaderViewport(
                    content: content,
                    controller: controller,
                    columns: columns,
                    imageExtent: (_) => 180,
                    imageBuilder: (_, _) =>
                        const SizedBox.expand(key: ValueKey('cover-image')),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final page = tester.getRect(find.byType(PagedReaderViewport));
          final picture = tester.getRect(
            find.byKey(const ValueKey('cover-image')),
          );
          expect(picture.height, 180);
          expect(picture.center.dx, closeTo(page.center.dx, .5));
          expect(picture.center.dy, closeTo(page.center.dy, .5));
          expect(picture.width, columns == 1 ? 300 : 680);
          expect(
            controller.inspectDisplayedPage()!.page.fullWidth,
            columns == 2,
          );
          expect(
            find.byKey(const ValueKey('reader-spread-gutter')),
            findsNothing,
          );
        },
      );
    }
  }

  test('stored responsive width limits support either representation', () {
    for (final box in [
      BlockBox(group: 0, maxWidthFraction: 1),
      BlockBox(group: 0, maxWidthLength: LayoutLength(1, LayoutUnit.fraction)),
    ]) {
      for (final local in [false, true]) {
        final content = ChapterContent.fromJson(
          jsonDecode(
                jsonEncode(
                  ChapterContent(
                    key: fixtureChapterKey(FixtureScenario.singleImage),
                    title: 'Cover',
                    blocks: [
                      ImageBlock(
                        media: fixtureMediaRef(0),
                        width: 300,
                        height: 180,
                        box: local ? null : box,
                        layout: local ? box : null,
                      ),
                    ],
                  ).toJson(),
                ),
              )
              as Map<String, dynamic>,
        );
        for (final columns in [1, 2]) {
          final layout = PageLayout(
            index: ChunkIndex(content),
            width: 300,
            height: 600,
            style: const TextStyle(fontSize: 20),
            scaler: TextScaler.noScaling,
            direction: TextDirection.ltr,
            columns: columns,
          );
          final page = layout.forward(const PageCursor(0, 0))!;
          expect(page.centered, isTrue);
          expect(page.fullWidth, columns == 2);
          final reverse = layout.backward(page.end)!;
          expect(reverse.centered, page.centered);
          expect(reverse.fullWidth, page.fullWidth);
        }
      }
    }
  });

  test('authored image geometry and decoration retain their placement', () {
    for (final box in [
      BlockBox(group: 0, margins: BoxInsets(top: LayoutLength(20))),
      BlockBox(group: 0, paddingEdges: BoxInsets(left: LayoutLength(10))),
      BlockBox(group: 0, padding: 10),
      BlockBox(group: 0, backgroundColor: 0xffeeeeee),
      BlockBox(group: 0, borderWidth: 1),
      BlockBox(
        group: 0,
        borders: BoxBorders(top: BoxBorderSide(width: LayoutLength(1))),
      ),
      BlockBox(group: 0, widthLength: LayoutLength(.5, LayoutUnit.fraction)),
      BlockBox(group: 0, width: 200),
      BlockBox(group: 0, widthFraction: 1),
      BlockBox(group: 0, widthLength: LayoutLength(1, LayoutUnit.fraction)),
      BlockBox(group: 0, maxWidth: 200),
      BlockBox(group: 0, maxWidthFraction: .75),
      BlockBox(group: 0, maxWidthLength: LayoutLength(150)),
      BlockBox(group: 0, maxWidthLength: LayoutLength(12, LayoutUnit.em)),
      BlockBox(
        group: 0,
        maxWidthLength: LayoutLength(.75, LayoutUnit.fraction),
      ),
      BlockBox(
        group: 0,
        maxWidthLength: LayoutLength(1.2, LayoutUnit.fraction),
      ),
      BlockBox(
        group: 0,
        maxWidthFraction: 1,
        maxWidthLength: LayoutLength(.75, LayoutUnit.fraction),
      ),
      BlockBox(
        group: 0,
        backgroundImage: BlockBackgroundImage(
          media: fixtureMediaRef(1),
          intrinsicWidth: 100,
          intrinsicHeight: 100,
        ),
      ),
      BlockBox(group: 0, radius: LayoutLength(8)),
      BlockBox(
        group: 0,
        decorationColumns: DecorationColumns(
          leadingFraction: .2,
          trailingFraction: .2,
        ),
      ),
      BlockBox(group: 0, autoLeft: true),
    ]) {
      // A responsive cap must not make an otherwise authored box neutral.
      final protected = BlockBox.fromJson({
        ...box.toJson(),
        'maxWidthFraction': box.maxWidthFraction ?? 1.0,
        'maxWidthLength':
            (box.maxWidthLength ?? LayoutLength(1, LayoutUnit.fraction))
                .toJson(),
      });
      for (final local in [false, true]) {
        final content = ChapterContent(
          key: fixtureChapterKey(FixtureScenario.singleImage),
          title: 'Authored cover',
          blocks: [
            ImageBlock(
              media: fixtureMediaRef(0),
              width: 300,
              height: 180,
              box: local ? null : protected,
              layout: local ? protected : null,
            ),
          ],
        );
        for (final columns in [1, 2]) {
          final page = PageLayout(
            index: ChunkIndex(content),
            width: 300,
            height: 600,
            style: const TextStyle(fontSize: 20),
            scaler: TextScaler.noScaling,
            direction: TextDirection.ltr,
            columns: columns,
          ).forward(const PageCursor(0, 0))!;
          expect(page.centered, isFalse);
          expect(page.fullWidth, isFalse);
        }
      }
    }
  });

  for (final columns in [1, 2]) {
    testWidgets('responsive cap preserves authored cover geometry ($columns)', (
      tester,
    ) async {
      final files = epubFiles();
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<html><head><style>'
        '.cover {width:200px;margin:20px 0 0 10px;padding:12px;'
        'border:1px solid #777777;background-color:#eeeeee;}'
        'img {max-width:100%;}'
        '</style></head><body><div class="cover">'
        '<img src="../images/%E6%98%9F%20%E7%A9%BA.png"/>'
        '</div></body></html>',
      );
      final parsed = EpubParser(
        zipFiles(files),
        NovelKey(
          sourceId: SourceId('local'),
          novelId: 'authored-responsive-cover',
        ),
        'cover.epub',
      ).parse().content.chapters.first;
      final content = ChapterContent.fromJson(
        jsonDecode(jsonEncode(parsed.toJson())) as Map<String, dynamic>,
      );
      final image = content.blocks.single as ImageBlock;
      expect(image.box!.width, 200);
      expect(image.box!.backgroundColor, 0xffeeeeee);
      expect(image.box!.borders!.top!.width, LayoutLength(1));
      expect(image.layout!.maxWidthFraction, 1);
      final controller = PagedReaderController();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: columns == 1 ? 300 : 750,
              height: 600,
              child: PagedReaderViewport(
                content: content,
                controller: controller,
                columns: columns,
                imageExtent: (_) => 180,
                imageBuilder: (_, _) =>
                    const SizedBox.expand(key: ValueKey('authored-image')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final page = tester.getRect(find.byType(PagedReaderViewport));
      final picture = tester.getRect(
        find.byKey(const ValueKey('authored-image')),
      );
      expect(picture.width, 200);
      expect(picture.left - page.left, 23);
      expect(picture.top - page.top, 33);
      expect(controller.inspectDisplayedPage()!.page.centered, isFalse);
      expect(controller.inspectDisplayedPage()!.page.fullWidth, isFalse);
    });
  }

  for (final imageFirst in [false, true]) {
    testWidgets('responsive body illustration keeps one column ($imageFirst)', (
      tester,
    ) async {
      final image = ImageBlock(
        media: fixtureMediaRef(0),
        width: 300,
        height: 180,
        layout: BlockBox(
          group: 0,
          maxWidthFraction: 1,
          maxWidthLength: LayoutLength(1, LayoutUnit.fraction),
        ),
      );
      final paragraph = ParagraphBlock(
        text: 'Body text remains in its own column.',
      );
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.singleImage),
        title: 'Body illustration',
        blocks: imageFirst ? [image, paragraph] : [paragraph, image],
      );
      final controller = PagedReaderController();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 750,
              height: 600,
              child: PagedReaderViewport(
                content: content,
                controller: controller,
                columns: 2,
                imageExtent: (_) => 400,
                imageBuilder: (_, _) =>
                    const SizedBox.expand(key: ValueKey('body-image')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final picture = tester.getRect(find.byKey(const ValueKey('body-image')));
      final viewport = tester.getRect(find.byType(PagedReaderViewport));
      final gutter = tester.getRect(
        find.byKey(const ValueKey('reader-spread-gutter')),
      );
      expect(picture.width, (viewport.width - gutter.width) / 2);
      expect(picture.center.dy, closeTo(viewport.center.dy, .5));
      expect(
        imageFirst
            ? picture.right <= gutter.left
            : picture.left >= gutter.right,
        isTrue,
      );
      final page = controller.inspectDisplayedPage()!.page;
      expect(page.fullWidth, isFalse);
      expect(page.columnBreak, isNotNull);
    });
  }

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
