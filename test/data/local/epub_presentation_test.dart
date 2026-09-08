import 'dart:typed_data';
import 'dart:convert';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart';
import 'package:shiori/data/local/epub/epub_presentation.dart';

void main() {
  test(
    'opening h4 is a chapter heading but inner headings retain their level',
    () {
      final files = epubFiles();
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<html><body><h4 class="left" style="text-align:left">Opening chapter</h4>'
        '<p>Body</p><h4>Inner section</h4><p>More body</p></body></html>',
      );
      final parsed = EpubParser(
        zipFiles(files),
        NovelKey(sourceId: SourceId('local'), novelId: 'test'),
        'fixture.epub',
      ).parse();
      final chapter = parsed.content.chapters.first;
      expect(chapter.title, 'Opening chapter');
      expect((chapter.blocks[0] as HeadingBlock).level, 2);
      expect((chapter.blocks[2] as HeadingBlock).level, 4);
    },
  );

  test(
    'native paragraphs and headings retain CSS alignment with legacy heading codec intact',
    () {
      final files = epubFiles();
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<html><head><style>p{text-indent:2em;}h4,.center{text-align:center;}.right{text-align:right;}</style></head><body><h4>Heading</h4><p class="center">Centered</p><p class="right">Author</p><p>Body</p></body></html>',
      );
      final parsed = EpubParser(
        zipFiles(files),
        NovelKey(sourceId: SourceId('local'), novelId: 'test'),
        'fixture.epub',
      ).parse();
      final blocks = parsed.content.chapters.first.blocks;
      expect((blocks[0] as HeadingBlock).alignment, ParagraphAlignment.center);
      expect(
        (blocks[1] as ParagraphBlock).alignment,
        ParagraphAlignment.center,
      );
      expect((blocks[2] as ParagraphBlock).alignment, ParagraphAlignment.end);
      expect((blocks[3] as ParagraphBlock).leadingIndent, 2);
      final legacy = HeadingBlock(text: 'Legacy');
      expect(legacy.toJson().containsKey('alignment'), isFalse);
      expect(ContentBlock.fromJson(legacy.toJson()), legacy);
      expect(ContentBlock.fromJson(blocks[0].toJson()), blocks[0]);
    },
  );

  String? render(String body, String css) => epubPresentation(
    parse(
      '<html><head><link rel="stylesheet" href="style.css"></head><body>$body</body></html>',
    ),
    'page.xhtml',
    (_) => css,
    (_) => Uint8List.fromList([1, 2, 3]),
    (_, href) => Uri.tryParse(href)?.hasScheme == false ? href : null,
  );
  test(
    'authored layout preserves grouped glyphs and decoration without scripts or network',
    () {
      final html = render(
        '''<div class="column" onclick="alert(1)"><p>A</p><p>B</p></div>
      <script>alert(1)</script><iframe src="https://example.com"></iframe>
      <img src="https://example.com/image.png"><form action="https://example.com">submit</form>''',
        '.column {float:right; transform:rotate(-10deg);color:#123456;border:1px dotted blue;} @import "https://example.com/style.css";',
      )!;
      expect(html, contains('float:right'));
      expect(html, contains('rotate(-10deg)'));
      expect(html, contains('<div class="column"><p>A</p><p>B</p></div>'));
      expect(html, contains("script-src 'none'"));
      expect(html, isNot(contains('onclick')));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<iframe')));
      expect(html, isNot(contains('https://example.com')));
    },
  );
  test(
    'unused stylesheet classes do not route normal prose to a layout page',
    () {
      expect(
        render('<p>Ordinary paragraph.</p>', '.unused{float:right;}'),
        isNull,
      );
      expect(
        render(
          '<div class="column">${'Long text ' * 300}</div>',
          '.column{float:right;}',
        ),
        isNull,
      );
    },
  );
  test('local font is embedded and no original package path survives', () {
    final html = render(
      '<div class="column"><p>A</p></div>',
      '@font-face{font-family:test;src:url("font.ttf");}.column{float:left;font-family:test;}',
    )!;
    expect(html, contains('data:font/ttf;base64,AQID'));
    expect(html, isNot(contains('font.ttf')));
  });
}
