import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_text_styles.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

EpubParser book(String head) {
  final files = epubFiles();
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><head>$head</head><body><p>正文</p></body></html>',
  );
  files['OPS/text/screen.css'] = utf8.encode('p{text-align:right}');
  files['OPS/text/print.css'] = utf8.encode(
    'p{display:none;position:absolute}',
  );
  return EpubParser(
    zipFiles(files),
    NovelKey(sourceId: SourceId('local'), novelId: 'styles'),
    'fixture.epub',
    includePresentations: true,
  );
}

EpubParser bookWith(
  Map<String, String> sheets,
  String head, {
  String body = '<p>正文</p>',
}) {
  final files = epubFiles();
  sheets.forEach((name, css) => files['OPS/text/$name'] = utf8.encode(css));
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><head>$head</head><body>$body</body></html>',
  );
  return EpubParser(
    zipFiles(files),
    NovelKey(sourceId: SourceId('local'), novelId: 'styles-imports'),
    'fixture.epub',
    includePresentations: true,
  );
}

int indentOf(EpubParser parser) =>
    (parser.parse().content.chapters.first.blocks.single as ParagraphBlock)
        .leadingIndent;

void main() {
  test('unquoted url import permits whitespace before closing parenthesis', () {
    final parser = bookWith({
      'screen.css': '@import url(base.css );',
      'base.css': 'p{text-indent:2em;}',
    }, '<link rel="stylesheet" href="screen.css">');
    expect(indentOf(parser), 2);
  });

  test('keyword prefixes are not treated as charset or import', () {
    for (final prelude in [
      '@charsetWhatever;',
      '@charset-foo;',
      '@charset中文;',
      r'@charset\61;',
      '@imported "base.css";',
      '@import urlSomething(base.css);',
    ]) {
      final reads = <String>[];
      final document = html.parse(
        '<style>$prelude @import "base.css";</style>',
      );
      epubDocumentStylesheets(document, 'a.xhtml', (_, href) => href, (path) {
        reads.add(path);
        return 'p{text-indent:2em;}';
      }).toList();
      expect(reads, isEmpty, reason: prelude);
    }
  });

  test('stylesheet expansion stops at the total raw CSS budget', () {
    const budget = 8 * 1024 * 1024;
    const tail = 'p{text-indent:2em;}';
    // Two cached occurrences consume raw comment volume independently.
    final large = '/*${'x' * (budget ~/ 2 - tail.length - 4)}*/';
    final sheets = {
      'large.css': large,
      'overflow.css': 'x' * (tail.length * 2 + 1),
      'exact.css': tail * 2,
      'late.css': 'p{color:red;}',
    };
    final document = html.parse(
      '<link rel="stylesheet" href="large.css">'
      '<link rel="stylesheet" href="large.css">'
      '<link rel="stylesheet" href="overflow.css">'
      '<style>$tail$tail</style>'
      '<link rel="stylesheet" href="exact.css">'
      '<link rel="stylesheet" href="late.css">',
    );
    final result = epubDocumentStylesheets(
      document,
      'a.xhtml',
      (_, href) => href,
      (path) => sheets[path]!,
    ).toList();
    expect(result, [
      ('large.css', ''),
      ('large.css', ''),
      ('a.xhtml', tail * 2),
    ]);
  });

  test('stylesheet source order follows interleaved style and link', () {
    final result = book(
      '<style>p{text-align:center}</style><link rel="stylesheet" href="screen.css">',
    ).parse();
    expect(
      (result.content.chapters.first.blocks.single as ParagraphBlock).alignment,
      ParagraphAlignment.end,
    );
  });
  for (final tag in [
    '<style media="print">p{display:none;position:absolute}</style>',
    '<link rel="stylesheet" href="print.css" media="print">',
  ]) {
    test('print-only sheet cannot hide screen prose: $tag', () {
      final parser = book(tag);
      expect(parser.parse().content.chapters, hasLength(2));
      expect(parser.presentations, isEmpty);
    });
  }
  test(
    'rel tokens are case-insensitive and alternate sheets are not selected',
    () {
      final result = book(
        '<link rel="STYLESHEET" href="screen.css"><link rel="alternate stylesheet" href="print.css">',
      ).parse();
      expect(
        (result.content.chapters.first.blocks.single as ParagraphBlock)
            .alignment,
        ParagraphAlignment.end,
      );
    },
  );
  test('authored page keeps sheet order while ignoring print declarations', () {
    final parser = book(
      '<style>p{position:absolute;text-align:center}</style><link rel="stylesheet" href="screen.css"><style media="print">p{display:none}</style>',
    );
    parser.parse();
    final html = parser.presentations.values.single;
    expect(
      html.indexOf('text-align:center'),
      lessThan(html.indexOf('text-align:right')),
    );
    expect(html, isNot(contains('display:none')));
  });

  test('@import chain delivers first-line indent from the imported sheets', () {
    final parser = bookWith({
      'screen.css': '@import "default.css";\n@import "necessary.css";',
      'default.css': 'p{line-height:1.5em;}',
      'necessary.css': 'p{text-indent:2em;}',
    }, '<link rel="stylesheet" href="screen.css">');
    expect(indentOf(parser), 2);
  });

  test('every inline style sheet applies, none swallowed by bookkeeping', () {
    final parser = bookWith(
      {},
      '<style>p{text-align:center}</style><style>p{text-indent:2em}</style>',
    );
    final block =
        parser.parse().content.chapters.first.blocks.single as ParagraphBlock;
    expect(block.alignment, ParagraphAlignment.center);
    expect(block.leadingIndent, 2);
  });

  test('url() imports resolve like plain string imports', () {
    final parser = bookWith({
      'screen.css': '@import url("base.css");',
      'base.css': 'p{text-indent:2em;}',
    }, '<link rel="stylesheet" href="screen.css">');
    expect(indentOf(parser), 2);
  });

  test('imported rules apply before the importing sheet’s own rules', () {
    final parser = bookWith({
      'screen.css': '@import "base.css";p{text-indent:0;}',
      'base.css': 'p{text-indent:2em;}',
    }, '<link rel="stylesheet" href="screen.css">');
    expect(indentOf(parser), 0);
  });

  test('only screen-applicable import qualifiers are followed', () {
    const cases = {
      '': 2,
      ' screen': 2,
      ' all': 2,
      ' screen, print': 2,
      ' print': 0,
      ' not screen': 0,
      ' screen and (min-width: 300px)': 0,
    };
    cases.forEach((qualifier, expected) {
      final parser = bookWith({
        'screen.css': '@import "base.css"$qualifier;',
        'base.css': 'p{text-indent:2em;}',
      }, '<link rel="stylesheet" href="screen.css">');
      expect(indentOf(parser), expected, reason: 'qualifier "$qualifier"');
    });
  });

  test('import cycles terminate and still apply the indent', () {
    // base.css's own import sits in the legal prelude, so the cycle
    // screen -> base -> screen is really followed and must terminate.
    final parser = bookWith({
      'screen.css': '@import "base.css";',
      'base.css': '@import "screen.css";p{text-indent:2em;}',
    }, '<link rel="stylesheet" href="screen.css">');
    expect(indentOf(parser), 2);
  });

  test('inline style imports resolve relative to the XHTML document', () {
    final parser = bookWith({
      'necessary.css': 'p{text-indent:2em;}',
    }, '<style>@import "necessary.css";</style>');
    expect(indentOf(parser), 2);
  });

  test('import keywords and media qualifiers are case-insensitive', () {
    final parser = bookWith({
      'screen.css': '@IMPORT URL("base.css") SCREEN;',
      'base.css': 'p{text-indent:2em;}',
    }, '<link rel="stylesheet" href="screen.css">');
    expect(indentOf(parser), 2);
  });

  test('sibling imports reapply the same sheet as cascade occurrences', () {
    final parser = bookWith(
      {
        'common.css': 'p{text-indent:2em;}',
        'a.css': '@import "common.css";p{text-indent:0;}',
        'b.css': '@import "common.css";',
      },
      '<link rel="stylesheet" href="a.css"><link rel="stylesheet" href="b.css">',
    );
    expect(indentOf(parser), 2);
  });

  test('nested imports resolve against the importing sheet’s own path', () {
    final files = epubFiles();
    files['OPS/text/screen.css'] = utf8.encode('@import "../styles/base.css";');
    files['OPS/styles/base.css'] = utf8.encode('@import "deep/leaf.css";');
    files['OPS/styles/deep/leaf.css'] = utf8.encode('p{text-indent:3em;}');
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><head><link rel="stylesheet" href="screen.css"></head>'
      '<body><p>正文</p></body></html>',
    );
    final parser = EpubParser(
      zipFiles(files),
      NovelKey(sourceId: SourceId('local'), novelId: 'styles-nested'),
      'fixture.epub',
      includePresentations: true,
    );
    expect(indentOf(parser), 3);
  });

  test('import lookalikes inside strings or blocks are never followed', () {
    final parser = bookWith({
      'screen.css': ".foo{content:'@import \"x.css\";';}",
      'x.css': 'p{display:none;}',
    }, '<link rel="stylesheet" href="screen.css">');
    expect(parser.parse().content.chapters, hasLength(2));
  });

  test('@charset preamble does not block imports', () {
    final parser = bookWith({
      'screen.css': '@charset "UTF-8";@import "base.css";',
      'base.css': 'p{text-indent:2em;}',
    }, '<link rel="stylesheet" href="screen.css">');
    expect(indentOf(parser), 2);
  });

  test('special pages see layout rules behind an import chain', () {
    final parser = bookWith(
      {
        'screen.css': '@import "base.css";',
        'base.css': '.v{writing-mode: vertical-rl;}',
      },
      '<link rel="stylesheet" href="screen.css">',
      body: '<div class="v"><p>竖排</p></div>',
    );
    parser.parse();
    expect(parser.presentations, isNotEmpty);
    expect(parser.presentations.values, everyElement(contains('vertical-rl')));
  });
}
