import 'dart:convert';
import 'package:shiori/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'support/epub_fixtures.dart';

final linkBookKey = LocalBookIdentity.book('d' * 64);
Map<String, List<int>> linkedEpub({bool repeated = false}) {
  final files = epubFiles();
  final opf = files.keys.firstWhere((k) => k.endsWith('.opf'));
  files[opf] = utf8.encode(
    utf8
        .decode(files[opf]!)
        .replaceFirst(
          '</manifest>',
          '<item id="notes" href="notes.xhtml" media-type="application/xhtml+xml"/><item id="last" href="last.xhtml" media-type="application/xhtml+xml"/></manifest>',
        )
        .replaceFirst(
          '<itemref idref="a"/>',
          repeated
              ? '<itemref idref="a"/><itemref idref="a"/>'
              : '<itemref idref="a"/>',
        )
        .replaceFirst(
          '<itemref idref="b"/>',
          '<itemref idref="b" linear="no"/><itemref idref="last"/>',
        ),
  );
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><body><h1>Start</h1><p id="origin">Original paragraph <a href="#origin">same</a> <a href="../notes.xhtml#note">note</a> <a href="b.xhtml#b">appendix</a> <a href="#absent">missing</a> <a href="https://example.test/private">external</a> <a href="../../../escape.xhtml">escape</a></p></body></html>',
  );
  files['OPS/notes.xhtml'] = utf8.encode(
    '<html><body><h1>Notes</h1><p id="note">Footnote body <a href="text/a.xhtml#origin">backlink</a></p></body></html>',
  );
  files['OPS/last.xhtml'] = utf8.encode(
    '<html><body><p>Final primary chapter.</p></body></html>',
  );
  return files;
}

