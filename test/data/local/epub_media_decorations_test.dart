import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

ParsedEpub decorationsEpub(String body, [String css = '']) {
  final files = epubFiles();
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><head><style>$css</style></head><body>$body</body></html>',
  );
  return EpubParser(
    zipFiles(files),
    LocalBookIdentity.book('a' * 64),
    'synthetic.epub',
  ).parse();
}

void main() {
  test('image authored width remains independent of native audio controls', () {
    final chapter = decorationsEpub(
      '<p><img src="../images/星 空.png" style="width:50%"/></p><p>Tail</p>',
    ).content.chapters.first;
    expect(
      chapter.blocks.whereType<ImageBlock>().single.layout!.widthLength,
      LayoutLength(.5, LayoutUnit.fraction),
    );
  });
  test('double, ridge and groove preserve authored border styles', () {
    for (final entry in {
      'double': 'doubleLine',
      'ridge': 'ridge',
      'groove': 'groove',
    }.entries) {
      final chapter = decorationsEpub(
        '<div class="frame"><p>Frame 😀</p><p>Tail</p></div>',
        '.frame{border:6px ${entry.key} #4682b4;padding:8px}',
      ).content.chapters.first;
      expect(chapter.blocks.first.box!.borders!.top!.style.name, entry.value);
      expect(chapter.blocks.first.box!.group, chapter.blocks.last.box!.group);
      expect(ChapterContent.fromJson(chapter.toJson()), chapter);
      expect(
        chapter.blocks.first.blockKey,
        ParagraphBlock(text: 'Frame 😀').blockKey,
      );
    }
  });
  test('one-cell heading keeps the outer background and uniform radius', () {
    final chapter = decorationsEpub(
      '<div class="frame"><table><tr><td>TRACK</td></tr></table></div><p>Tail</p>',
      '.frame{border-radius:12px;background-color:#383838;width:6em;padding:1px 3px}',
    ).content.chapters.first;
    final box = chapter.blocks.first.box!;
    expect(box.toJson()['radius'], {'value': 12.0, 'unit': 'px'});
    expect(box.backgroundColor, 0xff383838);
    expect(ChapterContent.fromJson(chapter.toJson()), chapter);
    final legacy = Map<String, dynamic>.from(box.toJson())..remove('radius');
    expect(BlockBox.fromJson(legacy).toJson().containsKey('radius'), isFalse);
  });
  test('a flattened single table cell keeps its own text alignment', () {
    final chapter = decorationsEpub(
      '<div class="frame"><table><tr><td class="label">TRACK</td></tr></table></div>'
          '<div class="frame"><table><tr><td class="label">CAST</td></tr></table></div>'
          '<table><tr><td style="text-align:right"><p style="text-align:left">Override</p></td></tr></table>'
          '<table><tr><td style="text-align:center">First</td><td>Second</td></tr></table>',
      '.frame{border-radius:12px;background-color:#383838;width:6em;padding:1px 3px}'
          '.label{text-align:center;text-indent:0}',
    ).content.chapters.first;
    final paragraphs = chapter.blocks.whereType<ParagraphBlock>().toList();
    expect(paragraphs[0].alignment, ParagraphAlignment.center);
    expect(paragraphs[1].alignment, ParagraphAlignment.center);
    expect(paragraphs[2].alignment, ParagraphAlignment.start);
    expect(paragraphs[3].alignment, ParagraphAlignment.start);
    expect(ChapterContent.fromJson(chapter.toJson()), chapter);
  });
}
