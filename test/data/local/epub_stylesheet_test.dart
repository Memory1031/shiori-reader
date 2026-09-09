import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
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

void main() {
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
}
