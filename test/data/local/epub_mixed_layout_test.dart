import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';
import 'support/mixed_epub_fixture.dart';

void main() {
  final book = NovelKey(sourceId: SourceId('local'), novelId: 'mixed');
  EpubParser parser(Map<String, List<int>> files) => EpubParser(
    zipFiles(files),
    book,
    'mixed.epub',
    includePresentations: true,
  );
  final fixedError = throwsA(
    isA<LocalParseException>().having(
      (e) => e.problem,
      'problem',
      LocalParseProblem.fixedLayout,
    ),
  );
  test(
    'mixed spine preserves dimensions, identities, navigation and native presentation',
    () {
      final p = parser(
        mixedEpub(
          metadata: '<meta property="rendition:layout">reflowable</meta>',
        ),
      );
      final content = p.parse().content;
      expect(content.chapters, hasLength(3));
      expect(content.readingOrder, content.chapters.map((c) => c.key));
      final first = content.chapters.first;
      expect(
        first.key,
        LocalBookIdentity.chapter(book, 'epub:OPS/text/a.xhtml'),
      );
      final image = first.blocks.single as ImageBlock;
      expect((image.width, image.height), (1, 1));
      final wide = content.chapters.last.blocks.single as ImageBlock;
      expect((wide.width, wide.height), (1000, 100));
      expect(content.navigation.last.chapterKey, first.key);
      expect(content.navigation.last.blockKey, image.blockKey);
      expect(p.presentations, isEmpty);
    },
  );
  test('default layout and repeated fixed occurrences remain supported', () {
    final content = parser(mixedEpub(repeat: true)).parse().content;
    expect(content.readingOrder, hasLength(4));
    expect(content.chapters.last.key, isNot(content.chapters.first.key));
    expect(content.chapters.last.blocks, content.chapters.first.blocks);
  });
  test('empty reflow occurrence cannot hide a later fixed occurrence', () {
    expect(
      () => parser(mixedEpub(body: '', properties: '', repeat: true)).parse(),
      fixedError,
    );
  });
  for (final count in [6, 15]) {
    for (final href in ['href', 'xlink:href']) {
      test('$count transparent SVG hotspots with $href are discarded', () {
        final p = parser(
          mixedEpub(
            body:
                '<main id="one"><svg xmlns:xlink="http://www.w3.org/1999/xlink">'
                '<image $href="../images/星 空.png"/>'
                '${List.generate(count, (i) => '<a $href="b.xhtml#b"><rect fill-opacity="0.0" x="10" y="${i * 20}" width="100" height="10"/></a>').join()}'
                '</svg></main>',
          ),
        );
        final content = p.parse().content;
        expect(content.chapters.first.blocks.single, isA<ImageBlock>());
        expect(content.links, isEmpty);
        expect(content.auxiliaryChapters, isEmpty);
        expect(
          content.navigation.last.blockKey,
          content.chapters.first.blocks.single.blockKey,
        );
        expect(p.presentations, isEmpty);
      });
    }
  }
  test('unfilled unstroked link rectangle is also a nonvisual hotspot', () {
    final content = parser(
      mixedEpub(
        body:
            '<svg><image href="../images/星 空.png"/>'
            '<a href="b.xhtml"><rect fill="none" stroke="none"/></a></svg>',
      ),
    ).parse().content;
    expect(content.chapters.first.blocks.single, isA<ImageBlock>());
    expect(content.links, isEmpty);
  });
  test('script and style text are not fixed-page prose', () {
    final content = parser(
      mixedEpub(
        body:
            '<script>neverExecute()</script>'
            '<style>main { margin: 0; }</style><main><img src="../images/星 空.png"/></main>',
      ),
    ).parse().content;
    expect(content.chapters.first.blocks.single, isA<ImageBlock>());
  });
  test('author CSS cannot make an attribute-transparent hotspot visible', () {
    final files = mixedEpub(
      body:
          '<svg><image href="../images/星 空.png"/>'
          '<a href="b.xhtml"><rect fill-opacity="0"/></a></svg>',
    );
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><head><link rel="stylesheet" href="../style.css"/></head>'
      '<body><svg><image href="../images/星 空.png"/><a href="b.xhtml"><rect fill-opacity="0"/></a></svg></body></html>',
    );
    files['OPS/style.css'] = utf8.encode(
      'rect { fill-opacity: 1 !important; }',
    );
    expect(() => parser(files).parse(), fixedError);
  });
  test('mixed layout overrides on repeated paths do not leak prose links', () {
    final content = parser(
      mixedEpub(
        properties: '',
        repeat: true,
        body: '<a href="b.xhtml"><img src="../images/星 空.png"/></a>',
      ),
    ).parse().content;
    expect(
      content.links.where((l) => l.source == content.chapters.first.key),
      isNotEmpty,
    );
    expect(
      content.links.where((l) => l.source == content.chapters.last.key),
      isEmpty,
    );
  });
  for (final metadata in [
    '<meta property="rendition:layout">pre-paginated</meta>',
    '<meta name="fixed-layout" content="true"/>',
  ]) {
    test('global fixed layout rejected: $metadata', () {
      expect(() => parser(mixedEpub(metadata: metadata)).parse(), fixedError);
    });
  }
  for (final body in [
    '',
    '<p>Fixed text</p>',
    '<img src="../images/星 空.png"/><p>caption</p>',
    '<img src="../images/星 空.png"/><img src="../images/星 空.png"/>',
    '<svg><image href="../images/星 空.png"/><path d="M0 0 L1 1"/></svg>',
    '<svg><path d="M0 0 L1 1"/></svg>',
    '<img src="missing.png"/>',
    '<img src="https://example.invalid/image.png"/>',
    '<svg><image href="../images/星 空.png"/><a href="b.xhtml"><rect/></a></svg>',
    '<svg><image href="../images/星 空.png"/><a href="b.xhtml"><rect fill-opacity="0" stroke="red"/></a></svg>',
    '<svg stroke="red"><image href="../images/星 空.png"/><a href="b.xhtml"><rect fill-opacity="0"/></a></svg>',
    '<svg><image href="../images/星 空.png"/><a href="b.xhtml"><rect fill-opacity="0" style="fill-opacity:1"/></a></svg>',
    '<svg><image href="../images/星 空.png"/><rect fill-opacity="0"/></svg>',
    '<svg><image href="../images/星 空.png"/><text>Visible text</text></svg>',
    '<img src="../images/星 空.png"/><div style="background-image:url(extra.png)"></div>',

    '<svg><image transform="rotate(90)" href="../images/星 空.png"/></svg>',
    '<img src="../images/星 空.png"/><canvas/>',
  ]) {
    test('unsafe fixed page rejected: $body', () {
      expect(() => parser(mixedEpub(body: body)).parse(), fixedError);
    });
  }
  for (final property in [
    'page-spread-right',
    'page-spread-left',
    'rendition:page-spread-center',
    'rendition:layout-reflowable',
    'other:rendition:layout-pre-paginated',
  ]) {
    test('non-fixed property leaves prose readable: $property', () {
      expect(
        parser(
          mixedEpub(body: '<p>Text</p>', properties: property),
        ).parse().content.chapters.first.blocks.single,
        isA<ParagraphBlock>(),
      );
    });
  }
}
