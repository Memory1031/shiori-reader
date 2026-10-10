import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';
import 'support/synthetic_font.dart';

String decorationTable({
  String text = '4',
  double leading = 25,
  double trailing = 25,
  String rowAttributes = '',
  String leadingAttributes = '',
  String leadingContent = '',
  String trailingStyle = '',
  String centerStyle = '',
  String contentStyle = '',
  String extraRow = '',
}) =>
    '''<table style="border-collapse:collapse;width:100%;border-left:6px solid #4682b4;border-right:6px solid #4682b4">
<tbody><tr $rowAttributes>
<td $leadingAttributes style="width:$leading%;border-bottom:6px solid #4682b4">$leadingContent</td>
<td style="$centerStyle"><p id="number" style="text-align:center;margin:0;padding:1em 20px .3em;$contentStyle">$text</p></td>
<td style="width:$trailing%;border-bottom:6px solid #4682b4;$trailingStyle"></td>
</tr>$extraRow</tbody></table>''';

ParsedEpub parseDecoration(String body, {bool assets = false}) {
  final files = epubFiles();
  files['OPS/text/a.xhtml'] = utf8.encode(
    '''<html><head>${assets ? '<style>@font-face{font-family:badge;src:url(../fonts/badge.ttf)} p{font-family:badge}</style>' : ''}</head><body>$body</body></html>''',
  );
  if (assets) {
    files['OPS/fonts/badge.ttf'] = syntheticFont();
    files['OPS/images/badge.png'] = tinyPng;
  }
  return EpubParser(
    zipFiles(files),
    LocalBookIdentity.book('a' * 64),
    'synthetic.epub',
  ).parse();
}

