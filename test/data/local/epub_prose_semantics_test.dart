import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'epub_structure_test.dart' show parse;
import 'support/epub_fixtures.dart';

List<ParagraphBlock> paragraphs(String body) {
  final files = epubFiles();
  files['OPS/text/a.xhtml'] = utf8.encode('<html><body>$body</body></html>');
  return parse(
    files,
  ).content.chapters.first.blocks.whereType<ParagraphBlock>().toList();
}

void main() {
  test('invalid declarations do not override valid whitespace styles', () {
    expect(
      paragraphs(
        '<p style="white-space:pre;white-space:invalid"> A  B </p>',
      ).single.text,
      ' A  B ',
    );
  });
  test('pre-line collapses whitespace across span boundaries', () {
    expect(
      paragraphs(
        '<p style="white-space:pre-line">A <span>  B </span>\n<span> C</span></p>',
      ).single.text,
      'A B\nC',
    );
  });
  test('pre and pre-wrap preserve whitespace across inline nodes', () {
    for (final mode in ['pre', 'pre-wrap']) {
      final blocks = paragraphs(
        '<p style="white-space:$mode">  A<span>  B\n C</span>  </p>',
      );
      expect(blocks.single.text, '  A  B\n C  ');
    }
  });
  test('pre-line keeps lines while collapsing horizontal whitespace', () {
    expect(
      paragraphs(
        '<p style="white-space:pre-line">A  B\n  C<br/>D</p>',
      ).single.text,
      'A B\nC\nD',
    );
  });
  test('normal override of inherited pre and following siblings', () {
    final blocks = paragraphs(
      '<div style="white-space:pre"><p style="white-space:normal"> A\n B </p></div><p>C\n D</p>',
    );
    expect(blocks.map((e) => e.text), ['A B', 'C D']);
  });
  test('hidden parent permits visible child but display none does not', () {
    final blocks = paragraphs(
      '<div style="visibility:hidden"><p>secret<span style="visibility:visible">shown</span>secret</p></div><div style="display:none"><p style="visibility:visible">absent</p></div><p>tail</p>',
    );
    expect(blocks.map((e) => e.text), ['shown', 'tail']);
  });
  test('hidden inline images do not leak visibility to following content', () {
    expect(
      paragraphs(
        '<p>A<img style="visibility:hidden" src="missing"/>B</p><p>C</p>',
      ).map((e) => e.text).join(),
      'ABC',
    );
  });
  test('wide spaces and NBSP survive normal source whitespace processing', () {
    expect(paragraphs('<p>　A&nbsp;B<br/>C</p>').single.text, '　A\u00a0B\nC');
  });
}