void main() {
  test(
    'fragment targets retain normalized code-point offsets and legacy JSON',
    () {
      final files = linkedEpub(repeated: true);
      files['OPS/text/a.xhtml'] = utf8.encode('''<html><body>
      <p>  😀前文<sup><a id="b5" href="../notes.xhtml#a5">5</a></sup>后文
      <a href="#b5">same</a><span hidden id="hidden">hidden</span></p>
      <p><a href="#hidden">unavailable</a></p>
      <pre> 😀 <span id="pre">kept</span></pre>
      <p><a href="#pre">pre</a><a href="#empty">empty</a></p>
      <p>前😀<a id="empty"></a>后</p></body></html>''');
      files['OPS/notes.xhtml'] = utf8.encode('''<html><body>
      <p>注释<a id="a5" href="text/a.xhtml#b5">back</a></p>
      </body></html>''');
      final c = EpubParser(
        zipFiles(files),
        linkBookKey,
        'book',
      ).parse().content;
      final same = c.links.where((l) => l.label == 'same').toList();
      expect(same, hasLength(2));
      for (final link in same) {
        expect(link.target, link.source);
        expect(link.targetOffset, 3); // 😀 is one code point, not two.
      }
      final back = c.links.firstWhere((l) => l.label == 'back');
      expect(back.target, c.chapters.first.key);
      expect(back.targetOffset, 3);
      expect(c.links.firstWhere((l) => l.label == '5').targetOffset, 2);
      expect(c.links.firstWhere((l) => l.label == 'pre').targetOffset, 3);
      expect(c.links.firstWhere((l) => l.label == 'empty').targetOffset, 2);
      expect(
        c.links.firstWhere((l) => l.label == 'unavailable').targetOffset,
        isNull,
      );
      final json =
          jsonDecode(jsonEncode(back.toJson())) as Map<String, dynamic>;
      expect(LocalContentLink.fromJson(json).targetOffset, 3);
      json.remove('targetOffset');
      expect(LocalContentLink.fromJson(json).targetOffset, isNull);
      expect(
        () => LocalContentLink.fromJson({...json, 'targetOffset': -1}),
        throwsArgumentError,
      );
      expect(
        () => LocalContentLink.fromJson({
          ...json,
          'targetBlock': null,
          'targetOffset': 1,
        }),
        throwsArgumentError,
      );
    },
  );

  test(
    'authored links cover each paragraph and preserve inline Unicode ranges',
    () {
      final files = linkedEpub();
      files['OPS/text/a.xhtml'] = utf8.encode('''<html><body>
      <a href="b.xhtml#b"><p>【第三话】</p><p>Subtitle</p></a>
      <p>😀before <a href="b.xhtml#b">same <em>label</em></a> after <a href="#anchor">same label</a>.</p>
      <p id="anchor">Target</p></body></html>''');
      final content = EpubParser(
        zipFiles(files),
        linkBookKey,
        'book',
      ).parse().content;
      final chapter = content.chapters.first;
      final links = content.links
          .where((l) => l.source == chapter.key)
          .toList();
      expect(links, hasLength(4));
      final ranges = links.map((link) {
        final block =
            chapter.blocks.firstWhere((b) => b.blockKey == link.sourceBlockKey)
                as ParagraphBlock;
        return String.fromCharCodes(
          block.text.runes.skip(link.sourceOffset!).take(link.sourceLength!),
        );
      }).toList();
      expect(
        ranges,
        containsAll(['【第三话】', 'Subtitle', 'same label', 'same label']),
      );
      expect(links.every((l) => !l.isFootnote), isTrue);
      final inline = links
          .where((l) => l.sourceBlockKey == chapter.blocks[2].blockKey)
          .toList();
      expect(inline.map((l) => l.sourceOffset), [8, 25]);
      expect(inline.last.target, chapter.key);
      final restored = LocalContentLink.fromJson(
        jsonDecode(jsonEncode(inline.first.toJson())) as Map<String, dynamic>,
      );
      expect(restored.sourceLength, 10);
      expect(restored.isFootnote, isFalse);
    },
  );
  test(
    'manifest auxiliary document is outside catalog and continuous order skips linear=no',
    () {
      final content = EpubParser(
        zipFiles(linkedEpub()),
        linkBookKey,
        'book',
      ).parse().content;
      expect(content.chapters.length, 3);
      expect(content.auxiliaryChapters.length, 1);
      expect(content.readingOrder, [
        content.chapters.first.key,
        content.chapters.last.key,
      ]);
      expect(
        content.links.firstWhere((l) => l.label == 'note').target,
        content.auxiliaryChapters.single.key,
      );
      expect(
        content.links.firstWhere((l) => l.label == 'note').targetBlockKey,
        content.auxiliaryChapters.single.blocks[1].blockKey,
      );
      expect(
        content.links.firstWhere((l) => l.label == 'backlink').target,
        content.chapters.first.key,
      );
    },
  );
  test(
    'same document links retain each occurrence; cross document targets first',
    () {
      final c = EpubParser(
        zipFiles(linkedEpub(repeated: true)),
        linkBookKey,
        'book',
      ).parse().content;
      for (final chapter in c.chapters.take(2)) {
        final same = c.links.singleWhere(
          (l) => l.source == chapter.key && l.label == 'same',
        );
        expect(same.target, chapter.key);
        expect(same.sourceBlockKey, chapter.blocks[1].blockKey);
      }
      expect(
        c.links.singleWhere((l) => l.label == 'backlink').target,
        c.chapters.first.key,
      );
    },
  );
  test(
    'missing anchors and external or escaping links never become targets or persist URLs',
    () {
      final c = EpubParser(
        zipFiles(linkedEpub()),
        linkBookKey,
        'book',
      ).parse().content;
      expect(
        c.links.firstWhere((l) => l.label == 'missing').unavailable,
        LocalLinkUnavailable.missingAnchor,
      );
      expect(
        c.links.firstWhere((l) => l.label == 'external').unavailable,
        LocalLinkUnavailable.external,
      );
      expect(
        c.links.firstWhere((l) => l.label == 'escape').unavailable,
        LocalLinkUnavailable.unsupported,
      );
      expect(
        jsonEncode(c.links.map((l) => l.toJson()).toList()),
        isNot(contains('example.test')),
      );
    },
  );
  test(
    'missing auxiliary and hidden anchor do not jump to a neighboring block',
    () {
      final files = linkedEpub();
      files.remove('OPS/notes.xhtml');
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<html><body><p><a href="#hidden">hidden target</a><a href="../notes.xhtml#note">missing document</a></p><p hidden id="hidden">hidden</p><p>Visible next</p></body></html>',
      );
      final c = EpubParser(
        zipFiles(files),
        linkBookKey,
        'book',
      ).parse().content;
      expect(c.links[0].unavailable, LocalLinkUnavailable.missingAnchor);
      expect(c.links[1].unavailable, LocalLinkUnavailable.missingDocument);
    },
  );
  test('link sidecar roundtrips without changing content identity', () {
    final files = linkedEpub();
    final linked = EpubParser(
      zipFiles(files),
      linkBookKey,
      'book',
    ).parse().content;
    files['OPS/text/a.xhtml'] = utf8.encode(
      utf8
          .decode(files['OPS/text/a.xhtml']!)
          .replaceAll(RegExp(r'<a[^>]*>'), '')
          .replaceAll('</a>', ''),
    );
    final plain = EpubParser(
      zipFiles(files),
      linkBookKey,
      'book',
    ).parse().content;
    expect(linked.chapters.first, plain.chapters.first);
    for (final link in linked.links) {
      expect(LocalContentLink.fromJson(link.toJson()).toJson(), link.toJson());
    }
  });
  test('auxiliary traversal is bounded even in a chain', () {
    final files = linkedEpub();
    final opf = files.keys.firstWhere((k) => k.endsWith('.opf'));
    files[opf] = utf8.encode(
      utf8
          .decode(files[opf]!)
          .replaceFirst(
            '</manifest>',
            '${List.generate(66, (i) => '<item id="n$i" href="n$i.xhtml" media-type="application/xhtml+xml"/>').join()}</manifest>',
          ),
    );
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><body><p><a href="../n0.xhtml">go</a></p></body></html>',
    );
    for (var i = 0; i < 66; i++) {
      files['OPS/n$i.xhtml'] = utf8.encode(
        '<html><body><p>Note $i <a href="n${i + 1}.xhtml">next</a></p></body></html>',
      );
    }
    expect(
      () => EpubParser(zipFiles(files), linkBookKey, 'book').parse(),
      throwsA(
        isA<LocalParseException>().having(
          (e) => e.problem,
          'limit',
          LocalParseProblem.tooLarge,
        ),
      ),
    );
  });
}
