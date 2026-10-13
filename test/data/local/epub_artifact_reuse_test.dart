import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_trace.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';

import 'epub_html_links_test.dart' show htmlLinkFiles;
import 'epub_svg_links_test.dart' show svgLinksParser;
import 'support/epub_fixtures.dart';

class _Session implements LocalImportSession, EpubPresentationSession {
  _Session(this.bytes)
    : key = LocalBookIdentity.book(sha256.convert(bytes).toString());
  final Uint8List bytes;
  @override
  final NovelKey key;
  int opens = 0, handoffs = 0;
  (LocalBookContent, Map<String, String>)? artifacts;
  @override
  Stream<List<int>> openOriginal() {
    opens++;
    return Stream.value(bytes);
  }

  @override
  Future<MediaRef> writeMedia(Stream<List<int>> chunks) async => MediaRef(
    sourceId: key.sourceId,
    mediaId: '${key.novelId}/${await sha256.bind(chunks).first}',
  );
  @override
  void acceptPresentations((LocalBookContent, Map<String, String>)? value) {
    handoffs++;
    artifacts = value;
  }
}

void main() {
  final cases = <String, Uint8List Function()>{
    'ordinary': () => zipFiles(epubFiles()),
    'long ordinary chapters': () {
      final files = epubFiles();
      for (final name in ['a', 'b']) {
        files['OPS/text/$name.xhtml'] = utf8.encode(
          '<html><body><p>${'Native prose. ' * 400}</p></body></html>',
        );
      }
      return zipFiles(files);
    },
    'authored HTML links': () => zipFiles(htmlLinkFiles()),
    'SVG links, repeated spine and auxiliary targets': () => svgLinksParser(
      targets: [
        'b.xhtml#b',
        '../notes.xhtml#note',
        '#missing',
        'https://example.test',
      ],
      repeat: true,
    ).bytes,
  };
  for (final entry in cases.entries) {
    test(
      '${entry.key}: reuse preserves native output and legacy renditions',
      () async {
        final session = _Session(entry.value());
        final native = EpubParser(
          session.bytes,
          session.key,
          'book.epub',
        ).parse();
        final legacy = EpubParser(
          session.bytes,
          session.key,
          'book.epub',
          includePresentations: true,
        );
        final legacyContent = legacy.parse().content;
        final trace = EpubTraceCollector();
        final reused = EpubParser(
          session.bytes,
          session.key,
          'book.epub',
          trace: trace,
        );
        final parsed = reused.parse(retainPresentationInputs: true);
        final before = trace.events
            .where((e) => e['kind'] == 'document.output')
            .toList();
        final artifacts = reused.renderForImport(parsed.content);
        for (final event in before) {
          expect(
            trace.events.where(
              (e) =>
                  e['kind'] == 'document.output' &&
                  e['document'] == event['document'],
            ),
            hasLength(1),
          );
        }
        expect(artifacts.$2, legacy.presentations);
        expect(jsonEncode(artifacts.$2), jsonEncode(legacy.presentations));
        expect(
          artifacts.$1.links
              .where((l) => l.region != null)
              .map((l) => l.toJson()),
          legacyContent.links
              .where((l) => l.region != null)
              .map((l) => l.toJson()),
        );
        final decoded = await const BookDecoder().decode(
          session,
          format: LocalBookFormat.epub,
          filename: 'book.epub',
          cancellation: CancellationSource().token,
          chooseEncoding: (_) async => TxtEncoding.utf8,
        );
        expect(decoded.chapters, native.content.chapters);
        expect(decoded.auxiliaryChapters, native.content.auxiliaryChapters);
        expect(
          decoded.navigation.map((n) => n.toJson()),
          native.content.navigation.map((n) => n.toJson()),
        );
        expect(
          decoded.links.map((l) => l.toJson()),
          native.content.links.map((l) => l.toJson()),
        );
        expect(session.opens, 1);
        expect(session.handoffs, 1);
        expect(session.artifacts!.$2, legacy.presentations);
      },
    );
  }

  test(
    'optional resource failure retains native content and records a failed rendition attempt',
    () async {
      final files = epubFiles();
      files['OPS/text/a.xhtml'] = utf8.encode(
        '''<html><head><style>
.unused{background-image:url(../oversized.woff2)}
</style></head><body><p style="position:absolute">Native fallback.</p></body></html>''',
      );
      files['OPS/oversized.woff2'] = Uint8List(8 * 1024 * 1024 + 1);
      final session = _Session(zipFiles(files, compress: false));
      final native = EpubParser(
        session.bytes,
        session.key,
        'book.epub',
      ).parse().content;
      final result = await const BookDecoder().decode(
        session,
        format: LocalBookFormat.epub,
        filename: 'book.epub',
        cancellation: CancellationSource().token,
        chooseEncoding: (_) async => TxtEncoding.utf8,
      );
      expect(result.chapters, native.chapters);
      expect(session.handoffs, 1);
      expect(session.artifacts, isNull);
    },
  );
}
