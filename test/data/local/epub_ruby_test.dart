import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

void main() {
  ChapterContent parse(String body) => EpubParser(
    zipFiles(
      epubFiles()
        ..['OPS/text/a.xhtml'] = utf8.encode('<html><body>$body</body></html>'),
    ),
    LocalBookIdentity.book('e' * 64),
    'ruby.epub',
  ).parse().content.chapters.first;

  test('preformatted multiline ruby retains its annotation fallback', () {
    final chapter = parse('<pre><ruby>甲\n乙<rt>a</rt></ruby></pre>');
    expect((chapter.blocks.first as ParagraphBlock).text, '甲\n乙（a）');
    expect(chapter.blocks.first.inlineRuby, isEmpty);
  });

  test('hidden EPUB ruby annotations do not leak into visible prose', () {
    final chapter = parse(
      '<style>.hide{display:none}.invisible{visibility:hidden}</style>'
      '<p><ruby>甲<rt hidden>secret1</rt></ruby>'
      '<ruby>乙<rt style="display:none">secret2</rt></ruby>'
      '<ruby>丙<rt class="hide">secret3</rt></ruby>'
      '<ruby>丁<rt class="invisible">secret4</rt></ruby>'
      '<ruby>戊<rt>show<span hidden>secret5</span></rt></ruby></p>',
    );
    final paragraph = chapter.blocks.first as ParagraphBlock;
    expect(paragraph.text, '甲乙丙丁戊');
    expect(paragraph.inlineRuby.map((ruby) => ruby.annotation), ['show']);
  });

  test('ruby annotation inherits visibility from its hidden parent', () {
    final chapter = parse(
      '<p><ruby style="visibility:hidden">'
      '<span style="visibility:visible">甲</span><rt>secret</rt>'
      '</ruby><ruby style="visibility:hidden">'
      '<span style="visibility:visible">乙</span>'
      '<rt style="visibility:visible">shown</rt></ruby></p>',
    );
    final paragraph = chapter.blocks.first as ParagraphBlock;
    expect(paragraph.text, '甲乙');
    expect(paragraph.inlineRuby.map((ruby) => ruby.annotation), ['shown']);
  });

  test('visible descendants of hidden rt remain readable', () {
    final chapter = parse(
      '<p><ruby style="visibility:hidden">'
      '<span style="visibility:visible">甲</span>'
      '<rt>secret<span style="visibility:visible">jia</span></rt>'
      '</ruby><ruby style="visibility:hidden">'
      '<span style="visibility:visible">乙</span><rt>secret</rt>'
      '</ruby><ruby>丙<rt style="visibility:hidden">'
      '<span style="visibility:visible">bing</span></rt></ruby>'
      '<ruby>丁<rt hidden><span style="visibility:visible">leak</span>'
      '</rt></ruby><ruby>戊<rt style="display:none">'
      '<span style="visibility:visible">leak</span></rt></ruby></p>',
    );
    final paragraph = chapter.blocks.first as ParagraphBlock;
    expect(paragraph.text, '甲乙丙丁戊');
    expect(paragraph.inlineRuby.map((ruby) => ruby.annotation), [
      'jia',
      'bing',
    ]);

    final fallback = parse(
      '<pre><ruby style="visibility:hidden">'
      '<span style="visibility:visible">甲</span>'
      '<rt>secret<span style="visibility:visible">jia</span></rt>'
      '</ruby></pre>',
    );
    expect((fallback.blocks.first as ParagraphBlock).text, '甲（jia）');
    expect(fallback.blocks.first.inlineRuby, isEmpty);
  });

  test(
    'ruby preserves base ranges, multiple pairs, heading, link and Unicode',
    () {
      final chapter = parse(
        '<h2><ruby>标题<rt>title</rt></ruby></h2>'
        '<p> 😀<a href="b.xhtml"><ruby>头脑风暴<rp>(</rp><rt>buresuto</rt><rp>)</rp></ruby></a>'
        '<ruby><rb>明神</rb><rt>Akegami</rt><rb>凛音</rb><rt>Rinne</rt></ruby>。</p>',
      );
      expect(chapter.blocks.first.inlineRuby.single.annotation, 'title');
      final paragraph = chapter.blocks[1] as ParagraphBlock;
      expect(paragraph.text, '😀头脑风暴明神凛音。');
      expect(
        paragraph.inlineRuby.map((r) => [r.start, r.length, r.annotation]),
        [
          [1, 4, 'buresuto'],
          [5, 2, 'Akegami'],
          [7, 2, 'Rinne'],
        ],
      );
      expect(
        ChapterContent.fromJson(jsonDecode(jsonEncode(chapter.toJson()))),
        chapter,
      );
    },
  );

  test('nested, malformed and oversized ruby retains readable fallback', () {
    final chapter = parse(
      '<p><ruby>甲<ruby>乙<rt>b</rt></ruby><rt>a</rt></ruby>'
      '<ruby>丙<rt></rt></ruby><ruby>${'丁' * 65}<rt>d</rt></ruby></p>',
    );
    expect(
      (chapter.blocks.first as ParagraphBlock).text,
      '甲乙（a）丙${'丁' * 65}（d）',
    );
    expect(chapter.blocks.first.inlineRuby.single.annotation, 'b');
  });

  test(
    'old JSON stays readable and annotations participate in content identity',
    () {
      final old = ChapterContent(
        key: LocalBookIdentity.chapter(
          LocalBookIdentity.book('a' * 64),
          'test',
        ),
        title: 'Old',
        blocks: [ParagraphBlock(text: '头脑风暴（buresuto）')],
      );
      expect(ChapterContent.fromJson(old.toJson()), old);
      final a = parse('<p><ruby>甲<rt>A</rt></ruby></p>');
      final b = parse('<p><ruby>甲<rt>B</rt></ruby></p>');
      expect(a.contentRevision, isNot(b.contentRevision));
      expect(
        () => ParagraphBlock(
          text: '甲',
          inlineRuby: [InlineRuby(start: 0, length: 2, annotation: 'a')],
        ),
        throwsArgumentError,
      );
      expect(
        () => ParagraphBlock(
          text: '甲乙',
          inlineRuby: [
            InlineRuby(start: 0, length: 2, annotation: 'a'),
            InlineRuby(start: 1, length: 1, annotation: 'b'),
          ],
        ),
        throwsArgumentError,
      );
    },
  );
}
