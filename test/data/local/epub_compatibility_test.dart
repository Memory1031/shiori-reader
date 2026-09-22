import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_zip.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

EpubParser parser(
  Map<String, List<int>> files, {
  bool compressedMime = false,
}) => EpubParser(
  zipFiles(files, compressMimetype: compressedMime),
  NovelKey(sourceId: SourceId('local'), novelId: 'fixture'),
  'self-authored.epub',
  includePresentations: true,
);
Map<String, List<int>> body(String value, {String css = ''}) => epubFiles()
  ..['OPS/text/a.xhtml'] = utf8.encode(
    '<html><head><style>$css</style></head><body>$value</body></html>',
  );
String prose(ChapterContent c) => c.blocks
    .map(
      (b) => switch (b) {
        ParagraphBlock(:final text) || HeadingBlock(:final text) => text,
        _ => '',
      },
    )
    .join();

void main() {
  test(
    'A01 skips an empty spine page, drops dead leaf targets and retains valid children',
    () {
      final files = body(' \n <hr/>');
      final p = parser(files);
      final result = p.parse();
      expect(p.skippedEmptyPaths, {'OPS/text/a.xhtml'});
      expect(result.content.chapters, hasLength(1));
      expect(result.content.catalog.flatChapters.single.ordinal, 0);
      expect(
        result.content.navigation.single.chapterKey,
        result.content.chapters.single.key,
      );
      files['OPS/text/b.xhtml'] = utf8.encode('<html><body> </body></html>');
      expect(() => parser(files).parse(), throwsA(isA<LocalParseException>()));
    },
  );
  test(
    'A02 authored SVG raster page falls back to native without losing image',
    () {
      final p = parser(
        body(
          '<div style="position:absolute"><svg xmlns="http://www.w3.org/2000/svg"><image href="../images/%E6%98%9F%20%E7%A9%BA.png"/></svg></div>',
        ),
      );
      final result = p.parse();
      expect(
        result.content.chapters.first.blocks.whereType<ImageBlock>(),
        hasLength(1),
      );
      expect(p.presentations, isEmpty);
    },
  );
  test('A02b positioned SVG text is rebuilt as one inert authored page', () {
    final files = epubFiles()
      ..['OPS/text/a.xhtml'] = utf8.encode(
        '''<html><head><title>目录</title></head>
<body style="margin:0;padding:0;"><div>
<svg style="margin:0;padding:0;" xmlns="http://www.w3.org/2000/svg"
 xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1"
 width="100%" height="100%" viewBox="0 0 1440 2048">
<image width="1440" height="2048" xlink:href="../images/%E6%98%9F%20%E7%A9%BA.png"/>
<a xlink:href="b.xhtml" target="_top">
<rect x="245" y="715" width="684" height="114" fill-opacity="0.0"/>
<text x="275" y="795" font-size="35" font-family="sans-serif">第１话　小澄同学与女生的证明</text>
<title>第１话　小澄同学与女生的证明</title>
</a>
</svg></div></body></html>''',
      );
    final native = EpubParser(
      zipFiles(files),
      NovelKey(sourceId: SourceId('local'), novelId: 'fixture'),
      'self-authored.epub',
    ).parse();
    final p = parser(files);
    final parsed = p.parse();
    final chapter = parsed.content.chapters.first;
    final rendered = p.presentations[chapter.key.chapterId]!;
    expect(rendered, contains('data:image/png;base64,'));
    expect(rendered, contains('viewBox="0 0 1440 2048"'));
    expect(RegExp('第１话　小澄同学与女生的证明').allMatches(rendered).length, 1);
    expect(rendered, isNot(contains('<title>')));
    expect(rendered, isNot(contains('b.xhtml')));
    expect(rendered, isNot(contains('xlink:href')));
    expect(
      chapter.contentRevision,
      native.content.chapters.first.contentRevision,
    );
  });
  test('A02c unsupported SVG drawing keeps the native fallback', () {
    final p = parser(
      body(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        '<image width="100" height="100" href="../images/%E6%98%9F%20%E7%A9%BA.png"/>'
        '<path d="M0 0 L1 1"/><text x="5" y="20">Title</text></svg>',
      ),
    )..parse();
    expect(p.presentations, isEmpty);
  });
  test('A02d metadata-only text does not qualify as positioned text', () {
    final p = parser(
      body(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        '<image width="100" height="100" href="../images/%E6%98%9F%20%E7%A9%BA.png"/>'
        '<text x="5" y="20"><title>only metadata</title></text></svg>',
      ),
    )..parse();
    expect(p.presentations, isEmpty);
  });
  test('A02e unsized SVG image keeps the native fallback', () {
    final p = parser(
      body(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        '<image href="../images/%E6%98%9F%20%E7%A9%BA.png"/>'
        '<text x="10" y="20">Visible</text></svg>',
      ),
    )..parse();
    expect(p.presentations, isEmpty);
  });
  test(
    'A03 explicit hidden subtree is omitted with missing anchor falling back to chapter start',
    () {
      final result = parser(
        body(
          '<div class="hide"><p id="one">Hidden text</p></div><p id="two">Visible</p>',
          css: '.hide {display:none}',
        ),
      ).parse();
      expect(prose(result.content.chapters.first), 'Visible');
      expect(result.content.navigation[1].blockKey, isNull);
      expect(
        result.content.navigation[1].children.first.blockKey,
        result.content.chapters.first.blocks.first.blockKey,
      );
    },
  );
  test('A04 important cascade respects specificity and inline priority', () {
    final result = parser(
      body(
        '<p id="one" style="text-align:right;text-indent:1em">Body</p><p style="text-align:right !important">Second</p>',
        css:
            'p{text-indent:2em !important;text-align:center !important}#one{text-align:left}',
      ),
    ).parse();
    final blocks = result.content.chapters.first.blocks.cast<ParagraphBlock>();
    expect(blocks[0].leadingIndent, 2);
    expect(blocks[0].alignment, ParagraphAlignment.center);
    expect(blocks[1].alignment, ParagraphAlignment.end);
  });
  test('A05 ruby consistently falls back to one parenthesized annotation', () {
    final result = parser(
      body(
        '<p><ruby>甲<rt>こう</rt></ruby>字 / <ruby>乙<rp>(</rp><rt>おつ</rt><rp>)</rp></ruby></p>',
      ),
    ).parse();
    expect(prose(result.content.chapters.first), '甲（こう）字 / 乙（おつ）');
  });
  test('A06 inline and stylesheet body layout select a presentation', () {
    for (final inline in [true, false]) {
      final files = epubFiles()
        ..['OPS/text/a.xhtml'] = utf8.encode(
          '<html><head><style>${inline ? '' : 'body{writing-mode:vertical-rl}'}</style></head>'
          '<body ${inline ? 'style="writing-mode:vertical-rl"' : ''}><p>Short layout</p></body></html>',
        );
      final p = parser(files)..parse();
      expect(
        p.presentations.values.single,
        contains('writing-mode:vertical-rl'),
      );
    }
  });
  test(
    'A07 package-local image queries are ignored without admitting network or traversal',
    () {
      final result = parser(
        body('<img src=" ../images/%E6%98%9F%20%E7%A9%BA.png?v=1#view "/>'),
      ).parse();
      expect(result.content.chapters.first.blocks.single, isA<ImageBlock>());
      expect(
        epubReference('OPS/a.xhtml', 'https://example.org/a.png?v=1'),
        isNull,
      );
      expect(epubReference('OPS/a.xhtml', '//example.org/a.png'), isNull);
      expect(
        () => epubReference('OPS/a.xhtml', '../../outside'),
        throwsA(isA<LocalParseException>()),
      );
      expect(
        () => epubReference('OPS/a.xhtml', '../C:/file'),
        throwsA(isA<LocalParseException>()),
      );
    },
  );
  test('unsupported pseudo-classes never abort the book', () {
    final p = parser(
      body(
        '<p>Body</p>',
        css:
            'p:unsupported-reader-state{position:absolute;text-indent:7em}p{text-indent:2em}',
      ),
    );
    expect(
      (p.parse().content.chapters.first.blocks.single as ParagraphBlock)
          .leadingIndent,
      2,
    );
    expect(p.presentations, isEmpty);
  });
  test(
    'print and unknown conditional rules are not flattened into screen text',
    () {
      final p = parser(
        body(
          '<p>Body</p>',
          css:
              '@media print{*{display:none!important}}'
              '@supports (unknown:yes){p{display:none}}@media screen{p{text-indent:2em}}'
              '@media print{body{position:absolute}}',
        ),
      );
      expect(
        (p.parse().content.chapters.first.blocks.single as ParagraphBlock)
            .leadingIndent,
        2,
      );
      expect(p.presentations, isEmpty);
    },
  );
  test('self-closing XHTML script cannot swallow following body', () {
    final files = epubFiles()
      ..['OPS/text/a.xhtml'] = utf8.encode(
        '<html><head><script src="inert.js"/></head><body><p>First</p><script src="x.js" /><p>Second</p></body></html>',
      );
    expect(prose(parser(files).parse().content.chapters.first), 'FirstSecond');
  });
  test(
    'compressed mimetype and trailing CRLF remain bounded and validated',
    () {
      final files = epubFiles()
        ..['mimetype'] = utf8.encode('application/epub+zip\r\n');
      expect(
        parser(files, compressedMime: true).parse().content.chapters,
        hasLength(2),
      );
      files['mimetype'] = utf8.encode('application/not-epub');
      expect(() => parser(files).parse(), throwsA(isA<LocalParseException>()));
    },
  );
  test('encoded unusual package leaf names remain in-memory identities', () {
    final files = body('<img src="../images/%2A%3A%3F%7C.png"/>');
    files['OPS/images/*:?|.png'] = tinyPng;
    expect(
      parser(files).parse().content.chapters.first.blocks.single,
      isA<ImageBlock>(),
    );
    files['C:/outside'] = [1];
    expect(() => parser(files).parse(), throwsA(isA<LocalParseException>()));
  });
  test(
    'legacy bit 4 tolerates stored and deflate but CRC and encryption remain enforced',
    () {
      final bytes = zipFiles(epubFiles());
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i + 46 <= bytes.length; i++) {
        if (data.getUint32(i, Endian.little) == 0x02014b50) {
          final local = data.getUint32(i + 42, Endian.little);
          final flags = data.getUint16(i + 8, Endian.little) | 0x10;
          data.setUint16(i + 8, flags, Endian.little);
          data.setUint16(local + 6, flags, Endian.little);
        }
      }
      expect(
        EpubZip(bytes).read('mimetype'),
        utf8.encode('application/epub+zip'),
      );
      final entry = EpubZip(bytes).entries['mimetype']!;
      bytes[entry.offset] ^= 1;
      expect(
        () => EpubZip(bytes).read('mimetype'),
        throwsA(isA<LocalParseException>()),
      );
      data.setUint16(6, data.getUint16(6, Endian.little) | 1, Endian.little);
      expect(() => EpubZip(bytes), throwsA(isA<LocalParseException>()));
    },
  );
}
