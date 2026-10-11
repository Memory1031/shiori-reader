import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'epub_authored_layout_test.dart' show authoredContent;

const blankBorderCss =
    '.line{border-top:1px solid #604635;'
    'margin:.4em 0 -.7em -3px}';

void main() {
  test(
    'direct blank borders retain the outer box, gaps, links and identity',
    () {
      const body =
          '<div style="width:14em;padding:4px;border:2px solid blue">'
          '<p>Author One</p><p class="line" id="line"><br/></p>'
          '<p>Profile 😀 one.</p><p>Author Two</p><p class="line"><br/></p>'
          '<p>Profile two.</p></div><p><a href="#line">Line</a></p>';
      final parsed = authoredContent(body, blankBorderCss);
      final plain = authoredContent(body);
      final chapter = parsed.chapters.first;
      final gaps = chapter.blocks
          .whereType<ParagraphBlock>()
          .where((b) => b.text.isEmpty)
          .toList();
      expect(gaps.length, 2);
      for (final gap in gaps) {
        expect(gap.authoredGapEm, 1);
        expect(gap.box!.widthLength, LayoutLength(14, LayoutUnit.em));
        expect(gap.box!.borders!.top!.width.value, 2);
        expect(gap.box!.paddingEdges!.left!.value, 4);
        expect(gap.layout, isNotNull);
        expect(gap.layout!.borders!.top!.width.value, 1);
        expect(gap.layout!.borders!.top!.color, 0xff604635);
        expect(gap.layout!.margins!.top, LayoutLength(.4, LayoutUnit.em));
        expect(gap.layout!.margins!.left, isNull);
        expect(gap.layout!.margins!.bottom, isNull);
        expect(gap.layout!.backgroundColor, isNull);
        expect(gap.layout!.radius, isNull);
        expect(gap.withOccurrence(1).layout, gap.layout);
      }
      expect(
        chapter.blocks.map((b) => b.blockKey),
        plain.chapters.first.blocks.map((b) => b.blockKey),
      );
      expect(chapter.contentRevision, plain.chapters.first.contentRevision);
      expect(
        parsed.links.map((l) => l.toJson()),
        plain.links.map((l) => l.toJson()),
      );
      expect(parsed.links.single.targetBlockKey, gaps.first.blockKey);
      expect(ChapterContent.fromJson(chapter.toJson()), chapter);
      expect(
        ChapterContent.fromJson(plain.chapters.first.toJson()),
        plain.chapters.first,
      );
    },
  );

  test(
    'multiple visible breaks and independent border sides keep their semantics',
    () {
      final gap =
          authoredContent(
                '<div style="width:10em"><p style="'
                'font-size:.8em;border-width:1px 2px 3px 4px;'
                'border-style:solid dashed none hidden;border-color:red'
                '"><br/><br/></p><p>Tail</p></div>',
              ).chapters.first.blocks.first
              as ParagraphBlock;
      expect(gap.authoredGapEm, 1.6);
      expect(gap.layout!.fontScale, .8);
      expect(gap.layout!.borders!.top!.style, BoxBorderStyle.solid);
      expect(gap.layout!.borders!.right!.style, BoxBorderStyle.dashed);
      expect(gap.layout!.borders!.bottom!.width.value, 0);
      expect(gap.layout!.borders!.left!.width.value, 0);
    },
  );

  for (final (name, contents) in [
    ('ordinary blank', '<p><br/></p>'),
    ('nonempty paragraph', '<p class="line">Text<br/></p>'),
    ('deeper container', '<div><p class="line"><br/></p></div>'),
    ('inline wrapper', '<p class="line"><span><br/></span></p>'),
    ('no visible border', '<p style="border-top:1px none red"><br/></p>'),
    ('background', '<p class="line" style="background-color:red"><br/></p>'),
    ('radius', '<p class="line" style="border-radius:3px"><br/></p>'),
    (
      'positioned',
      '<p class="line" style="position:relative;left:2px"><br/></p>',
    ),
    ('transformed', '<p class="line" style="transform:rotate(2deg)"><br/></p>'),
    ('fixed height', '<p class="line" style="height:3em"><br/></p>'),
  ]) {
    test('$name does not expand the local blank-border subset', () {
      final chapter = authoredContent(
        '<div style="width:14em">$contents<p>Tail</p></div>',
        blankBorderCss,
      ).chapters.first;
      expect(chapter.blocks.every((b) => b.layout == null), isTrue);
      expect((chapter.blocks.last as ParagraphBlock).text, 'Tail');
    });
  }

  for (final (name, content) in [
    (
      'display none',
      '<p class="line" style="display:none"><br style="visibility:visible"/></p>',
    ),
    ('HTML hidden', '<p class="line" hidden="hidden"><br/></p>'),
    (
      'visibility hidden',
      '<p class="line" style="visibility:hidden"><br/></p>',
    ),
    ('hidden break', '<p class="line"><br style="visibility:hidden"/></p>'),
    ('no break', '<p class="line"> \n </p>'),
  ]) {
    test('$name does not create a decoration block', () {
      final blocks = authoredContent(
        '<div style="width:14em">$content<p>Tail</p></div>',
        blankBorderCss,
      ).chapters.first.blocks;
      expect(blocks.length, 1);
      expect((blocks.single as ParagraphBlock).text, 'Tail');
    });
  }
  test('a restored break does not make its hidden paragraph border visible', () {
    final gap =
        authoredContent(
              '<div style="width:14em"><p class="line" style="visibility:hidden">'
              '<br style="visibility:visible"/></p><p>Tail</p></div>',
              blankBorderCss,
            ).chapters.first.blocks.first
            as ParagraphBlock;
    expect(gap.authoredGapEm, 1);
    expect(gap.layout, isNull);
  });
  test('a visible paragraph can recover inside a hidden outer container', () {
    final gap =
        authoredContent(
              '<div style="width:14em;visibility:hidden"><p class="line" style="visibility:visible">'
              '<br/></p></div><p>Tail</p>',
              blankBorderCss,
            ).chapters.first.blocks.first
            as ParagraphBlock;
    expect(gap.authoredGapEm, 1);
    expect(gap.layout!.borders!.top!.width.value, 1);
  });
}