void main() {
  test('single row preserves the two bottom arms and side borders', () {
    final parsed = parseDecoration(decorationTable());
    final block = parsed.content.chapters.first.blocks.single;
    expect(block.toJson()['text'], '4');
    expect(block.box!.toJson()['decorationColumns'], {
      'leadingFraction': .25,
      'trailingFraction': .25,
    });
    expect(block.box!.borders!.bottom!.width.value, 6);
    expect(block.box!.borders!.left!.width.value, 6);
    expect(block.box!.borders!.right!.width.value, 6);
    expect(block.layout, isNotNull);
    expect(block.layout!.borders!.bottom!.style, BoxBorderStyle.none);
  });

  test(
    'bottom arms retain the cell color rather than the table border color',
    () {
      final html = decorationTable()
          .replaceFirst('width:100%;', 'width:100%;border-color:blue;')
          .replaceAll(
            'border-bottom:6px solid #4682b4',
            'color:red;border-bottom-style:solid;border-bottom-width:6px',
          );
      final block = parseDecoration(html).content.chapters.first.blocks.single;
      expect(block.box!.borders!.bottom!.color, 0xffff0000);
      expect(block.box!.borders!.left!.color, 0xff4682b4);
    },
  );

  test(
    'an already supported colored rounded paragraph keeps its fallback box',
    () {
      final block = parseDecoration(
        decorationTable(
          contentStyle: 'background-color:blue;border-radius:4px',
        ),
      ).content.chapters.first.blocks.single;
      expect(block.box!.toJson(), isNot(contains('decorationColumns')));
      expect(block.box!.backgroundColor, 0xff0000ff);
      expect(block.box!.radius!.value, 4);
    },
  );

  test('shared vertical cell padding is applied once around the content', () {
    final block = parseDecoration(
      '<style>td{padding:3px 0}</style>${decorationTable()}',
    ).content.chapters.first.blocks.single;
    expect(block.box!.toJson(), contains('decorationColumns'));
    expect(block.box!.paddingEdges!.top!.value, 3);
    expect(block.box!.paddingEdges!.bottom!.value, 3);
    expect(block.layout!.paddingEdges!.top!.unit, LayoutUnit.em);
  });

  test('percentages come from CSS and decorative data is nonsemantic', () {
    final first = parseDecoration(
      decorationTable(leading: 20, trailing: 30),
    ).content.chapters.first;
    final second = parseDecoration(
      decorationTable(leading: 15, trailing: 35),
    ).content.chapters.first;
    expect(first.blocks.single.box!.toJson()['decorationColumns'], {
      'leadingFraction': .2,
      'trailingFraction': .3,
    });
    expect(first.blocks.single.blockKey, second.blocks.single.blockKey);
    expect(first.blocks.single, isNot(second.blocks.single));
    expect(ChapterContent.fromJson(first.toJson()), first);
    final legacy = ParagraphBlock(
      text: 'Legacy',
      box: BlockBox(group: 7, borderWidth: 2),
    );
    expect(legacy.box!.toJson(), isNot(contains('decorationColumns')));
    expect(ContentBlock.fromJson(legacy.toJson()), legacy);
  });

  test('text, unicode link ranges, background and fonts remain intact', () {
    final parsed = parseDecoration(
      '${decorationTable(text: '😀<a href="#target">é</a>', contentStyle: 'background:url(../images/badge.png) no-repeat center;background-size:2.2em;color:white')}<p id="target">Tail</p><p><a href="#number">Back</a></p>',
      assets: true,
    );
    final chapter = parsed.content.chapters.first;
    final block = chapter.blocks.first as ParagraphBlock;
    expect(block.text, '😀é');
    expect(block.box!.toJson(), contains('decorationColumns'));
    expect(block.layout!.backgroundImage, isNotNull);
    expect(block.inlineStyles.any((s) => s.fonts.isNotEmpty), isTrue);
    expect(block.inlineImages, isEmpty);
    expect(chapter.blocks.whereType<ImageBlock>(), isEmpty);
    final link = parsed.content.links.firstWhere(
      (l) => l.sourceBlockKey == block.blockKey,
    );
    expect(link.sourceOffset, 1);
    expect(link.sourceLength, 2);
    expect(parsed.content.links.last.targetBlockKey, block.blockKey);
    expect(ChapterContent.fromJson(chapter.toJson()), chapter);
  });

  test('unsupported structures keep all original text without decoration', () {
    for (final html in [
      decorationTable(extraRow: '<tr><td></td><td>Second</td><td></td></tr>'),
      decorationTable(leadingAttributes: 'colspan="1"'),
      decorationTable(rowAttributes: 'style="direction:rtl"'),
      decorationTable(leadingContent: 'Side'),
      decorationTable(text: '<table><tr><td>Nested</td></tr></table>'),
      decorationTable(text: '<ruby>Base<rt>Note</rt></ruby>'),
      decorationTable(text: '<img src="../images/p.png"/>Body'),
      decorationTable(trailingStyle: 'border-bottom-color:red'),
      decorationTable().replaceAll('#4682b4', 'currentColor'),
      decorationTable(centerStyle: 'padding:1em'),
      decorationTable(centerStyle: 'display:block'),
      decorationTable(text: '<span style="display:block">Changed flow</span>'),
      '<style>td{padding:1em 0} td:nth-child(2){font-size:2em}</style>${decorationTable()}',
      decorationTable(
        text: '<a href="#number">Link</a>',
        contentStyle: 'background-color:blue;padding:1em',
      ),
      decorationTable(leading: 60, trailing: 50),
      '<div style="border:1px solid red">${decorationTable()}</div>',
    ]) {
      final blocks = parseDecoration(html).content.chapters.first.blocks;
      expect(blocks, isNotEmpty, reason: html);
      expect(
        blocks.every((b) => b.box?.toJson()['decorationColumns'] == null),
        isTrue,
        reason: html,
      );
    }
    final side = parseDecoration(
      decorationTable(leadingContent: 'Side'),
    ).content.chapters.first.blocks;
    expect(side.map((b) => b.toJson()['text']).join(), contains('Side'));
    final multi = parseDecoration(
      decorationTable(extraRow: '<tr><td></td><td>Second</td><td></td></tr>'),
    ).content.chapters.first.blocks;
    expect(multi.map((b) => b.toJson()['text']).join(), '4Second');
  });
}
