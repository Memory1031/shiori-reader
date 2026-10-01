import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/record_codec.dart';
import '../../data/local/support/epub_fixtures.dart';
import '../../data/local/support/authored_epub.dart';
import '../../data/local/support/mixed_epub_fixture.dart';
import 'package:shiori/domain/contracts/local_books.dart';

Uint8List auditFixture({String? body, String css = '', String head = ''}) {
  final files = epubFiles();
  files['OPS/text/a.xhtml'] = utf8.encode(
    '''<html xmlns:epub="http://www.idpf.org/2007/ops"><head><style>$css</style>$head</head><body>${body ?? '<h2 id="one">Synthetic heading</h2><p>Alpha <ruby>base<rt>reading</rt></ruby> omega.</p><p>Note<a epub:type="noteref" href="#note">1</a>.</p><aside epub:type="footnote" id="note"><p>Self authored note.</p></aside><p>Before <img src="../images/星 空.png" style="height:1em"/> after.</p><p><br/></p><pre>  preserved\n space</pre><p>Wide\u00a0space<br/>new line.</p><p><a href="b.xhtml#b">Destination</a></p>'}</body></html>''',
  );
  return zipFiles(files);
}

Map<String, Uint8List> baselineFixtures() => {
  'semantics': auditFixture(),
  'authored': authoredEpub(),
  'mixed': zipFiles(mixedEpub(repeat: true)),
  'presentation': auditFixture(
    body:
        '<div style="position:absolute;top:3px"><p>Short authored page</p><img src="../images/星 空.png"/></div>',
  ),
  'invalid': Uint8List.fromList([1, 2, 3]),
  'fixedRejected': zipFiles(
    mixedEpub(
      metadata: '<meta property="rendition:layout">pre-paginated</meta>',
    ),
  ),
};

// Complete persistent content plus parser-owned media/presentation identities.
// Synthetic data only; used to freeze the pre-observer baseline.
Map<String, Object?> parserSnapshot(EpubParser parser) {
  final parsed = parser.parse();
  final c = parsed.content;
  return {
    'content': {
      'detail': RecordCodec.detail(c.detail),
      'catalog': RecordCodec.catalog(c.catalog),
      'chapters': c.chapters.map((e) => e.toJson()).toList(),
      'auxiliary': c.auxiliaryChapters.map((e) => e.toJson()).toList(),
      'navigation': c.navigation.map((e) => e.toJson()).toList(),
      'links': c.links.map((e) => e.toJson()).toList(),
      'readingOrder': c.readingOrder?.map((e) => e.toJson()).toList(),
      'txtEncoding': c.txtEncoding?.name,
    },
    'media': {
      for (final e in parsed.media.entries)
        e.key: sha256.convert(e.value).toString(),
    },
    'mediaByPath': {
      for (final e in parser.mediaByPath.entries) e.key: e.value.toJson(),
    },
    'presentations': {
      for (final e in parser.presentations.entries)
        e.key: sha256.convert(utf8.encode(e.value)).toString(),
    },
    'diagnostics': parsed.diagnostics.codes.map((e) => e.name).toList(),
    'diagnosticsTruncated': parsed.diagnostics.truncated,
  };
}

EpubParser fixtureParser(Uint8List bytes) => EpubParser(
  bytes,
  LocalBookIdentity.book(sha256.convert(bytes).toString()),
  'synthetic.epub',
  includePresentations: true,
);
