import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/epub/epub_diagnostics.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'epub_structure_test.dart' show parse, replace;
import 'parsers_test.dart' show ParserSession;
import 'support/epub_fixtures.dart';

void main() {
  test('missing image and anchor produce closed diagnostic codes', () {
    final files = epubFiles();
    files.remove('OPS/images/星 空.png');
    final report = parse(files).diagnostics;
    expect(
      report.codes,
      containsAll([
        EpubDiagnosticCode.missingImage,
        EpubDiagnosticCode.noUsableImage,
        EpubDiagnosticCode.missingFragment,
      ]),
    );
    expect(() => report.codes.clear(), throwsUnsupportedError);
  });
  test('missing and malformed navigation explain synthetic fallback', () {
    for (final ncx in [null, '<ncx>']) {
      final files = epubFiles(ncx: true);
      if (ncx == null) {
        files.remove('OPS/toc.ncx');
      } else {
        files['OPS/toc.ncx'] = utf8.encode(ncx);
      }
      expect(
        parse(files).diagnostics.codes,
        containsAll([
          ncx == null
              ? EpubDiagnosticCode.missingNavigation
              : EpubDiagnosticCode.unusableNavigation,
          EpubDiagnosticCode.syntheticNavigation,
        ]),
      );
    }
  });
  test('unsupported image and missing navigation target are distinguished', () {
    final files = epubFiles();
    files['OPS/images/星 空.png'] = utf8.encode('not an image');
    replace(files, 'OPS/nav.xhtml', 'text/a.xhtml#one', 'missing.xhtml');
    expect(
      parse(files).diagnostics.codes,
      containsAll([
        EpubDiagnosticCode.unsupportedImage,
        EpubDiagnosticCode.missingNavigationTarget,
      ]),
    );
  });
  test('large warning sets truncate without discarding readable content', () {
    final files = epubFiles();
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><body>${List.filled(150, '<img src="missing.png"/>').join()}<p>tail</p></body></html>',
    );
    final result = parse(files);
    expect(result.diagnostics.codes, hasLength(100));
    expect(result.diagnostics.truncated, isTrue);
    expect(result.content.chapters, hasLength(2));
  });
  test('snapshots do not change when collector continues', () {
    final collector = EpubDiagnosticCollector();
    final before = collector.snapshot();
    collector.add(EpubDiagnosticCode.spineFallback);
    expect(before.codes, isEmpty);
    expect(collector.snapshot().codes, [EpubDiagnosticCode.spineFallback]);
  });
  test(
    'worker report reaches optional decoder slot and fatal input still fails',
    () async {
      final slot = EpubDiagnosticSlot();
      final decoder = BookDecoder(epubDiagnostics: slot);
      Future<void> decode(Map<String, List<int>> files) async {
        await decoder.decode(
          ParserSession(zipFiles(files)),
          format: LocalBookFormat.epub,
          filename: '/private/secret/title.epub',
          cancellation: CancellationSource().token,
          chooseEncoding: (p) async => p.samples.keys.first,
        );
      }

      await decode(epubFiles());
      expect(slot.latest?.codes, contains(EpubDiagnosticCode.missingFragment));
      slot.clear();
      final files = epubFiles();
      replace(files, 'OPS/nav.xhtml', 'text/a.xhtml#one', '../../escape');
      await expectLater(decode(files), throwsA(isA<LocalParseException>()));
      expect(slot.latest, isNull);
    },
  );
}
