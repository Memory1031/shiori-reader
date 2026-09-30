import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_rich_styles.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

LocalBookContent authoredContent(String body, [String css = '']) {
  final files = epubFiles();
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><head><style>$css</style></head><body>$body</body></html>',
  );
  return EpubParser(
    zipFiles(files),
    LocalBookIdentity.book('a' * 64),
    'synthetic.epub',
  ).parse().content;
}

void main() {
  test('whole native link decoration accepts a/span and preserves ranges', () {
    for (final label in [
      '<a href="#target" style="background-color:#544f65;color:white;border-radius:30px;padding:.3em">Label</a>',
      '<a href="#target"><span style="background-color:#544f65;color:white;border-radius:30px;padding:.3em">Label</span></a>',
    ]) {
      final content = authoredContent(
        '<p style="text-align:center">$label</p><p id="target">Target</p>',
      );
      final block = content.chapters.first.blocks.first as ParagraphBlock;
      expect(block.text, 'Label');
      expect(block.linkDecoration!.backgroundColor, 0xff544f65);
      expect(
        block.linkDecoration!.padding.top,
        LayoutLength(.3, LayoutUnit.em),
      );
      expect(block.inlineStyles.single.color, 0xffffffff);
      expect(content.links.single.sourceOffset, 0);
      expect(content.links.single.sourceLength, 5);
      expect(
        block.blockKey,
        ParagraphBlock(
          text: 'Label',
          alignment: ParagraphAlignment.center,
        ).blockKey,
      );
      expect(block.withOccurrence(1).linkDecoration, block.linkDecoration);
      expect(
        ChapterContent.fromJson(content.chapters.first.toJson()),
        content.chapters.first,
      );
    }
    for (final label in [
      'Plain <a href="#target"><span style="background-color:red">Label</span></a>',
      '<a href="#target" style="background-color:red">One</a><a href="#target">Two</a>',
      '<a href="#target"><span style="background-color:url(x);color:white">Label</span></a>',
      '<a href="#target" style="background-color:red"><ruby>A<rt>B</rt></ruby></a>',
    ]) {
      final block =
          authoredContent(
                '<p>$label</p><p id="target">Target</p>',
              ).chapters.first.blocks.first
              as ParagraphBlock;
      expect(block.linkDecoration, isNull);
      expect(block.text, isNotEmpty);
    }
  });
  test(
    'side cascade respects shorthand order, important and invisible sides',
    () {
      BlockBox box(String css) => authoredContent(
        '<div style="$css">Text</div>',
      ).chapters.first.blocks.single.box!;
      final two = box(
        'border-width:6px;border-style:ridge groove none hidden;border-color:#4682b4',
      );
      expect(two.borders!.top!.style, BoxBorderStyle.solid);
      expect(two.borders!.right!.style, BoxBorderStyle.solid);
      expect(two.borders!.bottom!.width.value, 0);
      expect(two.borders!.left!.width.value, 0);
      final bottom = box('border-width:4px;border-bottom-style:solid');
      expect(bottom.borders!.top!.style, BoxBorderStyle.none);
      expect(bottom.borders!.bottom!.width.value, 4);
      expect(
        box(
          'border:2px solid red;border-right:3px dashed blue',
        ).borders!.right!.width.value,
        3,
      );
      expect(
        box(
          'border-right:3px dashed blue;border:2px solid red',
        ).borders!.right!.width.value,
        2,
      );
      expect(
        box(
          'border-right:3px dashed blue!important;border:2px solid red',
        ).borders!.right!.style,
        BoxBorderStyle.dashed,
      );
      final sides = box('border-style:solid;border-width:1px 2px 3px 4px');
      expect(
        [
          sides.borders!.top!.width.value,
          sides.borders!.right!.width.value,
          sides.borders!.bottom!.width.value,
          sides.borders!.left!.width.value,
        ],
        [1, 2, 3, 4],
      );
      final legacy = BlockBox(
        group: 0,
        borderWidth: 2,
        borderColor: 0xff000000,
      );
      final old = legacy.toJson()..remove('borders');
      expect(BlockBox.fromJson(old), legacy);
    },
  );
  test(
    'image geometry and dl grouping survive serialization without extra text',
    () {
      final chapter = authoredContent(
        '<div style="margin-top:36%"><img src="../images/%E6%98%9F%20%E7%A9%BA.png"/></div>'
        '<dl style="border-bottom:2px solid black;margin:0 2% 0 32%;padding-right:6%"><dt>Maker</dt><dd>Name</dd></dl>'
        '<hr style="width:50%;margin:0 auto"/><p>After</p>',
      ).chapters.first;
      expect(chapter.blocks.first, isA<ImageBlock>());
      final picture = authoredContent(
        '<div style="margin-top:36%"><picture>'
        '<img src="../images/%E6%98%9F%20%E7%A9%BA.png"/>'
        '</picture></div>',
      ).chapters.first;
      expect(picture.blocks.single, isA<ImageBlock>());
      expect(
        picture.blocks.single.box!.margins!.top,
        LayoutLength(.36, LayoutUnit.fraction),
      );
      expect(
        chapter.blocks.first.box!.margins!.top,
        LayoutLength(.36, LayoutUnit.fraction),
      );
      expect(chapter.blocks[1].box, chapter.blocks[2].box);
      expect(chapter.blocks[1].box!.borders!.bottom!.width.value, 2);
      expect(chapter.blocks[3].layout!.widthFraction, .5);
      expect(ChapterContent.fromJson(chapter.toJson()), chapter);
      expect(
        chapter.blocks.first.withOccurrence(1).box,
        chapter.blocks.first.box,
      );
    },
  );
  test('all absolute keywords use medium; em and percent use parent', () {
    for (final entry in {
      'xx-small': 3 / 5,
      'x-small': 3 / 4,
      'small': 8 / 9,
      'medium': 1.0,
      'large': 6 / 5,
      'x-large': 3 / 2,
      'xx-large': 2.0,
      'xxx-large': 3.0,
    }.entries) {
      expect(epubFontScale(entry.key, 3), entry.value);
    }
    expect(epubFontScale('.8em', 3), closeTo(2.4, 1e-10));
    expect(epubFontScale('80%', 3), closeTo(2.4, 1e-10));
    expect(epubFontScale('calc(1em + 2px)', 3), isNull);
  });
  test('block provenance, child inheritance and serialization keep identity', () {
    final chapter = authoredContent(
      '<h1>A<span style="color:red">B</span></h1>'
      '<h1 style="font-size:xxx-large">C<span style="color:red">D</span>'
      '<span style="font-size:medium">E</span><span style="font-size:.8em">F</span></h1>'
      '<h1>G<span style="font-size:.8em">H</span></h1>'
      '<h1 style="font-size:medium">I</h1><p>End</p>',
    ).chapters.first;
    final h = chapter.blocks.whereType<HeadingBlock>().toList();
    expect(h.map((b) => b.hasAuthoredFontSize), [false, true, false, true]);
    expect(h[0].inlineStyles.single.fontScale, 1);
    expect(h[0].inlineStyles.single.fontSizeFromReader, isFalse);
    expect(h[1].inlineStyles.map((s) => s.fontScale), [
      3,
      3,
      1,
      closeTo(2.4, 1e-10),
    ]);
    expect(h[2].inlineStyles.single.fontSizeFromReader, isFalse);
    expect(h[3].inlineStyles.single.fontSizeFromReader, isTrue);
    expect(ChapterContent.fromJson(chapter.toJson()), chapter);
    expect(h[1].withOccurrence(2).hasAuthoredFontSize, isTrue);
    expect(h[3].blockKey, HeadingBlock(text: 'I').blockKey);
    expect(
      ContentBlock.fromJson(
        HeadingBlock(text: 'Old').toJson(),
      ).hasAuthoredFontSize,
      isFalse,
    );
  });
}
