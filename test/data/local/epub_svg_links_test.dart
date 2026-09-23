import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';

import 'support/epub_fixtures.dart';

EpubParser svgLinksParser({
  List<String> targets = const ['b.xhtml#b'],
  bool repeat = false,
  bool unsupported = false,
}) {
  final files = epubFiles();
  final opf = files.keys.firstWhere((p) => p.endsWith('.opf'));
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
  files['OPS/notes.xhtml'] = utf8.encode(
    '<html><body><p id="note">Auxiliary note.</p></body></html>',
  );
  files['OPS/text/a.xhtml'] = utf8.encode('''<html><body>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="10 20 100 200">
<image x="10" y="20" width="100" height="200" href="../images/星 空.png"/>
${unsupported ? '<path d="M0 0L1 1"/>' : ''}
${[for (var i = 0; i < targets.length; i++) '''<a ${i.isEven ? 'xlink:href' : 'href'}="${const HtmlEscape(HtmlEscapeMode.attribute).convert(targets[i])}" target="_top">
<rect x="10" y="${60 + i * 10}" width="30" height="10" fill-opacity="0"/>
<text x="10" y="${65 + i * 10}">Chapter ${i + 1}</text><title>Go ${i + 1}</title></a>'''].join()}
</svg></body></html>''');
  return EpubParser(
    zipFiles(files),
    LocalBookIdentity.book('e' * 64),
    'fixture.epub',
    includePresentations: true,
  );
}

void main() {
  test(
    'SVG rect links share chapter/fragment resolution and round-trip in the side table',
    () {
      final parser = svgLinksParser(
        targets: [
          'b.xhtml#b',
          '../notes.xhtml#note',
          '#missing',
          'https://example.test',
          '../../../escape',
          '%2fetc/passwd',
          'file:///etc/passwd',
          'missing.xhtml',
        ],
        repeat: true,
      );
      final content = parser.parse().content;
      final links = content.links.where((l) => l.region != null).toList();
      expect(links, hasLength(16));
      final first = links.first;
      expect(first.label, 'Go 1');
      expect(first.target, content.chapters.last.key);
      expect(first.targetBlockKey, isNotNull);
      expect(first.region!.left, 0);
      expect(first.region!.top, .2);
      expect(first.region!.right, .3);
      expect(first.region!.bottom, .25);
      expect(first.region!.aspectRatio, .5);
      expect(links[1].target, content.auxiliaryChapters.single.key);
      expect(links[2].unavailable, LocalLinkUnavailable.missingAnchor);
      expect(links[3].unavailable, LocalLinkUnavailable.external);
      expect(links[4].unavailable, LocalLinkUnavailable.unsupported);
      expect(links[5].unavailable, LocalLinkUnavailable.unsupported);
      expect(links[6].unavailable, LocalLinkUnavailable.external);
      expect(links[7].target, isNull);
      expect(links[8].source, content.chapters[1].key);
      final restored = LocalContentLink.fromJson(
        jsonDecode(jsonEncode(first.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), first.toJson());
      final legacy = {...first.toJson()}..remove('region');
      expect(LocalContentLink.fromJson(legacy).region, isNull);
      final html = parser.presentations.values.first;
      expect(html, isNot(contains('xlink:href')));
      expect(html, isNot(contains('<a ')));
      expect(html, isNot(contains('example.test')));
      expect(html, contains("script-src 'none'"));
    },
  );

  test('same-resource SVG links keep the current spine occurrence', () {
    final content = svgLinksParser(
      targets: ['a.xhtml'],
      repeat: true,
    ).parse().content;
    for (final link in content.links.where((l) => l.region != null)) {
      expect(link.target, link.source);
    }
  });

  test('unsupported SVG does not publish orphan interactive regions', () {
    final parser = svgLinksParser(unsupported: true);
    final content = parser.parse().content;
    expect(parser.presentations, isEmpty);
    expect(content.links.where((l) => l.region != null), isEmpty);
  });

  test('link regions reject nonfinite and inverted geometry', () {
    for (final right in [double.nan, double.infinity, 1.1, -.1, 0.0]) {
      expect(
        () => LocalLinkRegion(
          left: 0,
          top: 0,
          right: right,
          bottom: 1,
          aspectRatio: .5,
        ),
        throwsArgumentError,
      );
    }
  });
}
