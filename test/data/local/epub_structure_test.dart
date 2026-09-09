import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

ParsedEpub parse(Map<String, List<int>> files) => EpubParser(
  zipFiles(files),
  NovelKey(sourceId: SourceId('local'), novelId: 'structure'),
  'fixture.epub',
).parse();
void replace(
  Map<String, List<int>> files,
  String path,
  String from,
  String to,
) {
  files[path] = utf8.encode(utf8.decode(files[path]!).replaceAll(from, to));
}

void main() {
  test('WebP bytes remain images even with generic manifest MIME', () {
    final files = epubFiles();
    final bytes = base64Decode(
      'UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA',
    );
    files['OPS/images/星 空.png'] = bytes;
    replace(files, 'OPS/book.opf', 'image/png', 'application/octet-stream');
    final result = parse(files);
    expect(result.media.values.single, bytes);
    expect(result.content.detail.summary.cover, isNotNull);
    expect(
      result.content.chapters.first.blocks.whereType<ImageBlock>(),
      hasLength(1),
    );
  });
  test('empty manifest ID and href are rejected', () {
    for (final field in ['id="a"', 'href="text/a.xhtml"']) {
      final files = epubFiles();
      replace(
        files,
        'OPS/book.opf',
        field,
        field.startsWith('id') ? 'id=""' : 'href=""',
      );
      expect(() => parse(files), throwsA(isA<LocalParseException>()));
    }
  });

  test('OPF extensions cannot inject metadata or manifest entries', () {
    final files = epubFiles();
    replace(
      files,
      'OPS/book.opf',
      '<metadata ',
      '<extension><title>Wrong</title><item id="a" href="missing"/></extension><metadata ',
    );
    final result = parse(files);
    expect(result.content.detail.summary.title, '离线星空');
    expect(result.content.chapters.length, 2);
  });
  test('namespace alias preserves nested nav and fragment identity', () {
    final files = epubFiles();
    final baseline = parse(files).content;
    replace(files, 'OPS/nav.xhtml', 'epub:', 'book:');
    replace(files, 'OPS/nav.xhtml', 'xmlns:epub', 'xmlns:book');
    final result = parse(files).content;
    expect(result.navigation.first.title, '第二卷');
    expect(
      result.navigation[1].children.first.blockKey,
      baseline.navigation[1].children.first.blockKey,
    );
    expect(
      result.chapters.map((c) => c.key),
      baseline.chapters.map((c) => c.key),
    );
  });
  test('empty nav falls back to nested NCX before synthetic spine TOC', () {
    final files = epubFiles();
    replace(
      files,
      'OPS/book.opf',
      '</manifest>',
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>',
    );
    files['OPS/nav.xhtml'] = utf8.encode(
      '<html><body><nav epub:type="toc"><ol/></nav></body></html>',
    );
    final result = parse(files).content;
    expect(result.navigation.first.title, '第二卷');
    expect(result.navigation[1].children.first.blockKey, isNotNull);
    expect(result.navigation.first.chapterKey, result.chapters[1].key);
  });
  test('duplicate manifest and empty item identity fail explicitly', () {
    for (final change in [
      '<manifest/>',
      '<manifest><item id="" href="x"/></manifest>',
    ]) {
      final files = epubFiles();
      replace(files, 'OPS/book.opf', '</package>', '$change</package>');
      expect(() => parse(files), throwsA(isA<LocalParseException>()));
    }
  });
  test(
    'percent encoded literal is decoded once and external paths stay excluded',
    () {
      expect(epubReference('OPS/book.opf', 'text/a%2520b.xhtml#x%20y'), (
        'OPS/text/a%20b.xhtml',
        'x y',
      ));
      expect(epubReference('OPS/book.opf', 'https://example.com/a'), isNull);
      expect(
        () => epubReference('OPS/book.opf', '../../escape'),
        throwsA(isA<LocalParseException>()),
      );
    },
  );
}
