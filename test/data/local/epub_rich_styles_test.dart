import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/bookmark_position.dart';
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
    'inline borders retain source ranges, cascade, links and semantic identity',
    () {
      const body =
          '<p id="one">😀e\u0301<span class="signal">甲<b>乙</b><a href="#one"><i>丙</i></a></span>丁</p>';
      final plain = parse(body, '');
      final content = parse(
        body,
        '.signal {border-bottom:2px dotted #000;padding-bottom:2px}',
      );
      final block = content.chapters.first.blocks.single as ParagraphBlock;
      final ranges = block.inlineStyles
          .where((s) => s.borderBottom != null)
          .toList();
      expect(block.text, '😀e\u0301甲乙丙丁');
      expect(ranges.map((s) => s.start), [3, 4, 5]);
      expect(
        ranges.every(
          (s) =>
              s.length == 1 && s.borderBottom!.style == BoxBorderStyle.dotted,
        ),
        isTrue,
      );
      expect(ranges.first.borderBottom!.width, LayoutLength(2));
      expect(ranges.first.borderBottom!.color, isNull);
      expect(ranges[1].bold, isTrue);
      expect(ranges[2].italic, isTrue);
      expect(block.blockKey, plain.chapters.first.blocks.single.blockKey);
      expect(
        content.chapters.first.contentRevision,
        plain.chapters.first.contentRevision,
      );
      expect(
        content.links.map((l) => l.toJson()).toList(),
        plain.links.map((l) => l.toJson()).toList(),
      );
      expect(
        ChapterContent.fromJson(content.chapters.first.toJson()),
        content.chapters.first,
      );
      expect(
        InlineTextStyle.fromJson({
          'start': 0,
          'length': 1,
          'color': null,
          'fontScale': 1,
          'bold': null,
          'italic': null,
        }).borderBottom,
        isNull,
      );
    },
  );
  for (final (css, expected) in [
    (
      'border-bottom:1px solid red;border-bottom-style:dashed',
      BoxBorderStyle.dashed,
    ),
    (
      'border-bottom-style:solid;border-bottom-width:.1em;border-bottom-color:blue',
      BoxBorderStyle.solid,
    ),
    (
      'border-bottom:2px dotted black!important;border-bottom-style:solid',
      BoxBorderStyle.dotted,
    ),
    ('border-bottom:2px dotted black;border-bottom:none', null),
    ('border-bottom:0 dotted black', null),
    ('border-bottom:9px dotted black', null),
    ('border-bottom:1em dotted black', null),
    ('border-bottom:2px double black', null),
    ('border-bottom:2px dotted transparent', null),
  ]) {
    test('bounded inline border cascade: $css', () {
      final block =
          parse(
                '<p><span style="$css">Text</span></p>',
                '',
              ).chapters.first.blocks.single
              as ParagraphBlock;
      expect(block.inlineStyles.firstOrNull?.borderBottom?.style, expected);
    });
  }
  test('block borders do not become inline decorations', () {
    final block =
        parse(
              '<p style="border-bottom:2px dotted black">A<span>B</span></p>',
              '',
            ).chapters.first.blocks.single
            as ParagraphBlock;
    expect(block.box!.borders!.bottom!.style, BoxBorderStyle.dotted);
    expect(block.inlineStyles.every((s) => s.borderBottom == null), isTrue);
    expect(
      () => InlineTextStyle(
        start: 0,
        length: 1,
        borderBottom: BoxBorderSide(width: LayoutLength(9)),
      ),
      throwsArgumentError,
    );
  });

  test(
    'explicit superscripts preserve text identity and ordinary link routing',
    () {
      const body =
          '<p id="one">😀e\u0301<a href="#one"><span class="up">[12]</span></a>'
          '<sup>甲</sup><sup style="vertical-align:baseline">乙</sup>1</p>';
      final content = parse(body, '.up {font-size:.75em;vertical-align:super}');
      final block = content.chapters.first.blocks.single as ParagraphBlock;
      expect(block.text, '😀e\u0301[12]甲乙1');
      final raised = block.inlineStyles.where((s) => s.superscript).toList();
      expect(raised.map((s) => s.start), [3, 7]);
      expect(raised.map((s) => s.fontScale), [.75, .75]);
      expect(content.links.single.isFootnote, isFalse);
      expect(content.links.single.sourceOffset, 3);
      expect(content.links.single.sourceLength, 4);
      expect(content.links.single.targetBlockKey, block.blockKey);
      final plain = parse(body, '.up {font-size:.75em}');
      expect(
        content.chapters.first.contentRevision,
        plain.chapters.first.contentRevision,
      );
      final position = ReaderPosition(
        contentRevision: plain.chapters.first.contentRevision,
        blockKey: block.blockKey,
        blockIndex: 0,
        blockFraction: 4 / block.text.runes.length,
        chapterFraction: 4 / block.text.runes.length,
      );
      final anchor = BookmarkPositionIndex(
        plain.chapters,
      ).capture(plain.chapters.first.key, position)!;
      final restored = BookmarkPositionIndex(
        content.chapters,
      ).resolve(content.chapters.first.key, anchor);
      expect(restored.location, BookmarkLocation.exact);
      expect(restored.anchor!.position, anchor.position);

      expect(
        ChapterContent.fromJson(content.chapters.first.toJson()),
        content.chapters.first,
      );
      final legacy = InlineTextStyle(start: 0, length: 1).toJson();
      expect(legacy.containsKey('superscript'), isFalse);
      expect(InlineTextStyle.fromJson(legacy).superscript, isFalse);
    },
  );
  test(
    'superscript children retain baseline intent without repeated shrinking',
    () {
      final block =
          parse(
                '<p><sup><b>A</b><i>B</i></sup><span style="vertical-align:super">C</span>D</p>',
                '',
              ).chapters.first.blocks.single
              as ParagraphBlock;
      expect(block.inlineStyles.map((s) => s.fontScale), [.75, .75, 1]);
      expect(block.inlineStyles.every((s) => s.superscript), isTrue);
      expect(
        parse(
          '<p style="vertical-align:super">Body</p>',
          '',
        ).chapters.first.blocks.single.inlineStyles,
        isEmpty,
      );
    },
  );

  test('deep superscript nesting stays within typography bounds', () {
    final block = parse(
      '<p>${'<sup>' * 20}A${'</sup>' * 20}</p>',
      '',
    ).chapters.first.blocks.single;
    expect(block.inlineStyles.single.fontScale, .25);
    expect(block.inlineStyles.single.superscript, isTrue);
  });

  test('ordinary prose preserves consecutive explicit blank paragraphs', () {
    final content = parse(
      '<p>A</p><p id="gap"><br/></p><p><br/></p>'
          '<p id="after">B</p><p><a href="#gap">Gap</a> '
          '<a href="#after">After</a></p>',
      '',
    );
    final chapter = content.chapters.first;
    final blocks = chapter.blocks.cast<ParagraphBlock>();
    expect(blocks.map((b) => b.text), ['A', '', '', 'B', 'Gap After']);
    expect(blocks.map((b) => b.authoredGapEm), [null, 1, 1, null, null]);
    expect(blocks.every((b) => b.box == null), isTrue);
    expect(blocks[1].blockKey, isNot(blocks[2].blockKey));
    expect(content.links[0].targetBlockKey, blocks[1].blockKey);
    expect(content.links[1].targetBlockKey, blocks[3].blockKey);
    expect(
      content.links.every((l) => l.sourceBlockKey == blocks[4].blockKey),
      isTrue,
    );
    expect(ChapterContent.fromJson(chapter.toJson()), chapter);
  });
  for (final (name, between) in [
    ('source indentation', '\n   \t\n'),
    ('empty paragraph', '<p> \n\t </p>'),
    ('display none', '<p style="display:none"><br/></p>'),
    ('hidden attribute', '<p hidden="hidden"><br/></p>'),
    (
      'inherited visibility',
      '<div style="visibility:hidden"><p><br/></p></div>',
    ),
    ('collapsed visibility', '<p style="visibility:collapse"><br/></p>'),
    ('hidden inline break', '<p><br style="visibility:hidden"/></p>'),
  ]) {
    test('$name does not create an authored blank paragraph', () {
      final blocks = parse(
        '<p>A</p>$between<p>B</p>',
        '',
      ).chapters.first.blocks.cast<ParagraphBlock>();
      expect(blocks.map((b) => b.text), ['A', 'B']);
      expect(blocks.every((b) => b.authoredGapEm == null), isTrue);
    });
  }
  test('inline br remains inside a nonempty paragraph without extra gaps', () {
    final block =
        parse('<p>A<br/>B</p>', '').chapters.first.blocks.single
            as ParagraphBlock;
    expect(block.text, 'A\nB');
    expect(block.authoredGapEm, isNull);
  });
  test('ordinary authored gaps retain relative scale and the safety bound', () {
    final chapter = parse(
      '<p>A</p><p style="font-size:.4em"><br/></p>'
          '<p>${'<br/>' * 20}</p><p>B</p>',
      '',
    ).chapters.first;
    final blocks = chapter.blocks.cast<ParagraphBlock>();
    expect(blocks.map((b) => b.text), ['A', '', '', 'B']);
    expect(blocks[1].authoredGapEm, .4);
    expect(blocks[2].authoredGapEm, 16);
    expect(blocks.every((b) => b.box == null), isTrue);
    expect(ChapterContent.fromJson(chapter.toJson()), chapter);
  });

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
      expect(block.inlineStyles.map((s) => s.start), [0, 1, 2, 3, 4]);
      expect(block.inlineStyles.map((s) => s.fontScale), [1, .8, 1, 1, 1]);
      expect(block.inlineStyles[3].italic, isTrue);
      expect(block.inlineStyles[3].bold, isTrue);
      expect(block.inlineStyles[3].color, 0xff9161a4);
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
  test('contents container keeps auto centering independently of its text', () {
    const body =
        '<div class="box" style="margin:0 auto"><div>'
        '<p>CONTENTS</p><p><a href="#start">序章</a></p>'
        '</div></div><p id="start">正文</p>';
    const css =
        '.box {width:19em;max-width:100%;margin:auto}'
        '.box p {text-align:center}';
    final content = parse(body, css);
    final chapter = content.chapters.first;
    final box = chapter.blocks.first.box!;
    expect(box.centered, isTrue);
    expect(box.width, isNull);
    expect(box.widthLength, LayoutLength(19, LayoutUnit.em));
    expect(box.maxWidthFraction, 1);
    expect(chapter.blocks[1].box, box);
    expect(
      (chapter.blocks.first as ParagraphBlock).alignment,
      ParagraphAlignment.center,
    );
    expect(chapter.blocks.last.box, isNull);
    expect(content.links.single.label, '序章');
    expect(ChapterContent.fromJson(chapter.toJson()), chapter);
    final left = parse(
      body.replaceAll('margin:0 auto', 'margin:0'),
      css,
    ).chapters.first;
    expect(left.blocks.first.box!.centered, isFalse);
    expect(left.contentRevision, chapter.contentRevision);
    expect(left, isNot(chapter));
  });
  for (final (style, centered) in [
    ('margin:auto', true),
    ('margin:1em auto', true),
    ('margin:1em auto 2em', true),
    ('margin:1em auto 2em auto', true),
    ('margin-left:auto;margin-right:auto', true),
    ('margin:auto;margin-left:0', false),
    ('margin-left:0;margin:auto', true),
    ('margin:auto!important;margin-right:0', true),
    ('margin-right:0!important;margin:auto', false),
    ('margin:auto;margin:invalid', true),
    ('margin:auto;margin:0 0 0 0 0', true),
    ('margin:auto;margin:initial', false),
    ('margin-left:auto', false),
    ('margin:0 auto 0 1em', false),
    ('text-align:center', false),
  ]) {
    test('box centering follows margin cascade: $style', () {
      final block = parse(
        '<div style="width:200px;$style">Content</div>',
        '',
      ).chapters.first.blocks.single;
      expect(block.box!.centered, centered);
    });
  }
  test('stylesheet priority survives inline margin shorthand', () {
    final block = parse(
      '<div class="box" style="margin:0 auto">Content</div>',
      '.box {width:200px;margin-left:0!important}',
    ).chapters.first.blocks.single;
    expect(block.box!.centered, isFalse);
  });
  test('old box JSON defaults to left alignment', () {
    final box = BlockBox(group: 0, width: 304);
    final old = box.toJson()..remove('centered');
    expect(BlockBox.fromJson(old), box);
    expect(BlockBox.fromJson(old).centered, isFalse);
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
      expect(chapter.blocks.first.inlineStyles, isEmpty);
      final box = chapter.blocks.last.box!;
      expect(box.width, isNull);
      expect(box.widthFraction, .8);
      expect(box.maxWidthFraction, .9);
      expect(chapter.blocks.last.inlineStyles.single.color, 0xff000000);
      expect(ChapterContent.fromJson(chapter.toJson()), chapter);
    },
  );
  test('neutral inherited color is no-op, explicit resets and gaps survive', () {
    final chapter = parse(
      '<h1>Title</h1><p><strong>A<span style="font-weight:normal">B</span></strong></p>'
          '<div class="card"><div>One</div><div style="font-size:.4em"><br/></div><div>Two</div></div>',
      'body {color:black} .card {border:1px solid red}',
    ).chapters.first;
    expect(chapter.blocks.first.inlineStyles, isEmpty);
    expect(chapter.blocks[1].inlineStyles.first.bold, isTrue);
    expect(chapter.blocks[1].inlineStyles.last.bold, isFalse);
    expect(chapter.blocks[1].inlineStyles.last.italic, isNull);
    final gap = chapter.blocks[3] as ParagraphBlock;
    expect(gap.authoredGapEm, .4);
    expect(gap.text, isEmpty);
    expect(gap.box!.group, chapter.blocks[2].box!.group);
    expect(ChapterContent.fromJson(chapter.toJson()), chapter);
  });
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
