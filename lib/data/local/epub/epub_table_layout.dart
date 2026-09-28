import 'package:html/dom.dart' as dom;
import '../../../domain/models/models.dart';
import 'epub_rich_styles.dart';

class EpubTableRow {
  EpubTableRow(this.left, this.right, this.layout);
  final dom.Element left, right;
  final TableRowLayout layout;
}

/// Validate an entire bounded table before opting any of its rows into native
/// geometry. Unsupported tables keep the existing text walker, unchanged.
Map<dom.Element, EpubTableRow> epubTableRows(
  dom.Document doc,
  Map<dom.Element, Map<String, String>> styles,
  Map<dom.Element, EpubRichStyle> richStyles,
) {
  final result = <dom.Element, EpubTableRow>{};
  String? own(dom.Element e, String key) => styles[e]?[key];
  String? inherited(dom.Element? e, String key) {
    if (e == null) return null;
    final value = styles[e]?[key];
    return value == null || value == 'inherit' || value == 'unset'
        ? inherited(e.parent, key)
        : value == 'initial'
        ? null
        : value;
  }

  bool hidden(dom.Element e) {
    for (dom.Element? n = e; n != null; n = n.parent) {
      if (n.attributes.containsKey('hidden') || own(n, 'display') == 'none') {
        return true;
      }
    }
    return {'hidden', 'collapse'}.contains(inherited(e, 'visibility'));
  }

  double? em(String? s, {double? fallback}) {
    if (s == null) return fallback;
    if (s == '0') return 0;
    if (!s.endsWith('em')) return null;
    final n = double.tryParse(s.substring(0, s.length - 2));
    return n != null && n.isFinite && n >= 0 ? n : null;
  }

  bool simple(dom.Element e) {
    for (dom.Element? n = e; n != null; n = n.parent) {
      if (!{null, 'none', 'initial'}.contains(own(n, 'float')) ||
          !{null, 'static', 'initial'}.contains(own(n, 'position')) ||
          !{null, 'ltr', 'initial'}.contains(own(n, 'direction')) ||
          !{null, 'normal', 'initial'}.contains(own(n, 'unicode-bidi')) ||
          !{
            null,
            'horizontal-tb',
            'initial',
          }.contains(own(n, 'writing-mode')) ||
          !{null, 'ltr'}.contains(n.attributes['dir']) ||
          {
            'flex',
            'grid',
            'inline-flex',
            'inline-grid',
          }.contains(own(n, 'display'))) {
        return false;
      }
    }
    return true;
  }

  bool nested(dom.Element e) {
    for (var n = e.parent; n != null; n = n.parent) {
      if (n.localName == 'table') return true;
    }
    return false;
  }

  var group = 0;
  for (final table in doc.querySelectorAll('table')) {
    if (hidden(table) ||
        own(table, 'width') != null ||
        !simple(table) ||
        nested(table) ||
        inherited(table, 'border-collapse') != 'collapse' ||
        table.querySelector(
              'table, th, caption, col, colgroup, tfoot, thead',
            ) !=
            null) {
      continue;
    }
    final rows = <dom.Element>[];
    var valid = true;
    for (final child in table.children) {
      if (child.localName == 'tr') {
        rows.add(child);
      } else if (child.localName == 'tbody' &&
          child.children.every((e) => e.localName == 'tr')) {
        rows.addAll(child.children);
      } else {
        valid = false;
      }
    }
    if (!valid || rows.isEmpty || rows.length > 2048) continue;
    final candidate = <dom.Element, EpubTableRow>{};
    List<Object?>? geometry;
    for (final row in rows) {
      if (hidden(row)) continue;
      final cells = row.children;
      if (!simple(row) ||
          cells.length != 2 ||
          cells.any(
            (e) =>
                e.localName != 'td' ||
                hidden(e) ||
                !simple(e) ||
                e.attributes.containsKey('rowspan') ||
                e.attributes.containsKey('colspan') ||
                e
                    .querySelectorAll('*')
                    .any(
                      (n) =>
                          !{
                            'span',
                            'b',
                            'i',
                            'em',
                            'strong',
                            'a',
                            'br',
                          }.contains(n.localName) ||
                          !simple(n),
                    ),
          )) {
        valid = false;
        break;
      }
      if (cells.every((e) => e.text.trim().isEmpty)) {
        final gapValue = em(own(row, 'height'));
        final gap = gapValue == null
            ? null
            : gapValue * (richStyles[row]?.scale ?? 1);
        if (row.querySelector('br') != null ||
            gap == null ||
            gap <= 0 ||
            gap > 4 ||
            candidate.isEmpty) {
          valid = false;
          break;
        }
        final last = candidate.keys.last;
        final before = candidate[last]!;
        if (before.layout.gapAfterEm + gap > 4) {
          valid = false;
          break;
        }
        candidate[last] = EpubTableRow(
          before.left,
          before.right,
          before.layout.withGap(before.layout.gapAfterEm + gap),
        );
        continue;
      }
      final left = cells[0], right = cells[1];
      // A short label is structural, not a time/date heuristic.
      if (own(row, 'height') != null ||
          cells.any(
            (e) =>
                !{null, 'left', 'start'}.contains(inherited(e, 'text-align')),
          ) ||
          left.text.trim().isEmpty ||
          left.text.runes.length > 48 ||
          right.text.trim().isEmpty ||
          left.querySelector('br') != null ||
          inherited(left, 'white-space') != 'nowrap' ||
          !{null, 'normal'}.contains(inherited(right, 'white-space')) ||
          own(left, 'vertical-align') != 'top' ||
          !{null, 'top'}.contains(own(right, 'vertical-align'))) {
        valid = false;
        break;
      }
      final leftScale = richStyles[left]?.scale ?? 1;
      final rightScale = richStyles[right]?.scale ?? 1;
      double? scaled(double? value, double scale) =>
          value == null ? null : value * scale;
      final width = scaled(em(own(left, 'width')), leftScale);
      final lp = scaled(em(own(left, 'padding-right'), fallback: 0), leftScale);
      final rp = scaled(
        em(own(right, 'padding-left'), fallback: 0),
        rightScale,
      );
      final border = own(left, 'border-right-width');
      final bw = border == '0'
          ? 0.0
          : border?.endsWith('px') == true
          ? double.tryParse(border!.substring(0, border.length - 2))
          : null;
      final color = epubColor(own(left, 'border-right-color'));
      if (width == null ||
          width < .25 ||
          width > 12 ||
          lp == null ||
          lp > 4 ||
          rp == null ||
          rp > 4 ||
          bw == null ||
          !bw.isFinite ||
          bw <= 0 ||
          bw > 4 ||
          color == null ||
          own(left, 'border-right-style') != 'solid' ||
          [table, row, ...cells].any(
            (e) =>
                own(e, 'border') != null ||
                [
                  'border-width',
                  'border-style',
                  'border-color',
                  'border-left-width',
                  'border-left-style',
                  'border-left-color',
                  'border-top-width',
                  'border-top-style',
                  'border-top-color',
                  'border-bottom-width',
                  'border-bottom-style',
                  'border-bottom-color',
                  'border-left',
                  'border-top',
                  'border-bottom',
                ].any((p) => own(e, p) != null),
          ) ||
          own(right, 'border-right') != null ||
          own(right, 'border-right-width') != null ||
          own(right, 'width') != null ||
          em(own(left, 'padding-left'), fallback: 0) != 0 ||
          em(own(right, 'padding-right'), fallback: 0) != 0 ||
          cells.any(
            (e) =>
                em(own(e, 'padding-top'), fallback: 0) != 0 ||
                em(own(e, 'padding-bottom'), fallback: 0) != 0,
          )) {
        valid = false;
        break;
      }
      final g = [width, lp, rp, bw, color];
      if (geometry != null && g.indexed.any((v) => v.$2 != geometry![v.$1])) {
        valid = false;
        break;
      }
      geometry = g;
      candidate[row] = EpubTableRow(
        left,
        right,
        TableRowLayout(
          group: group,
          leftEnd: 1,
          rightStart: 1,
          leftWidthEm: width,
          leftPaddingEm: lp,
          rightPaddingEm: rp,
          dividerWidth: bw,
          dividerColor: color,
        ),
      );
    }
    if (valid && candidate.isNotEmpty) {
      result.addAll(candidate);
      group++;
    }
  }
  return result;
}
