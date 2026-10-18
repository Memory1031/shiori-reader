import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_inline_images.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

ImageBlock image({
  int? width = 32,
  int? height = 32,
  ImageSizing? sizing,
  BlockBox? box,
  BlockBox? layout,
  String? caption,
}) => ImageBlock(
  media: fixtureMediaRef(0),
  width: width,
  height: height,
  sizing: sizing ?? ImageSizing(alignment: ParagraphAlignment.center),
  box: box,
  layout: layout,
  caption: caption,
);
ChapterContent chapter(List<ContentBlock> blocks) => ChapterContent(
  key: fixtureChapterKey(FixtureScenario.longChapter),
  title: 'Original fixture',
  blocks: blocks,
);
ReaderImageGeometry geometry(
  ImageBlock block, {
  double width = 600,
  double height = 600,
  double font = 20,
  TextScaler scaler = TextScaler.noScaling,
  Size? knownSize,
}) => readerImageForColumn(
  block,
  width: width,
  height: height,
  style: TextStyle(fontSize: font),
  scaler: scaler,
  direction: TextDirection.ltr,
  content: chapter([block]),
  blockIndex: 0,
  knownSize: knownSize,
);
PageLayout layout(ChapterContent content, {int columns = 2}) => PageLayout(
  index: ChunkIndex(content),
  width: 600,
  height: 600,
  style: const TextStyle(fontSize: 20, height: 1),
  scaler: TextScaler.noScaling,
  direction: TextDirection.ltr,
  columns: columns,
  paragraphSpacing: 0,
);

