import 'dart:convert';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

void main() {
  EpubParser parser(Map<String, List<int>> files, {bool presentation = true}) =>
      EpubParser(
        zipFiles(files),
        LocalBookIdentity.book('a' * 64),
        'styles.epub',
        includePresentations: presentation,
      );
  final invalid = throwsA(
    isA<LocalParseException>().having(
      (e) => e.problem,
      'problem',
      LocalParseProblem.invalid,
    ),
  );
  for (final presentation in [false, true]) {
    test(
      'root chapter ignores escaping stylesheet, retains cover ($presentation)',
      () {
        final files = epubFiles();
        files['OPS/book.opf'] = utf8.encode(
          utf8
              .decode(files['OPS/book.opf']!)
              .replaceFirst('text/a.xhtml', '../chapter2_0.xhtml'),
        );
        files['chapter2_0.xhtml'] = utf8.encode(
          '<html><head><link rel="stylesheet" href="../Styles/style.css"/></head><body><img src="OPS/images/%E6%98%9F%20%E7%A9%BA.png"/></body></html>',
        );
        final result = parser(files, presentation: presentation).parse();
        expect(result.content.chapters, hasLength(2));
        expect(result.content.chapters.first.blocks.single, isA<ImageBlock>());
      },
    );
  }
  test(
    'bad imports and CSS fonts are omitted; valid sibling styles still apply',
    () {
      final files = epubFiles();
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<html><head><link rel="stylesheet" href="screen.css"/></head><body><p>正文</p></body></html>',
      );
      files['OPS/text/screen.css'] = utf8.encode(
        '''@import '../../../outside.css';
      @import '%FF.css'; @import 'valid.css';
      @font-face{font-family:old;src:url(../../../../../zw.ttf),url(file:///mnt/us/font.ttf),url(res:///opt/sony/font.ttf)}
      p{position:absolute}''',
      );
      files['OPS/text/valid.css'] = utf8.encode('p{text-align:center}');
      final p = parser(files);
      final result = p.parse();
      expect(
        (result.content.chapters.first.blocks.single as ParagraphBlock)
            .alignment,
        ParagraphAlignment.center,
      );
      final html = p.presentations.values.single;
      expect(html, contains('text-align:center'));
      expect(html, isNot(contains('file:///')));
      expect(html, isNot(contains('res:///')));
      expect(html, isNot(contains('zw.ttf')));
    },
  );
  test('manifest, container and body image containment remains strict', () {
    var files = epubFiles();
    files['OPS/book.opf'] = utf8.encode(
      utf8
          .decode(files['OPS/book.opf']!)
          .replaceFirst('text/a.xhtml', '../../outside.xhtml'),
    );
    expect(() => parser(files).parse(), invalid);
    files = epubFiles();
    files['META-INF/container.xml'] = utf8.encode(
      '<container><rootfiles><rootfile full-path="../outside.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    );
    expect(() => parser(files).parse(), invalid);
    files = epubFiles();
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><body><p>正文<img src="../../../outside.png"/></p></body></html>',
    );
    expect(() => parser(files).parse(), invalid);
  });
  test('optional stylesheet content still enforces size limits', () {
    final files = epubFiles();
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><head><link rel="stylesheet" href="huge.css"/></head><body><p>正文</p></body></html>',
    );
    files['OPS/text/huge.css'] = List.filled(4 * 1024 * 1024 + 1, 32);
    expect(
      () => parser(files).parse(),
      throwsA(
        isA<LocalParseException>().having(
          (e) => e.problem,
          'problem',
          LocalParseProblem.tooLarge,
        ),
      ),
    );
  });
}
