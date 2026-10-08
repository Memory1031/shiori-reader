import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'epub_structure_test.dart' show parse;
import 'support/epub_fixtures.dart';

const stackStyle =
    'display:inline-block;text-align:center;text-indent:0;line-height:1em';
ChapterContent stackedChapter(String body, {String css = ''}) {
  final files = epubFiles();
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><head><style>$css</style></head><body>$body</body></html>',
  );
  return parse(files).content.chapters.first;
}

void main() {
  test(
    'effective CSS creates source-preserving stacks with inherited fixed line height',
    () {
      const body =
          '<p>😀前「<span class="unit"><b style="font-size:.68em">SAMPLE</b><br/>示例</span>」<span class="unit">上层中文<br/><i>Code42</i></span>尾<a href="b.xhtml">后链</a></p>';
      final c = stackedChapter(body, css: '.unit{$stackStyle}');
      final b = c.blocks.single as ParagraphBlock;
      final old = stackedChapter(
        body,
        css: '.unit{$stackStyle;display:inline}',
      );
      expect(b.text, (old.blocks.single as ParagraphBlock).text);
      expect(b.blockKey, old.blocks.single.blockKey);
      expect(c.contentRevision, old.contentRevision);
      expect(
        b.inlineStyles,
        (old.blocks.single as ParagraphBlock).inlineStyles,
      );
      expect(b.inlineStacks, hasLength(2));
      expect(b.inlineStacks.first.start, 3);
      expect(b.inlineStacks.first.separator, 9);
      expect(b.inlineStacks.first.upperLineHeightEm, 1);
      expect(b.inlineStacks.first.lowerLineHeightEm, 1);
      expect(ContentBlock.fromJson(b.toJson()), b);
      expect(b.withOccurrence(4).inlineStacks, b.inlineStacks);
      final json = b.toJson()..remove('inlineStacks');
      expect(ContentBlock.fromJson(json).inlineStacks, isEmpty);
      expect(ContentBlock.fromJson(json).blockKey, b.blockKey);
    },
  );
  test('inline declarations, inherited centering, override and unitless height', () {
    final c = stackedChapter(
      '<p style="text-align:center;text-indent:0"><span style="display:inline-block;line-height:1.2"><span style="font-size:.68em">上</span><br/>下</span></p>',
    );
    final s = c.blocks.single.inlineStacks.single;
    expect(s.upperLineHeightEm, closeTo(.816, 1e-8));
    expect(s.upperLineHeightBasisEm, .68);
    expect(s.lowerLineHeightEm, 1.2);
    expect(ContentBlock.fromJson(c.blocks.single.toJson()), c.blocks.single);
    expect(
      stackedChapter(
        '<p><span style="display:inline-block;text-align:center;text-indent:0;line-height:2"><span style="font-size:.68em">上</span>大<br/>下</span></p>',
      ).blocks.single.inlineStacks,
      isEmpty,
    );
    expect(
      stackedChapter(
        '<p><span class="x">上<br/>下</span></p>',
        css: '.x{$stackStyle}.x{display:inline!important}',
      ).blocks.single.inlineStacks,
      isEmpty,
    );
    expect(
      stackedChapter(
        '<h3><span style="$stackStyle">上<br/>下</span></h3>',
      ).blocks.single.inlineStacks,
      hasLength(1),
    );
    for (final height in ['0', 'calc(1em + 2px)', '9em']) {
      expect(
        stackedChapter(
          '<p><span style="$stackStyle;line-height:$height">上<br/>下</span></p>',
        ).blocks.single.inlineStacks,
        isEmpty,
        reason: height,
      );
    }
    expect(
      stackedChapter(
        '<p><span style="$stackStyle;line-height:bogus">上<br/>下</span></p>',
      ).blocks.single.inlineStacks.single.upperLineHeightEm,
      1,
    );
  });
  test('visibility is distinct from display suppression', () {
    final b =
        stackedChapter(
              '<p>前<span style="$stackStyle;visibility:hidden">secret<span style="visibility:visible">上<br/>下</span>secret</span><span style="display:none">gone<br/></span>后</p>',
            ).blocks.single
            as ParagraphBlock;
    expect(b.text, '前上\n下后');
    expect(b.inlineStacks, hasLength(1));
    expect(
      stackedChapter(
        '<p>前<span style="$stackStyle;display:none">上<br/>下</span>后</p>',
      ).blocks.single.inlineStacks,
      isEmpty,
    );
  });
  test('layout admission preserves later link and footnote source ranges', () {
    final files = epubFiles();
    const body =
        '<html><body><p><a href="#note">前链</a>😀<span style="$stackStyle"><span style="font-size:.68em">SAMPLE</span><br/>示例</span><a href="#note">后链</a><sup><a href="#note">1</a></sup></p><aside id="note" epub:type="footnote">合成注释。</aside></body></html>';
    files['OPS/text/a.xhtml'] = utf8.encode(body);
    final current = parse(files).content;
    files['OPS/text/a.xhtml'] = utf8.encode(
      body.replaceAll('display:inline-block', 'display:inline'),
    );
    final previous = parse(files).content;
    expect(
      current.chapters.first.contentRevision,
      previous.chapters.first.contentRevision,
    );
    expect(
      current.links.map((l) => l.toJson()),
      previous.links.map((l) => l.toJson()),
    );
    expect(current.links.map((l) => l.label), containsAll(['前链', '后链', '1']));
  });
  test('unsupported containers preserve the existing text and interactions', () {
    for (final inner in [
      '上<br/>中<br/>下',
      '<span style="display:inline-block">上</span><br/>下',
      '上<br/><ruby>下<rt>注</rt></ruby>',
      '上<br/><img src="missing"/>下',
      '<a href="b.xhtml">上</a><br/>下',
      '<div>上</div><br/>下',
    ]) {
      final a = stackedChapter(
        '<p>前<span style="$stackStyle">$inner</span>后</p>',
      );
      final b = stackedChapter(
        '<p>前<span style="$stackStyle;display:inline">$inner</span>后</p>',
      );
      expect(a.blocks.expand((b) => b.inlineStacks), isEmpty, reason: inner);
      expect(a.blocks.map((b) => b.blockKey), b.blocks.map((b) => b.blockKey));
    }
    for (final extra in [
      'width:5em',
      'padding:1em',
      'overflow:hidden',
      'position:absolute',
      'float:right',
      'writing-mode:vertical-rl',
    ]) {
      final b =
          stackedChapter(
                '<p>前<span style="$stackStyle;$extra">上<br/>下</span>后</p>',
              ).blocks.single
              as ParagraphBlock;
      expect(b.inlineStacks, isEmpty);
      expect(b.text, '前上\n下后');
    }
    expect(
      stackedChapter(
        '<p><a href="b.xhtml"><span style="$stackStyle">上<br/>下</span></a></p>',
      ).blocks.single.inlineStacks,
      isEmpty,
    );
  });
  test(
    'bounds downgrade without truncation and ranges reject malformed atoms',
    () {
      final b =
          stackedChapter(
                '<p><span style="$stackStyle">${'上' * 257}<br/>下</span>尾</p>',
              ).blocks.single
              as ParagraphBlock;
      expect(b.inlineStacks, isEmpty);
      expect(b.text.runes.length, 260);
      final many =
          stackedChapter(
                '<p>${List.filled(65, '<span style="$stackStyle">上<br/>下</span>').join()}尾</p>',
              ).blocks.single
              as ParagraphBlock;
      expect(many.inlineStacks, hasLength(64));
      expect(many.text, '${List.filled(65, '上\n下').join()}尾');
      final valid = InlineStack(start: 0, length: 3, separator: 1);
      expect(
        () => ParagraphBlock(text: '上\n下', inlineStacks: [valid, valid]),
        throwsArgumentError,
      );
      expect(
        () => ParagraphBlock(
          text: '上\n下',
          inlineStacks: [InlineStack(start: 1, length: 3, separator: 2)],
        ),
        throwsArgumentError,
      );
      expect(
        () => ParagraphBlock(
          text: '😀\u200d😀\n下',
          inlineStacks: [InlineStack(start: 1, length: 4, separator: 3)],
        ),
        throwsArgumentError,
      );
      expect(
        () => ParagraphBlock(
          text: '上\n下',
          inlineStacks: [valid],
          inlineRuby: [InlineRuby(start: 0, length: 1, annotation: '注')],
        ),
        throwsArgumentError,
      );
    },
  );
}
