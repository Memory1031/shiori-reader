import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/shared/epub_link_address.dart';

import 'support/epub_fixtures.dart';

Map<String, List<int>> htmlLinkFiles({bool repeat = false}) {
  final files = epubFiles();
  final opf = files.keys.firstWhere((path) => path.endsWith('.opf'));
  files[opf] = utf8.encode(
    utf8
        .decode(files[opf]!)
        .replaceFirst(
          '</manifest>',
          '<item id="notes" href="notes.xhtml" media-type="application/xhtml+xml"/></manifest>',
        )
        .replaceFirst(
          '<itemref idref="a"/>',
          repeat
              ? '<itemref idref="a"/><itemref idref="a"/>'
              : '<itemref idref="a"/>',
        ),
  );
  files['OPS/text/a.xhtml'] = utf8.encode('''<html><head><style>
.tilt{transform:rotate(14deg);display:inline-block;}
td{padding:0.9em 0 0;}a{color:#02932e;text-decoration:none;}
</style></head><body><h1>Contents</h1><table><tbody>
<tr><td>1.</td><td><a href="b.xhtml#b" target="_blank">Same <span class="tilt">😀合</span></a></td></tr>
<tr><td>2.</td><td><a href="../notes.xhtml#note">Same 😀合</a></td></tr>
<tr><td>3.</td><td><a href="#own">Within</a></td></tr>
<tr><td>4.</td><td><a href="#absent">Missing</a></td></tr>
<tr><td>5.</td><td><a href="https://example.invalid/private">External</a></td></tr>
</tbody></table><a href="b.xhtml#b"><p>Across</p><p>Paragraphs</p></a>
<p id="own">Local destination</p></body></html>''');
  files['OPS/text/b.xhtml'] = utf8.encode('''<html><body>
<p>BEFORE ${'正文😀跨页内容。' * 360}<span id="b">DESTINATION</span>${'后文。' * 30}</p>
</body></html>''');
  files['OPS/notes.xhtml'] = utf8.encode(
    '<html><body><p id="note">AUXILIARY_DESTINATION</p></body></html>',
  );
  return files;
}

EpubParser htmlLinksParser({bool repeat = false, bool presentations = true}) =>
    EpubParser(
      zipFiles(htmlLinkFiles(repeat: repeat)),
      LocalBookIdentity.book('b' * 64),
      'synthetic.epub',
      includePresentations: presentations,
    );

void main() {
  test(
    'static HTML anchors preserve layout and map by identity to resolved links',
    () {
      final parser = htmlLinksParser(repeat: true);
      final content = parser.parse().content;
      final source = content.chapters.first;
      final links = content.links
          .where((link) => link.source == source.key)
          .toList();
      final document = html.parse(parser.presentations[source.key.chapterId]!);
      final anchors = document.querySelectorAll('a[href]');
      expect(anchors, hasLength(6));
      expect(anchors.map((a) => epubLinkId(a.attributes['href'])), [
        0,
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(document.querySelectorAll('table tr'), hasLength(5));
      expect(document.querySelector('.tilt')!.text, '😀合');
      expect(document.querySelector('style')!.text, contains('rotate(14deg)'));
      expect(document.querySelector('style')!.text, contains('padding:0.9em'));
      expect(document.querySelectorAll('[target],[onclick]'), isEmpty);
      expect(document.outerHtml, isNot(contains('example.invalid')));
      expect(document.outerHtml, isNot(contains('b.xhtml#b')));
      expect(document.outerHtml, contains("script-src 'none'"));
      expect(links.where((link) => link.presentationId == 5), hasLength(2));
      expect(links.first.target, content.chapters.last.key);
      expect(links.first.targetOffset, greaterThan(0));
      expect(links[1].target, content.auxiliaryChapters.single.key);
      expect(links[2].target, source.key);
      expect(links[3].unavailable, LocalLinkUnavailable.missingAnchor);
      expect(links[4].unavailable, LocalLinkUnavailable.external);
      final repeated = content.links
          .where((link) => link.source == content.chapters[1].key)
          .toList();
      expect(
        repeated.map((link) => link.presentationId),
        links.map((link) => link.presentationId),
      );
      expect(repeated[2].target, content.chapters[1].key);
      final decoded = htmlLinksParser(presentations: false).parse().content;
      expect(
        decoded.links.map((link) => link.toJson()),
        htmlLinksParser().parse().content.links.map((link) => link.toJson()),
      );
    },
  );

  test(
    'opaque anchor codec preserves old links and rejects arbitrary addresses',
    () {
      final link = htmlLinksParser().parse().content.links.first;
      expect(
        LocalContentLink.fromJson(link.toJson()).presentationId,
        link.presentationId,
      );
      final legacy = {...link.toJson()}..remove('presentationId');
      expect(LocalContentLink.fromJson(legacy).presentationId, isNull);
      for (final value in [-1, 10000]) {
        expect(
          () => LocalContentLink.fromJson({
            ...link.toJson(),
            'presentationId': value,
          }),
          throwsArgumentError,
        );
      }
      for (final url in [
        '${epubLinkPrefix}00',
        '${epubLinkPrefix}10000',
        '${epubLinkAddress(0)}#fragment',
        'shiori-link://0',
        'SHIORI-link:0',
        'https://example.invalid',
        'javascript:alert(1)',
      ]) {
        expect(epubLinkId(url), isNull);
      }
    },
  );
}
