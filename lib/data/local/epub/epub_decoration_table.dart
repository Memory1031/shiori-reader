import 'package:html/dom.dart' as dom;
import '../../../domain/models/models.dart';
import 'epub_rich_styles.dart';

class EpubDecorationTable {
  EpubDecorationTable(this.content, this.css, this.columns);
  final dom.Element content;
  final Map<String, String> css;
  final DecorationColumns columns;
}

/// One row with two empty, equally bordered side cells and one simple text block.
/// All other tables keep their existing text / two-column paths.
Map<dom.Element, EpubDecorationTable> epubDecorationTables(
  dom.Document doc,
  Map<dom.Element, Map<String, String>> styles,
  Map<dom.Element, EpubRichStyle> rich,
) {
  final result = <dom.Element, EpubDecorationTable>{};
  Map<String, String> css(dom.Element e) => styles[e] ?? const {};
  bool emptyText(String text) =>
      text.replaceAll(RegExp(r'[ \t\r\n\f]'), '').isEmpty;
  bool zero(String? value) =>
      value == null || epubLayoutLength(value)?.value == 0;
  bool hidden(dom.Element e) {
    for (dom.Element? n = e; n != null; n = n.parent) {
      if (n.attributes.containsKey('hidden') || css(n)['display'] == 'none') {
        return true;
      }
    }
    for (dom.Element? n = e; n != null; n = n.parent) {
      final value = css(n)['visibility'];
      if (value == 'visible' || value == 'initial') return false;
      if (value == 'hidden' || value == 'collapse') return true;
    }
    return false;
  }

  bool simple(dom.Element e) {
    for (dom.Element? n = e; n != null; n = n.parent) {
      final s = css(n);
      if (!{null, 'none', 'initial'}.contains(s['float']) ||
          !{null, 'static', 'initial'}.contains(s['position']) ||
          !{null, 'none', 'initial'}.contains(s['transform']) ||
          !{null, 'ltr', 'initial'}.contains(s['direction']) ||
          !{null, 'ltr'}.contains(n.attributes['dir']) ||
          !{null, 'normal', 'initial'}.contains(s['unicode-bidi']) ||
          !{null, 'horizontal-tb', 'initial'}.contains(s['writing-mode']) ||
          {
            'flex',
            'grid',
            'inline-flex',
            'inline-grid',
          }.contains(s['display'])) {
        return false;
      }
    }
    return true;
  }

  bool plainCell(dom.Element cell) {
    final s = css(cell);
    return !cell.attributes.containsKey('colspan') &&
        !cell.attributes.containsKey('rowspan') &&
        !hidden(cell) &&
        simple(cell) &&
        {null, 'table-cell'}.contains(s['display']) &&
        {'left', 'right'}.every((side) => zero(s['padding-$side'])) &&
        {
          'top',
          'right',
          'bottom',
          'left',
        }.every((side) => zero(s['margin-$side'])) &&
        s['height'] == null &&
        s['min-height'] == null &&
        s['max-height'] == null &&
        s['border-radius'] == null &&
        s['background-color'] == null &&
        {null, 'none'}.contains(s['background-image']);
  }

  BoxBorderSide? bottomBorder(dom.Element e) => epubBlockBox(
    css(e),
    0,
    rich[e] ?? const EpubRichStyle(),
  )?.borders?.bottom;
  bool nested(dom.Element e) {
    for (var n = e.parent; n != null; n = n.parent) {
      if (n.localName == 'table') return true;
    }
    return false;
  }

  bool noBorder(dom.Element e, String side) =>
      {null, 'none', 'hidden'}.contains(css(e)['border-$side-style']);
  double? fraction(dom.Element e) {
    final width = epubLayoutLength(css(e)['width']);
    return width?.unit == LayoutUnit.fraction &&
            width!.value > 0 &&
            width.value < 1
        ? width.value
        : null;
  }

  for (final table in doc.querySelectorAll('table')) {
    final s = css(table);
    if (hidden(table) ||
        !simple(table) ||
        nested(table) ||
        s['border-collapse'] != 'collapse' ||
        !{null, 'table'}.contains(s['display']) ||
        !{null, '100%'}.contains(s['width']) ||
        s['max-width'] != null ||
        s['height'] != null ||
        s['border-radius'] != null ||
        !noBorder(table, 'top') ||
        !noBorder(table, 'bottom') ||
        !{
          'top',
          'right',
          'bottom',
          'left',
        }.every((side) => zero(s['padding-$side']))) {
      continue;
    }
    final rows =
        table.children.length == 1 && table.children.single.localName == 'tbody'
        ? table.children.single.children
        : table.children;
    if (rows.length != 1 || rows.single.localName != 'tr') continue;
    final row = rows.single, cells = rows.single.children;
    if (!simple(row) ||
        !{null, 'table-row'}.contains(css(row)['display']) ||
        hidden(row) ||
        cells.length != 3 ||
        cells.any((c) => c.localName != 'td' || !plainCell(c)) ||
        css(row).keys.any(
          (k) =>
              k.startsWith('border-') ||
              k.startsWith('padding-') ||
              k.startsWith('margin-') ||
              k == 'height' ||
              k == 'background-color',
        )) {
      continue;
    }
    final left = cells[0], center = cells[1], right = cells[2];
    final verticalPadding = <String, String>{};
    var matchingPadding = true;
    for (final side in ['top', 'bottom']) {
      final lengths = cells
          .map(
            (c) => css(c)['padding-$side'] == null
                ? LayoutLength(0)
                : epubLayoutLength(css(c)['padding-$side'], percentage: false),
          )
          .toList();
      final length = lengths.first;
      if (length == null ||
          length.unit == LayoutUnit.em &&
              length.value > 0 &&
              cells.any(
                (c) => (rich[c]?.scale ?? 1) != (rich[table]?.scale ?? 1),
              ) ||
          lengths.any((l) => l != length) ||
          length.value > (length.unit == LayoutUnit.em ? 4 : 64)) {
        matchingPadding = false;
        break;
      }
      verticalPadding['padding-$side'] = css(center)['padding-$side'] ?? '0';
    }
    if (!matchingPadding) continue;

    if (left.children.isNotEmpty ||
        right.children.isNotEmpty ||
        !emptyText(left.text) ||
        !emptyText(right.text) ||
        center.children.length != 1 ||
        !emptyText(
          center.nodes.whereType<dom.Text>().map((t) => t.text).join(),
        ) ||
        [left, right].any(
          (c) => ['top', 'left', 'right'].any((side) => !noBorder(c, side)),
        ) ||
        [
          'top',
          'left',
          'right',
          'bottom',
        ].any((side) => !noBorder(center, side))) {
      continue;
    }
    final content = center.children.single;
    if (!{
          'p',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
        }.contains(content.localName) ||
        hidden(content) ||
        !simple(content) ||
        !{null, 'block'}.contains(css(content)['display']) ||
        content.text.trim().isEmpty ||
        content.text.runes.length > 256 ||
        !zero(css(content)['margin-left']) ||
        !zero(css(content)['margin-right']) ||
        css(content)['width'] != null ||
        css(content)['max-width'] != null ||
        css(content)['border-radius'] != null ||
        epubColor(css(content)['background-color']) != null ||
        epubLinkDecoration(content, styles, rich)?.onBlock == true ||
        [
          'top',
          'left',
          'right',
          'bottom',
        ].any((side) => !noBorder(content, side)) ||
        content
            .querySelectorAll('*')
            .any(
              (e) =>
                  !{
                    'span',
                    'b',
                    'i',
                    'em',
                    'strong',
                    'a',
                    'br',
                    'u',
                    's',
                    'sup',
                    'sub',
                  }.contains(e.localName) ||
                  !simple(e) ||
                  !{null, 'inline'}.contains(css(e)['display']),
            )) {
      continue;
    }
    final leading = fraction(left),
        trailing = fraction(right),
        bottom = bottomBorder(left);
    if (leading == null ||
        trailing == null ||
        leading + trailing >= 1 ||
        bottom == null ||
        bottom.color == null ||
        bottom.style != BoxBorderStyle.solid ||
        bottom.width.unit != LayoutUnit.px ||
        bottom.width.value <= 0 ||
        bottom.width.value > 8 ||
        bottom != bottomBorder(right)) {
      continue;
    }
    final centerWidth = css(center)['width'];
    if (centerWidth != null &&
        centerWidth != 'auto' &&
        (fraction(center) == null ||
            (fraction(center)! - (1 - leading - trailing)).abs() > .000001)) {
      continue;
    }
    result[table] = EpubDecorationTable(
      content,
      {
        ...s,
        ...verticalPadding,
        for (final name in ['style', 'width'])
          if (css(left)['border-bottom-$name'] != null)
            'border-bottom-$name': css(left)['border-bottom-$name']!,
        'border-bottom-color':
            '#${(bottom.color! & 0xffffff).toRadixString(16).padLeft(6, '0')}',
      },
      DecorationColumns(leadingFraction: leading, trailingFraction: trailing),
    );
  }
  return result;
}
