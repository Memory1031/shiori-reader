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
      BlockBox(group: 0, maxWidth: 200),
      BlockBox(group: 0, autoLeft: true),
    ]) {
      for (final local in [false, true]) {
        final content = ChapterContent(
          key: fixtureChapterKey(FixtureScenario.singleImage),
          title: 'Authored cover',
          blocks: [
            ImageBlock(
              media: fixtureMediaRef(0),
              width: 300,
              height: 180,
              box: local ? null : box,
              layout: local ? box : null,
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
