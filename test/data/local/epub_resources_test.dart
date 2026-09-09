import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

(ParsedEpub, Map<String, String>) book(
  String body, {
  String head = '',
  Map<String, List<int>> extra = const {},
}) {
  final files = epubFiles();
  files.addAll(extra);
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><head>$head</head><body><div style="float:right">$body</div><p>tail</p></body></html>',
  );
  final parser = EpubParser(
    zipFiles(files),
    NovelKey(sourceId: SourceId('local'), novelId: 'resources'),
    'fixture.epub',
    includePresentations: true,
  );
  final parsed = parser.parse();
  return (parsed, parser.presentations);
}

void expectImage((ParsedEpub, Map<String, String>) result) {
  final chapter = result.$1.content.chapters.first;
  expect(chapter.blocks.whereType<ImageBlock>(), hasLength(1));
  expect(result.$2[chapter.key.chapterId], contains('data:image/png;base64,'));
}

void main() {
  test('candidate processing is bounded and preserves a placeholder', () {
    final candidates = List.filled(128, 'missing.png 1x').join(', ');
    final result = book(
      '<img srcset="$candidates, ../images/%E6%98%9F%20%E7%A9%BA.png 2x"/>',
    );
    expect(
      result.$1.content.chapters.first.blocks.whereType<ImageBlock>(),
      isEmpty,
    );
  });
  test('picture selection precedes img fallback and agrees with inert bytes', () {
    final gif = utf8.encode('GIF89a1234');
    final result = book(
      '<picture><source srcset="choice.gif 1x"/><img src="../images/%E6%98%9F%20%E7%A9%BA.png"/></picture>',
      extra: {'OPS/text/choice.gif': gif},
    );
    final image = result.$1.content.chapters.first.blocks
        .whereType<ImageBlock>()
        .single;
    final hash = image.media.mediaId.split('/').last;
    expect(result.$1.media[hash], gif);
    expect(
      result.$2.values.first,
      contains('data:image/gif;base64,${base64Encode(gif)}'),
    );
  });
  test('guide XHTML cover uses the same candidate fallback', () {
    final files = epubFiles();
    files['OPS/book.opf'] = utf8.encode(
      utf8
          .decode(files['OPS/book.opf']!)
          .replaceAll('properties="cover-image"', '')
          .replaceAll('<meta name="cover" content="cover"/>', '')
          .replaceAll(
            '</manifest>',
            '<item id="coverpage" href="cover.xhtml" media-type="application/xhtml+xml"/></manifest>',
          )
          .replaceAll(
            '</package>',
            '<guide><reference type="cover" href="cover.xhtml"/></guide></package>',
          ),
    );
    files['OPS/cover.xhtml'] = utf8.encode(
      '<html><body><img srcset="images/%E6%98%9F%20%E7%A9%BA.png 1x"/></body></html>',
    );
    final parsed = EpubParser(
      zipFiles(files),
      NovelKey(sourceId: SourceId('local'), novelId: 'guide'),
      'test.epub',
    ).parse();
    expect(parsed.content.detail.summary.cover, isNotNull);
  });

  test(
    'srcset-only supports density and width candidates with missing fallback',
    () {
      for (final descriptor in ['2x', '.5x', '1e0x', '640w']) {
        expectImage(
          book(
            '<img srcset="missing.png 1x, ../images/%E6%98%9F%20%E7%A9%BA.png $descriptor"/>',
          ),
        );
      }
    },
  );
  test('picture skips unsupported and conditional sources in both renderers', () {
    final result = book(
      '<picture><source type="image/avif" srcset="bad.avif"/><source media="print" srcset="bad.png"/><source media="(min-width:1px)" srcset="bad.png"/><source type="image/png" media="screen" srcset="../images/%E6%98%9F%20%E7%A9%BA.png 1x"/><img src="missing.png"/></picture>',
    );
    expectImage(result);
    final output = result.$2.values.first;
    expect(output, isNot(contains('<source')));
    expect(output, isNot(contains('srcset=')));
  });
  test(
    'existing src precedes img srcset and unlisted byte-sniffed image works',
    () {
      expectImage(
        book(
          '<img src="unlisted.bin" srcset="missing.png 2x"/>',
          extra: {'OPS/text/unlisted.bin': tinyPng},
        ),
      );
    },
  );
  test(
    'commas inside candidate URLs and percent-encoded commas are preserved',
    () {
      for (final path in ['a,b.png', 'a%2Cb.png']) {
        expectImage(
          book(
            '<img srcset="$path 1x"/>',
            extra: {'OPS/text/a,b.png': tinyPng},
          ),
        );
      }
    },
  );
  test('invalid descriptors and remote candidates fall back without network', () {
    expectImage(
      book(
        '<img srcset="bad.png -1x, bad.png 0w, bad.png 1w 2x, https://example.com/remote.png 2x, ../images/%E6%98%9F%20%E7%A9%BA.png 3x"/>',
      ),
    );
  });
  test(
    'all missing candidates keep native placeholder and subsequent text',
    () {
      final result = book(
        '<img srcset="missing.png 1x, missing2.png 2x" alt="missing"/>',
      );
      final blocks = result.$1.content.chapters.first.blocks;
      expect(blocks.whereType<ImageBlock>(), isEmpty);
      expect(
        blocks.whereType<ParagraphBlock>().map((b) => b.text),
        containsAllInOrder(['[missing]', 'tail']),
      );
    },
  );
  test('root absolute and escaping candidates remain rejected', () {
    for (final path in [
      '/OPS/images/a.png',
      '../../../escape.png',
      '..%2F..%2F..%2Fescape.png',
    ]) {
      expect(
        () => book('<img srcset="$path 1x"/>'),
        throwsA(isA<LocalParseException>()),
      );
    }
  });
  test('base and xml base remain uninterpreted with inert base removed', () {
    final result = book(
      '<div xml:base="https://example.com/"><img src="../images/%E6%98%9F%20%E7%A9%BA.png"/></div>',
      head: '<base href="https://example.com/"/>',
    );
    expectImage(result);
    expect(result.$2.values.first, isNot(contains('https://example.com')));
  });
}
