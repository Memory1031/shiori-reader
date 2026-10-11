import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'package:shiori/domain/models/models.dart';
import 'parsers_test.dart' show decode, ParserSession, utf16;
import 'support/epub_fixtures.dart';
import 'support/mixed_epub_fixture.dart';

List<int> cssBytes(String css, String encoding) => switch (encoding) {
  'utf8-bom' => [239, 187, 191, ...utf8.encode(css)],
  'utf16le' => utf16(css),
  'utf16be' => utf16(css, le: false),
  _ => utf8.encode(css),
};

Map<String, List<int>> styledFiles(List<int> css) {
  final files = epubFiles();
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><head><link rel="stylesheet" href="screen-style"/></head>'
    '<body><p id="one"><a href="b.xhtml#b">正文链接</a>，保留正文。</p>'
    '<p id="two">下一段。</p></body></html>',
  );
  files['OPS/text/screen-style'] = css;
  return files;
}

EpubParser parser(Map<String, List<int>> files, {bool presentation = true}) =>
    EpubParser(
      zipFiles(files),
      LocalBookIdentity.book('a' * 64),
      'css-comments.epub',
      includePresentations: presentation,
    );

void main() {
  const controls = '\x00\x01\x08\x0b\x0e\x1f\x7f';
  const comment = '/* 制作注释：<span class="jp">$controls</span> */';
  final encodingError = throwsA(
    isA<LocalParseException>().having(
      (e) => e.problem,
      'problem',
      LocalParseProblem.encoding,
    ),
  );

  for (final encoding in ['utf8', 'utf8-bom', 'utf16le', 'utf16be']) {
    for (final presentation in [false, true]) {
      test('CSS comment controls preserve imports and content ($encoding, '
          '$presentation)', () {
        final files = styledFiles(
          cssBytes(
            '$comment @import "base-style";'
            'p{position:absolute;text-align:right;}$comment',
            encoding,
          ),
        );
        files['OPS/text/base-style'] = cssBytes(
          '$comment p{text-align:center;text-indent:2em;}',
          encoding,
        );
        final p = parser(files, presentation: presentation);
        final result = p.parse();
        expect(result.content.chapters, hasLength(2));
        final blocks = result.content.chapters.first.blocks
            .whereType<ParagraphBlock>()
            .toList();
        expect(blocks.map((b) => b.text), ['正文链接，保留正文。', '下一段。']);
        expect(blocks.first.alignment, ParagraphAlignment.end);
        expect(blocks.first.leadingIndent, 2);
        final link = result.content.links.single;
        expect(link.target, result.content.chapters.last.key);
        expect(link.unavailable, isNull);
        expect(result.media, isNotEmpty);
        if (presentation) {
          final html = p.presentations.values.single;
          expect(html, contains('text-indent:2em'));
          expect(html, contains('text-align:right'));
          expect(html, isNot(contains('制作注释')));
          expect(html, isNot(contains('\x01')));
        } else {
          expect(p.presentations, isEmpty);
        }
      });
    }
  }

  test(
    'production decoder imports CSS with control characters in comments',
    () async {
      final files = styledFiles(utf8.encode('$comment p{text-align:center;}'));
      final session = ParserSession(zipFiles(files));
      final content = await decode(session, LocalBookFormat.epub);
      expect(content.chapters, hasLength(2));
      expect(
        (content.chapters.first.blocks.first as ParagraphBlock).alignment,
        ParagraphAlignment.center,
      );
      expect(session.media, isNotEmpty);
    },
  );

  test('fixed image page uses the same CSS comment tolerance', () {
    final files = mixedEpub();
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><head><link rel="stylesheet" href="../fixed-style"/></head>'
      '<body><img src="../images/%E6%98%9F%20%E7%A9%BA.png"/></body></html>',
    );
    files['OPS/fixed-style'] = utf8.encode('$comment img{width:100%;}');
    final result = parser(files).parse();
    expect(result.content.chapters, hasLength(3));
    expect(result.content.chapters.first.blocks.single, isA<ImageBlock>());
  });

  test('controls outside CSS comments still fail strict validation', () {
    for (final css in [
      '$comment p{\x01text-align:center;}',
      'p{font-family:"/*\x01*/";}',
      "p{font-family:'/*\x01*/';}",
      'p{font-family:"escaped\\"/*\x01*/";}',
      'p{font-family:escaped\\/*\x01*/;}',
    ]) {
      expect(
        () => parser(styledFiles(utf8.encode(css))).parse(),
        encodingError,
        reason: css,
      );
    }
  });

  test('CSS comment tolerance does not relax XHTML or TXT content', () {
    final files = styledFiles(utf8.encode('$comment p{text-align:center;}'));
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><body><p>正文 /*\x01*/</p></body></html>',
    );
    expect(() => parser(files).parse(), encodingError);
    expect(
      decode(
        ParserSession(utf8.encode('正文 /*\x01*/')),
        LocalBookFormat.txt,
        encoding: TxtEncoding.utf8,
      ),
      encodingError,
    );
  });

  test('malformed CSS encodings remain rejected even inside comments', () {
    for (final bytes in [
      [...utf8.encode('/*'), 0xff, ...utf8.encode('*/ p{text-align:center;}')],
      [...utf8.encode('/*'), 0xc3, ...utf8.encode('*/')],
      [...utf16('/*'), 0x00, 0xd8, ...utf16('*/').skip(2)],
      [...utf16('/*\x01*/'), 0],
    ]) {
      expect(() => parser(styledFiles(bytes)).parse(), encodingError);
    }
  });
}
