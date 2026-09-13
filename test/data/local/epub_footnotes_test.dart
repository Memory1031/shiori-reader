import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/local_content_links.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

void main() {
  final key = NovelKey(sourceId: SourceId('local'), novelId: 'notes');
  test('image noteref stays inline; hidden note is inert and round trips', () {
    final files = epubFiles();
    files['OPS/text/a.xhtml'] = utf8.encode('''
      <html xmlns:epub="http://www.idpf.org/2007/ops"><body>
      <p>😀Before<a epub:type="noteref" href="#n"><img src="note.png"></a>after.</p>
      <aside hidden epub:type="footnote" id="n"><a href="#origin"><p>First note.</p><p>Second line.</p></a><script>bad()</script><a role="doc-backlink">back</a></aside>
      <p>Next paragraph.</p></body></html>''');
    final parsed = EpubParser(zipFiles(files), key, 'synthetic.epub').parse();
    final chapter = parsed.content.chapters.first;
    expect(chapter.blocks.whereType<ImageBlock>(), isEmpty);
    expect(chapter.blocks.whereType<ParagraphBlock>().map((b) => b.text), [
      '😀Before⁽¹⁾after.',
      'Next paragraph.',
    ]);
    final note = parsed.content.links.single;
    expect(note.sourceOffset, 7);
    expect(note.sourceBlockKey, chapter.blocks.first.blockKey);
    expect(note.footnoteText, 'First note.\nSecond line.');
    expect(note.unavailable, isNull);
    final restored = LocalContentLink.fromJson(
      jsonDecode(jsonEncode(note.toJson())) as Map<String, dynamic>,
    );
    expect(restored.sourceOffset, note.sourceOffset);
    expect(restored.footnoteText, note.footnoteText);
    final legacy = note.toJson()
      ..remove('sourceOffset')
      ..remove('footnoteText');
    expect(LocalContentLink.fromJson(legacy).isFootnote, isFalse);
  });

  test('cross-document and unavailable notes never become image blocks', () {
    final files = epubFiles();
    files['OPS/text/a.xhtml'] = utf8.encode('''<html><body><p>
      Text<a role="doc-noteref" href="b.xhtml#n">1</a>
      <a role="doc-noteref" href="#missing"><img src="note.png"></a>
      <a role="doc-noteref" href="https://example.test/#n">3</a>
      <a role="doc-noteref" href="../../../escape">4</a>
      <a href="b.xhtml">ordinary link</a></p></body></html>''');
    files['OPS/text/b.xhtml'] = utf8.encode(
      '<html><body><p>Body.</p><aside role="doc-footnote" id="n"><p>Remote within book.</p></aside></body></html>',
    );
    final content = EpubParser(
      zipFiles(files),
      key,
      'synthetic.epub',
    ).parse().content;
    final notes = content.links.where((l) => l.isFootnote).toList();
    expect(notes, hasLength(4));
    expect(notes.first.footnoteText, 'Remote within book.');
    expect(notes.map((l) => l.unavailable), [
      null,
      LocalLinkUnavailable.missingAnchor,
      LocalLinkUnavailable.external,
      LocalLinkUnavailable.unsupported,
    ]);
    expect(content.chapters.first.blocks.whereType<ImageBlock>(), isEmpty);
    expect(
      content.links.where((l) => !l.isFootnote).single.label,
      'ordinary link',
    );
  });

  test('oversized annotations are unavailable and ordinary asides remain', () {
    final files = epubFiles();
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><body><p>A<a role="doc-noteref" href="#n">1</a>B</p><aside role="doc-footnote" id="n">${'x' * 16385}</aside><aside>Ordinary aside.</aside></body></html>',
    );
    final content = EpubParser(
      zipFiles(files),
      key,
      'synthetic.epub',
    ).parse().content;
    expect(content.links.single.unavailable, LocalLinkUnavailable.unsupported);
    expect(
      content.chapters.first.blocks.whereType<ParagraphBlock>().last.text,
      'Ordinary aside.',
    );
  });
}
