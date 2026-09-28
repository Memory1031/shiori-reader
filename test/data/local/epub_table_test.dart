import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'epub_prose_semantics_test.dart' show paragraphs;

const tableCss = '''<style>
.schedule table {border-collapse:collapse}
.schedule td:nth-child(1) {width:2.5em; padding-right:.5em; border-right:2px solid black; vertical-align:top; white-space:nowrap}
.schedule td:nth-child(2) {padding-left:.5em}
.gap {height:.8em}
</style>''';
String tableHtml(String rows) =>
    '$tableCss<div class="schedule"><table><tbody>$rows</tbody></table></div>';

void main() {
  test(
    'two cell source ranges, arbitrary labels, gaps and identities round trip',
    () {
      const rows =
          '<tr><td>Gate😀</td><td>开头<b>加粗</b><a href="#end">链接</a>é正文</td></tr><tr class="gap"><td></td><td></td></tr><tr><td>B</td><td>尾行</td></tr>';
      final blocks = paragraphs(tableHtml(rows));
      final flat = paragraphs('<table>$rows</table>');
      expect(blocks.length, 2);
      expect(blocks.map((b) => b.text), flat.map((b) => b.text));
      expect(blocks.map((b) => b.blockKey), flat.map((b) => b.blockKey));
      expect(blocks.first.tableRow, isNotNull);
      final meta = blocks.first.tableRow!;
      expect(meta.leftEnd, 5);
      expect(meta.rightStart, 5);
      expect(meta.gapAfterEm, .8);
      expect(blocks.last.tableRow!.group, meta.group);
      expect(blocks.first.inlineStyles.single.start, 7);
      for (final b in blocks) {
        expect(ContentBlock.fromJson(b.toJson()), b);
        expect(b.withOccurrence(3).tableRow, b.tableRow);
      }
    },
  );
  test('cascade shorthand sides, important and hidden rows', () {
    final blocks = paragraphs(
      tableHtml('''
      <tr><td style="padding:0 1em 0 0 !important; padding-right:3em">A</td><td>Body</td></tr>
      <tr class="gap" hidden><td></td><td></td></tr>
      <tr style="display:none"><td>Hidden</td><td>Secret</td></tr>
    '''),
    );
    expect(blocks.length, 1);
    expect(blocks.single.tableRow!.leftPaddingEm, 1);
    expect(blocks.single.tableRow!.gapAfterEm, 0);
  });
  test('any unsupported row rejects the entire table without losing prose', () {
    for (final row in [
      '<tr><td>A</td><td>B</td><td>C</td></tr>',
      '<tr><td colspan="2">A</td><td>B</td></tr>',
      '<tr><td rowspan="1">A</td><td>B</td></tr>',
      '<tr><td>A</td><td><table><tr><td>Nested</td></tr></table></td></tr>',
      '<tr><td>A</td><td><ruby>基<rt>注</rt></ruby></td></tr>',
      '<tr><td>A</td><td><p>Block</p></td></tr>',
      '<tr><td>A</td><td style="float:right">Body</td></tr>',
      '<tr><td>Long${'x' * 50}</td><td>Body</td></tr>',
      '<tr><td style="border-left:1px solid red">A</td><td>Body</td></tr>',
    ]) {
      final html = '<tr><td>OK</td><td>Readable</td></tr>$row';
      final parsed = paragraphs(tableHtml(html));
      expect(parsed.every((b) => b.tableRow == null), isTrue, reason: row);
      expect(
        parsed.map((b) => b.text),
        paragraphs('<table>$html</table>').map((b) => b.text),
      );
    }
  });
  test(
    'row validation rejects invalid ranges and geometry; geometry is nonsemantic',
    () {
      final b = paragraphs(
        tableHtml('<tr><td>A😀</td><td>正文</td></tr>'),
      ).single;
      final changed = b.toJson();
      final meta = Map<String, Object?>.from(changed['tableRow'] as Map);
      changed['tableRow'] = {...meta, 'leftWidthEm': 3.0};
      final other = ContentBlock.fromJson(changed);
      expect(other.blockKey, b.blockKey);
      expect(other, isNot(b));
      for (final patch in [
        {'rightStart': 999},
        {'leftEnd': 0},
        {'leftWidthEm': double.nan},
        {'gapAfterEm': 99},
        {'dividerWidth': -1},
        {'group': -1},
      ]) {
        expect(
          () => ContentBlock.fromJson({
            ...b.toJson(),
            'tableRow': {...meta, ...patch},
          }),
          throwsArgumentError,
        );
      }
    },
  );
}
