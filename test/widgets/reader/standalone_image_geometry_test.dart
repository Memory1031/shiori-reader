import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/domain/bookmark_position.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

import '../../data/local/support/epub_fixtures.dart';
import 'image_sizing_test.dart' as media show Images, app, frames;
import 'settings_test.dart' show Store;

ChapterContent cover({bool blanks = true}) {
  final files = epubFiles();
  files['OPS/images/星 空.png'] = fixturePng(1000, 250, 2);
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><body>${blanks ? '<p id="before"><br/></p>' : ''}'
    '<img style="width:100%" src="../images/%E6%98%9F%20%E7%A9%BA.png"/>'
    '${blanks ? '<p id="after"><br/></p>' : ''}</body></html>',
  );
  final parsed = EpubParser(
    zipFiles(files),
    NovelKey(sourceId: SourceId('local'), novelId: 'wide-cover'),
    'cover.epub',
  ).parse().content.chapters.first;
  return ChapterContent.fromJson(
    jsonDecode(jsonEncode(parsed.toJson())) as Map<String, dynamic>,
  );
}

void main() {
  for (final (width, gap, columns, height) in [
    (1100.0, 72.0, 2, 600.0),
    (600.0, 40.0, 2, 600.0),
    (900.0, 72.0, 1, 600.0),
    (1100.0, 72.0, 2, 80.0),
  ]) {
    testWidgets(
      'standalone image measures and paints $columns columns at $width x $height / $gap',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final content = cover();
        final images = media.Images(fixturePng(1000, 250, 2));
        final controller = PagedReaderController();
        await tester.pumpWidget(
          media.app(
            Center(
              child: SizedBox(
                width: width,
                height: height,
                child: PagedReaderViewport(
                  content: content,
                  controller: controller,
                  columns: columns,
                  columnGap: gap,
                  imageBuilder: (context, block) => LayoutBuilder(
                    builder: (context, bounds) {
                      final geometry = readerImageForColumn(
                        block,
                        width: bounds.maxWidth,
                        height: height,
                        style: const TextStyle(fontSize: 20),
                        scaler: TextScaler.noScaling,
                        direction: TextDirection.ltr,
                        content: content,
                        blockIndex: 1,
                      );
                      return ReaderImage(
                        block: block,
                        repository: images,
                        geometry: geometry,
                        captionHeight: geometry.caption,
                        onIntrinsicSize: (_) {},
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await media.frames(tester);
        final page = controller.inspectDisplayedPage()!.page;
        final expectedWidth = (columns == 2 ? width.clamp(0.0, 680.0) : width)
            .clamp(0.0, height * 4);
        expect(page.fullWidth, columns == 2);
        expect(page.fragments.single.height, closeTo(expectedWidth / 4, .01));
        final picture = tester.getRect(find.byType(RawImage));
        final bounds = tester.getRect(find.byType(PagedReaderViewport));
        expect(picture.size, Size(expectedWidth, expectedWidth / 4));
        expect(picture.center.dx, closeTo(bounds.center.dx, .01));
        expect(picture.center.dy, closeTo(bounds.center.dy, .01));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await media.frames(tester);
        expect(images.closed, images.loads);
      },
    );
  }

  for (final restoreBlank in [false, true]) {
    testWidgets(
      'cover bookmark uses the visible image and preserves explicit blank restore=$restoreBlank',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final content = cover();
        final index = ChunkIndex(content);
        final images = media.Images(fixturePng(1000, 250, 2));
        final controller = PagedReaderController();
        final store = Store()..value = ReaderSettings(controlsHintSeen: true);
        await tester.pumpWidget(
          media.app(
            ReaderContentView(
              content: content,
              images: images,
              settings: store,
              viewportController: controller,
              initialPosition: restoreBlank ? index.position(0, 0) : null,
            ),
          ),
        );
        await media.frames(tester);
        final viewport = tester.widget<PagedReaderViewport>(
          find.byType(PagedReaderViewport),
        );
        // The production host already chooses a single page for a dedicated cover.
        expect(viewport.columns, 1);
        final rect = tester.getRect(find.byType(RawImage));
        expect(rect.size, const Size(680, 170));
        final page = controller.inspectDisplayedPage()!.page;
        expect(page.start.unit, 0);
        expect(page.end.unit, 3);
        final position = controller.capture()!;
        expect(position.blockIndex, restoreBlank ? 0 : 1);
        expect(
          position.blockKey,
          content.blocks[restoreBlank ? 0 : 1].blockKey,
        );
        if (!restoreBlank) {
          final anchor = BookmarkPositionIndex([
            content,
          ]).capture(content.key, position)!;
          expect(anchor.unique, isTrue);
          expect(anchor.blockDigest, content.blocks[1].semanticDigest);
          final mark = UserBookmark(
            id: 'cover-mark',
            chapter: content.key,
            chapterTitle: content.title,
            anchor: anchor,
            createdAt: DateTime.utc(2026),
          );
          final reparsed = cover(blanks: false);
          final migrated = migrateBookmarks([content], [reparsed], [
            mark,
          ]).single;
          expect(migrated.location, BookmarkLocation.migrated);
          expect(migrated.anchor.position.blockIndex, 0);
          expect(
            migrated.anchor.position.blockKey,
            reparsed.blocks.single.blockKey,
          );
        }
        tester.view.physicalSize = const Size(500, 820);
        await media.frames(tester);
        expect(controller.capture()!.blockKey, position.blockKey);
        expect(controller.capture()!.blockIndex, position.blockIndex);
        expect(tester.getSize(find.byType(RawImage)).width, lessThan(500));
        await tester.pumpWidget(const SizedBox());
        await media.frames(tester);
        expect(images.closed, images.loads);
      },
    );
  }
}
