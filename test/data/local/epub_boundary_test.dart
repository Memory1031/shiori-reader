import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'support/epub_fixtures.dart';
import 'epub_structure_test.dart' show parse, replace;

void main() {
  test('EPUB2 guide cover page supplies missing metadata cover', () {
    final f = epubFiles(ncx: true);
    replace(f, 'OPS/book.opf', 'properties="cover-image"', '');
    replace(f, 'OPS/book.opf', '<meta name="cover" content="cover"/>', '');
    replace(
      f,
      'OPS/book.opf',
      '</package>',
      '<guide><reference type="cover" href="text/a.xhtml"/></guide></package>',
    );
    expect(parse(f).content.detail.summary.cover, isNotNull);
  });
  test('broken cover-image falls back to usable legacy cover', () {
    final f = epubFiles();
    replace(f, 'OPS/book.opf', 'properties="cover-image"', '');
    replace(
      f,
      'OPS/book.opf',
      '</manifest>',
      '<item id="bad" href="missing.png" media-type="image/png" properties="cover-image"/></manifest>',
    );
    expect(parse(f).content.detail.summary.cover, isNotNull);
  });
  test('guide external cover stays offline and absent', () {
    final f = epubFiles();
    replace(f, 'OPS/book.opf', 'properties="cover-image"', '');
    replace(f, 'OPS/book.opf', '<meta name="cover" content="cover"/>', '');
    replace(
      f,
      'OPS/book.opf',
      '</package>',
      '<guide><reference type="cover" href="https://example.com/cover"/></guide></package>',
    );
    expect(parse(f).content.detail.summary.cover, isNull);
  });

  test('foreign metadata and attributes do not shadow standard values', () {
    final f = epubFiles();
    replace(
      f,
      'OPS/book.opf',
      '<dc:title>',
      '<x:title xmlns:x="urn:extension">Wrong</x:title><dc:title>',
    );
    replace(
      f,
      'OPS/book.opf',
      'id="a"',
      'xmlns:x="urn:extension" x:id="wrong" id="a"',
    );
    expect(parse(f).content.detail.summary.title, '离线星空');
  });
  test('container ignores nested foreign rootfile', () {
    final f = epubFiles();
    replace(
      f,
      'META-INF/container.xml',
      '<rootfiles>',
      '<extension xmlns="urn:extension"><rootfile full-path="missing.opf" media-type="application/oebps-package+xml"/></extension><rootfiles>',
    );
    expect(parse(f).content.chapters, hasLength(2));
  });
  test('NCX ignores foreign map and navPoint', () {
    final f = epubFiles(ncx: true);
    replace(
      f,
      'OPS/toc.ncx',
      '<navMap>',
      '<x:navMap xmlns:x="urn:extension"/><navMap><x:navPoint xmlns:x="urn:extension"><navLabel><text>Wrong</text></navLabel><content src="text/a.xhtml"/></x:navPoint>',
    );
    expect(parse(f).content.navigation.first.title, '第二卷');
  });
  test('deep XML rejects before recursive navigation processing', () {
    final f = epubFiles();
    replace(
      f,
      'OPS/book.opf',
      '</metadata>',
      '${List.filled(140, '<extension>').join()}${List.filled(140, '</extension>').join()}</metadata>',
    );
    expect(
      () => parse(f),
      throwsA(
        isA<LocalParseException>().having(
          (e) => e.problem,
          'problem',
          LocalParseProblem.tooLarge,
        ),
      ),
    );
  });
  test('spine foreign format follows XHTML fallback and keeps nav aliases', () {
    final f = epubFiles();
    replace(
      f,
      'OPS/book.opf',
      '</manifest>',
      '<item id="foreign" href="foreign.bin" media-type="application/x-unknown" fallback="a"/></manifest>',
    );
    replace(f, 'OPS/book.opf', 'idref="a"', 'idref="foreign"');
    replace(f, 'OPS/nav.xhtml', 'text/a.xhtml#one', 'foreign.bin#one');
    final result = parse(f).content;
    final baseline = parse(epubFiles()).content;
    expect(
      result.chapters.map((c) => c.key),
      baseline.chapters.map((c) => c.key),
    );
    expect(result.navigation[1].blockKey, baseline.navigation[1].blockKey);
  });
  test('fallback cycles and missing targets fail without recursion', () {
    for (final fallback in ['foreign', 'missing']) {
      final f = epubFiles();
      replace(
        f,
        'OPS/book.opf',
        '</manifest>',
        '<item id="foreign" href="foreign.bin" media-type="application/x-unknown" fallback="$fallback"/></manifest>',
      );
      replace(f, 'OPS/book.opf', 'idref="a"', 'idref="foreign"');
      expect(() => parse(f), throwsA(isA<LocalParseException>()));
    }
  });
  test(
    'spine nav grouping without href targets first child, not nav itself',
    () {
      final f = epubFiles();
      replace(
        f,
        'OPS/book.opf',
        '</spine>',
        '<itemref idref="nav" linear="no"/></spine>',
      );
      final result = parse(f).content;
      expect(result.chapters, hasLength(3));
      expect(result.navigation.first.chapterKey, result.chapters[1].key);
    },
  );
  test('nav properties tokens and foreign type cannot steal TOC', () {
    final f = epubFiles();
    replace(f, 'OPS/book.opf', 'properties="nav"', 'properties="scripted nav"');
    replace(
      f,
      'OPS/nav.xhtml',
      '<body>',
      '<body><nav xmlns:x="urn:foreign" x:type="toc"><ol><li><a href="text/a.xhtml">Wrong</a></li></ol></nav>',
    );
    expect(parse(f).content.navigation.first.title, '第二卷');
  });
  test(
    'linear no retains content and case-sensitive missing resource fails',
    () {
      final f = epubFiles();
      replace(f, 'OPS/book.opf', 'idref="a"', 'idref="a" linear="no"');
      expect(parse(f).content.chapters, hasLength(2));
      replace(f, 'OPS/book.opf', 'text/a.xhtml', 'text/A.xhtml');
      expect(() => parse(f), throwsA(isA<LocalParseException>()));
    },
  );
  test('encoded fragment and nested nav directory resolve consistently', () {
    final f = epubFiles();
    replace(f, 'OPS/text/a.xhtml', 'id="one"', 'id="节 一"');
    replace(f, 'OPS/nav.xhtml', 'text/', '../text/');
    replace(f, 'OPS/nav.xhtml', '#one', '#%E8%8A%82%20%E4%B8%80');
    f['OPS/navigation/nav.xhtml'] = f.remove('OPS/nav.xhtml')!;
    replace(
      f,
      'OPS/book.opf',
      'href="nav.xhtml"',
      'href="navigation/nav.xhtml"',
    );
    expect(parse(f).content.navigation[1].blockKey, isNotNull);
  });
  test('missing images retain placeholder and trailing prose', () {
    final f = epubFiles();
    f.remove('OPS/images/星 空.png');
    final result = parse(f);
    expect(result.content.detail.summary.cover, isNull);
    expect(result.content.chapters.first.blocks.length, greaterThan(3));
  });
}
