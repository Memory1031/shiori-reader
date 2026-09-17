import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

void main() {
  final key = LocalBookIdentity.book('a' * 64);
  LocalBookContent parse(String body, String css) {
    final files = epubFiles();
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><head><style>$css</style></head><body>$body</body></html>',
    );
    return EpubParser(zipFiles(files), key, 'rich.epub').parse().content;
  }

  test(
    'nested relative styles preserve code point offsets, links and identity',
    () {
      final content = parse(
        '<p id="one">😀<span class="color">甲<a href="#one"><b style="font-size:125%">乙<i>丙</i></b></a></span>丁</p>',
        'body {font-size:32px} p {font-size:1em;line-height:120%;margin:1em} .color {font-size:.8em;color:#9161a4}',
      );
      final chapter = content.chapters.first;
      final block = chapter.blocks.single as ParagraphBlock;
      expect(block.text, '😀甲乙丙丁');
      expect(block.inlineStyles.map((s) => s.start), [1, 2, 3]);
      expect(block.inlineStyles.map((s) => s.fontScale), [.8, 1, 1]);
      expect(block.inlineStyles.last.italic, isTrue);
      expect(block.inlineStyles.last.bold, isTrue);
      expect(block.inlineStyles.last.color, 0xff9161a4);
      expect(content.links.single.sourceOffset, 2);
      expect(content.links.single.sourceLength, 2);
      expect(block.blockKey, ParagraphBlock(text: block.text).blockKey);
      expect(ChapterContent.fromJson(chapter.toJson()), chapter);
    },
  );
  test('decorated containers retain shared membership and reset on exit', () {
    final chapter = parse(
      '<div class="card"><div><b>角色</b></div><hr/><div>介绍</div></div><p>普通正文</p><div class="other">旁白</div>',
      '.card {width:200px;max-width:240px;padding:5px;border:1px #dccedf solid;background-color:#fefafb;font-size:.8em;color:#000} .other {width:130px;padding:3px;border:2px #905ca3 dashed;color:#905ca3}',
    ).chapters.first;
    expect(chapter.blocks.take(3).map((b) => b.box?.group), [0, 0, 0]);
    expect(chapter.blocks[3].box, isNull);
    expect(chapter.blocks[4].box!.group, 1);
    expect(chapter.blocks[4].box!.dashed, isTrue);
    final box = chapter.blocks.first.box!;
    expect(box.width, 200);
    expect(box.padding, 5);
    expect(box.borderColor, 0xffdccedf);
    expect(box.backgroundColor, 0xfffefafb);
    expect(ChapterContent.fromJson(chapter.toJson()), chapter);
  });
  test(
    'CSS cascade, normal reset, px sizes and invalid values remain bounded',
    () {
      final block = parse(
        '<p><strong class="a">A<span style="font-weight:normal;font-style:normal;font-size:17.6px;color:rgb(239,131,3)">B</span></strong><span style="font-size:999999em;color:url(x)">C</span></p>',
        '.a {color:red!important;font-style:italic}.a {color:blue}',
      ).chapters.first.blocks.single;
      expect(block.inlineStyles.first.color, 0xffff0000);
      expect(block.inlineStyles[1].fontScale, closeTo(1.1, .00001));
      expect(block.inlineStyles[1].bold, isFalse);
      expect(block.inlineStyles[1].italic, isFalse);
      expect(block.inlineStyles[1].color, 0xffef8303);
      expect(block.inlineStyles.last.fontScale, 4);
    },
  );
  test(
    'percentage box widths stay relative; neutral prose colors follow reader theme',
    () {
      final chapter = parse(
        '<p style="color:black">普通</p><div style="width:80%;max-width:90%;padding:4px;border:1px solid red;background-color:white;color:black">框内</div>',
        '',
      ).chapters.first;
      expect(chapter.blocks.first.inlineStyles.single.color, isNull);
      final box = chapter.blocks.last.box!;
      expect(box.width, isNull);
      expect(box.widthFraction, .8);
      expect(box.maxWidthFraction, .9);
      expect(chapter.blocks.last.inlineStyles.single.color, 0xff000000);
      expect(ChapterContent.fromJson(chapter.toJson()), chapter);
    },
  );
  test('document backgrounds never become authored block backgrounds', () {
    final chapter = parse(
      '<div>Plain</div><div class="card">Card</div>',
      'html, body {background-color:#fef7ff} .card {background-color:#fefafb}',
    ).chapters.first;
    expect(chapter.blocks.first.box, isNull);
    expect(chapter.blocks.last.box!.backgroundColor, 0xfffefafb);
  });
  test('malformed style metadata is rejected; old JSON remains readable', () {
    final old = ParagraphBlock(text: 'AB');
    expect(ContentBlock.fromJson(old.toJson()), old);
    expect(
      () => ParagraphBlock(
        text: 'AB',
        inlineStyles: [InlineTextStyle(start: 1, length: 2)],
      ),
      throwsArgumentError,
    );
    expect(
      () => InlineTextStyle(start: 0, length: 1, fontScale: double.nan),
      throwsArgumentError,
    );
    expect(
      () => BlockBox(group: 0, width: double.infinity),
      throwsArgumentError,
    );
  });
}