void main() {
  test(
    'page role accepts 100% fill but preserves actual authored constraints',
    () {
      for (final columns in [1, 2]) {
        for (final local in [false, true]) {
          for (final box in [
            BlockBox(group: 0, widthFraction: 1),
            BlockBox(
              group: 0,
              widthLength: LayoutLength(1, LayoutUnit.fraction),
            ),
            BlockBox(group: 0, maxWidthFraction: 1),
          ]) {
            final c = chapter([
              image(
                width: 300,
                height: 180,
                sizing: ImageSizing(role: ImageRole.page),
                box: local ? null : box,
                layout: local ? box : null,
              ),
            ]);
            final l = layout(c, columns: columns);
            final p = l.forward(const PageCursor(0, 0))!;
            expect(p.centered, isTrue);
            expect(p.fullWidth, columns == 2);
            final back = l.backward(p.end)!;
            expect((back.centered, back.fullWidth), (p.centered, p.fullWidth));
          }
          for (final box in [
            BlockBox(group: 0, width: 200),
            BlockBox(group: 0, widthFraction: .5),
            BlockBox(group: 0, maxWidth: 200),
            BlockBox(
              group: 0,
              widthFraction: 1,
              margins: BoxInsets(top: LayoutLength(12)),
            ),
            BlockBox(group: 0, widthFraction: 1, borderWidth: 1),
            BlockBox(group: 0, widthFraction: 1, padding: 10),
          ]) {
            final p = layout(
              chapter([
                image(
                  sizing: ImageSizing(role: ImageRole.page),
                  box: local ? null : box,
                  layout: local ? box : null,
                ),
              ]),
              columns: columns,
            ).forward(const PageCursor(0, 0))!;
            expect((p.centered, p.fullWidth), (false, false));
          }
        }
      }
    },
  );
  test('known indexes retain grouped edges across an image-heavy chapter', () {
    final c = chapter(
      List.generate(
        2048,
        (i) => ImageBlock(
          media: fixtureMediaRef(0),
          width: 32,
          height: 32,
          sizing: ImageSizing(),
          box: BlockBox(
            group: i ~/ 2,
            margins: BoxInsets(top: LayoutLength(8), bottom: LayoutLength(12)),
          ),
        ),
      ),
    );
    final l = layout(c, columns: 1);
    var cursor = const PageCursor(0, 0);
    var count = 0;
    while (true) {
      final p = l.forward(cursor);
      if (p == null) break;
      for (final fragment in p.fragments) {
        final at = l.index.chunks[fragment.unit].blockIndex;
        final b = c.blocks[at] as ImageBlock;
        final g = readerImageForColumn(
          b,
          width: 600,
          height: 600,
          style: const TextStyle(fontSize: 20, height: 1),
          scaler: TextScaler.noScaling,
          direction: TextDirection.ltr,
          content: c,
          blockIndex: at,
        );
        expect(g.size, const Size(32, 32));
        expect(fragment.height, at.isEven ? 40 : 44);
        count++;
      }
      cursor = p.end;
    }
    expect(count, 2048);
  });
  test(
    'inline authored caps use the same scaled and unscaled span geometry',
    () {
      final i = InlineImage(
        offset: 0,
        media: fixtureMediaRef(0),
        widthEm: 2,
        heightEm: 1,
        maxWidth: LayoutLength(20),
        maxHeight: LayoutLength(1, LayoutUnit.em),
      );
      const style = TextStyle(fontSize: 20);
      expect(
        readerInlineSize(i, style, TextScaler.linear(2), maxWidth: 600),
        const Size(20, 10),
      );
      expect(
        readerInlineSize(
          i,
          style,
          TextScaler.linear(2),
          maxWidth: 600,
          unscaled: true,
        ),
        const Size(10, 5),
      );
    },
  );
  test(
    'ordinary images use natural logical dimensions, large images shrink',
    () {
      expect(geometry(image()).size, const Size(32, 32));
      expect(geometry(image(width: 88, height: 88)).size, const Size(88, 88));
      expect(
        geometry(image(width: 1200, height: 1800)).size,
        const Size(400, 600),
      );
      expect(
        geometry(image(), scaler: TextScaler.linear(2)).size,
        const Size(32, 32),
      );
    },
  );
  test(
    'confirmed low-resolution page can enlarge; author width stays authoritative',
    () {
      expect(
        geometry(
          image(
            width: 300,
            height: 450,
            sizing: ImageSizing(role: ImageRole.page),
          ),
        ).size,
        const Size(400, 600),
      );
      expect(
        geometry(
          image(
            sizing: ImageSizing(role: ImageRole.page),
            layout: BlockBox(
              group: 0,
              widthLength: LayoutLength(2, LayoutUnit.em),
            ),
          ),
        ).size,
        const Size(40, 40),
      );
    },
  );
  test(
    'width is distinguished from max-width, including em and parent constraints',
    () {
      expect(
        geometry(
          image(
            layout: BlockBox(
              group: 0,
              widthLength: LayoutLength(1, LayoutUnit.fraction),
            ),
          ),
        ).size,
        const Size(600, 600),
      );
      expect(
        geometry(
          image(
            layout: BlockBox(
              group: 0,
              maxWidthLength: LayoutLength(1, LayoutUnit.fraction),
            ),
          ),
        ).size,
        const Size(32, 32),
      );
      final em = image(
        layout: BlockBox(group: 0, widthLength: LayoutLength(2, LayoutUnit.em)),
      );
      expect(geometry(em, font: 30).size, const Size(60, 60));
      expect(
        geometry(em, scaler: TextScaler.linear(2)).size,
        const Size(80, 80),
      );
      expect(
        geometry(image(box: BlockBox(group: 0, width: 200))).size,
        const Size(32, 32),
      );
      expect(
        geometry(
          image(width: 600, height: 900, box: BlockBox(group: 0, width: 200)),
        ).size,
        const Size(200, 300),
      );
    },
  );
  test(
    'height, max-height and two explicit axes share measured and painted shape',
    () {
      expect(
        geometry(
          image(
            width: 80,
            height: 40,
            sizing: ImageSizing(height: LayoutLength(100)),
          ),
        ).size,
        const Size(200, 100),
      );
      expect(
        geometry(image(sizing: ImageSizing(maxHeight: LayoutLength(16)))).size,
        const Size(16, 16),
      );
      expect(
        geometry(
          image(
            width: 80,
            height: 40,
            sizing: ImageSizing(height: LayoutLength(.5, LayoutUnit.fraction)),
          ),
        ).size,
        const Size(600, 300),
      );
      final axes = geometry(
        image(
          layout: BlockBox(group: 0, width: 200),
          sizing: ImageSizing(height: LayoutLength(100)),
        ),
      );
      expect(axes.size, const Size(200, 100));
      expect(axes.fit, BoxFit.fill);
    },
  );
  test('edges and caption reserve only their measured space', () {
    final b = image(
      caption: 'Self-authored caption',
      box: BlockBox(
        group: 0,
        margins: BoxInsets(top: LayoutLength(8), bottom: LayoutLength(12)),
        paddingEdges: BoxInsets(top: LayoutLength(4), bottom: LayoutLength(6)),
      ),
    );
    final content = chapter([b]);
    final g = geometry(b);
    final page = layout(content, columns: 1).forward(const PageCursor(0, 0))!;
    expect(g.size, const Size(32, 32));
    expect(g.caption, greaterThan(16));
    expect(page.fragments.single.height, closeTo(g.height + 30, .001));
    expect(g.alignment, Alignment.center);
  });
  test('unknown size has bounded fallback and late natural geometry', () {
    final b = image(width: null, height: null);
    expect(geometry(b, width: 100, height: 90).size, const Size(90, 90));
    expect(geometry(b, knownSize: const Size(32, 32)).size, const Size(32, 32));
  });
  test(
    'layout evidence round-trips without changing media or reading identity',
    () {
      final legacy = ImageBlock(
        media: fixtureMediaRef(0),
        width: 32,
        height: 32,
      );
      final modern = image(
        sizing: ImageSizing(height: LayoutLength(2, LayoutUnit.em)),
      );
      expect(legacy.blockKey, modern.blockKey);
      expect(
        chapter([legacy]).contentRevision,
        chapter([modern]).contentRevision,
      );
      final old =
          ContentBlock.fromJson(
                jsonDecode(jsonEncode(legacy.toJson())) as Map<String, dynamic>,
              )
              as ImageBlock;
      expect(old.sizing, isNull);
      expect(geometry(old).size, const Size(600, 600));
      final restored = ChapterContent.fromJson(
        jsonDecode(jsonEncode(chapter([modern]).toJson()))
            as Map<String, dynamic>,
      );
      expect(restored, chapter([modern]));
    },
  );
  test(
    'standalone flow ornament never gains a page role from its block count',
    () {
      final l = layout(chapter([image()]));
      final p = l.forward(const PageCursor(0, 0))!;
      expect(p.fullWidth, isFalse);
      expect(p.centered, isFalse);
      expect(p.fragments.single.height, 32);
    },
  );
  for (final columns in [1, 2]) {
    test(
      'natural ornaments flow with text, large illustrations pair and reverse ($columns)',
      () {
        final content = chapter([
          ParagraphBlock(text: 'Opening original text.'),
          image(),
          ParagraphBlock(text: 'After ornament. ' * 80),
          image(width: 1200, height: 1800),
          image(width: 1200, height: 1800),
          ParagraphBlock(text: 'Ending original text.'),
        ]);
        final l = layout(content, columns: columns);
        var cursor = const PageCursor(0, 0);
        final pages = <ReaderPage>[];
        while (true) {
          final p = l.forward(cursor);
          if (p == null) break;
          pages.add(p);
          cursor = p.end;
          expect(pages.length, lessThan(30));
        }
        expect(pages.first.fragments.any((f) => f.height == 32), isTrue);
        final all = pages.expand((p) => p.fragments).toList();
        expect(all.where((f) => f.text == null).map((f) => f.height), [
          32,
          600,
          600,
        ]);
        for (final page in pages.reversed) {
          final back = l.backward(page.end)!;
          expect(
            (back.start.unit, back.start.offset),
            (page.start.unit, page.start.offset),
          );
        }
      },
    );
  }
}
