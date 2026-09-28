import 'package:shiori/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'epub_prose_semantics_test.dart' show paragraphs;

void main() {
  test(
    'inherited indent uses the declaring font size rather than child size',
    () {
      final blocks = paragraphs(
        '<div style="font-size:2em;text-indent:-3em"><p style="font-size:.5em;margin-left:3em">A</p><p style="font-size:.5em;margin-left:6em">B</p></div>',
      );
      expect(blocks.first.hangingIndentEm, isNull);
      expect(blocks.last.hangingIndentEm, 6);
    },
  );
  test('cascade, important, resets, inherited indent and local margins', () {
    final blocks = paragraphs('''<style>
      .x { margin-left:3em; text-indent:-3em !important }
      .x { margin:0 0 0 7em; text-indent:-7em !important }
      .reset { margin-left:initial !important }
      </style>
      <div class="x" style="text-indent:-3em">A</div>
      <div class="x reset">B</div>
      <div style="text-indent:-3em"><p style="margin-left:3em">C</p><p>D</p></div>
      <p style="margin-left:7em;text-indent:initial">E</p>
      <p style="text-indent:2em">F</p>
      <div style="margin-left:7em;text-indent:-7em"><p>G</p></div>
      ''');
    expect(blocks.map((b) => b.hangingIndentEm), [
      7,
      null,
      3,
      null,
      null,
      null,
      null,
    ]);
    expect(blocks.last.leadingIndent, 0);
    expect(blocks[5].leadingIndent, 2);
  });
  test('normalized suffix offsets, hidden and unsupported floats preserve text', () {
    const css =
        '<style>.entry {margin-left:3em;text-indent:-3em;clear:both}.meta {float:right;text-indent:0}</style>';
    for (final hidden in [
      'hidden',
      'style="display:none"',
      'style="visibility:hidden"',
    ]) {
      final block = paragraphs(
        '$css<div class="entry">Body<span class="meta" $hidden>secret</span></div>',
      ).single;
      expect(block.text, 'Body');
      expect(block.trailingLabelStart, isNull);
    }
    for (final inner in [
      '<span class="meta">label</span>Tail',
      '<span class="meta">one</span><span class="meta">two</span>',
      '<span class="meta"><b>nested</b></span>',
      '<span class="meta"></span>Tail',
      '<span class="meta">${'x' * 65}</span>',
      '<span class="meta" style="float:left">left</span>',
      '<span class="meta" style="text-indent:1em">indent</span>',
    ]) {
      final block = paragraphs(
        '$css<div class="entry">Body$inner</div>',
      ).single;
      final flat = paragraphs('<div>Body$inner</div>').single;
      expect(block.text, flat.text);
      expect(block.trailingLabelStart, isNull);
    }
    final block = paragraphs(
      '$css<div class="entry">  😀é　<a href="#a">链接</a><br/>后文<span class="meta" style="color:red"> 标签😀 </span>  </div>',
    ).single;
    expect(
      String.fromCharCodes(block.text.runes.skip(block.trailingLabelStart!)),
      ' 标签😀',
    );
    expect(block.inlineStyles.last.start, block.trailingLabelStart);
    expect(block.text.startsWith('😀é　链接\n后文'), isTrue);
    final noClear = paragraphs(
      '<div>Body<span style="float:right;text-indent:0">label</span></div>',
    ).single;
    expect(noClear.text, 'Bodylabel');
    expect(noClear.trailingLabelStart, isNull);
  });
  test('directional and unsupported geometry fall back safely', () {
    for (final extra in [
      'dir="rtl"',
      'dir="auto"',
      'style="direction:rtl"',
      'style="writing-mode:vertical-rl"',
      'style="display:flex"',
    ]) {
      final block = paragraphs(
        '<style>.entry {margin-left:7em;text-indent:-7em;clear:both}</style><div class="entry" $extra>Body<span style="float:right;text-indent:0">label</span></div>',
      ).single;
      expect(block.text, 'Bodylabel');
      expect(block.hangingIndentEm, isNull);
      expect(block.trailingLabelStart, isNull);
    }
    for (final margin in ['50%', 'calc(3em + 1px)', '40em', '7em']) {
      final block = paragraphs(
        '<p style="margin-left:$margin;text-indent:-3em">Text</p>',
      ).single;
      expect(block.hangingIndentEm, isNull);
    }
  });
  test('metadata round trips without changing semantic identity', () {
    final plain = ParagraphBlock(text: '甲😀é正文label');
    final styled = ParagraphBlock(
      text: plain.text,
      hangingIndentEm: 7,
      trailingLabelStart: plain.text.runes.length - 5,
    );
    expect(styled.blockKey, plain.blockKey);
    expect(styled, isNot(plain));
    expect(ContentBlock.fromJson(styled.toJson()), styled);
    expect(ContentBlock.fromJson(plain.toJson()), plain);
    expect(styled.withOccurrence(3).hangingIndentEm, 7);
    expect(
      styled.withOccurrence(3).trailingLabelStart,
      styled.trailingLabelStart,
    );
    for (final invalid in [0, -1, 33, double.nan, double.infinity]) {
      expect(
        () => ContentBlock.fromJson({
          ...plain.toJson(),
          'hangingIndentEm': invalid,
        }),
        throwsArgumentError,
      );
    }
    for (final invalid in [-1, 0, 3, plain.text.runes.length, 99]) {
      expect(
        () => ContentBlock.fromJson({
          ...plain.toJson(),
          'trailingLabelStart': invalid,
        }),
        throwsArgumentError,
      );
    }
  });
  test('synthetic hanging paragraph retains source and authored geometry', () {
    for (final em in [3, 7]) {
      final block = paragraphs('''
<style>.entry { margin-left:${em}em; text-indent:-${em}em; clear:both }
.entry > .meta { float:right; text-indent:0 }</style>
<div class="entry"><span>甲同学　　〈正文😀é<br/>续行〉</span><span class="meta">-09:41</span></div>
''').single;
      expect(block.text, '甲同学　　〈正文😀é\n续行〉-09:41');
      expect(block.leadingIndent, 0);
      expect(block.toJson()['hangingIndentEm'], em.toDouble());
      expect(block.toJson()['trailingLabelStart'], block.text.runes.length - 6);
    }
  });
}
