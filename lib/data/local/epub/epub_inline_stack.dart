import 'package:html/dom.dart' as dom;
import 'epub_rich_styles.dart';
import 'epub_paragraph_layout.dart';

/// Structural admission only; the existing prose walker owns normalized text.
/// No class names or text/language heuristics participate in recognition.
({
  double? upper,
  double? lower,
  double upperBasis,
  double lowerBasis,
  bool upperFromReader,
  bool lowerFromReader,
})?
epubInlineStack(
  dom.Element owner,
  Map<dom.Element, Map<String, String>> styles,
  Map<dom.Element, EpubRichStyle> rich,
  bool inheritedVisible,
) {
  String? local(dom.Element e, String key) {
    final v = styles[e]?[key];
    return v == 'inherit'
        ? (e.parent == null ? null : local(e.parent!, key))
        : v;
  }

  if (local(owner, 'display') != 'inline-block' ||
      epubInheritedProperty(owner, styles, 'text-align') != 'center' ||
      !{
        null,
        '0',
        '0em',
        '0px',
        'initial',
      }.contains(epubInheritedProperty(owner, styles, 'text-indent'))) {
    return null;
  }
  for (var e = owner.parent; e != null; e = e.parent) {
    if (e.localName == 'a' ||
        local(e, 'display') == 'inline-block' ||
        !{
          null,
          'horizontal-tb',
          'initial',
          'inherit',
          'unset',
        }.contains(styles[e]?['writing-mode']) ||
        !{null, 'none', 'initial'}.contains(styles[e]?['float']) ||
        !{null, 'static', 'initial'}.contains(styles[e]?['position'])) {
      return null;
    }
  }
  bool simple(dom.Element e, bool root) {
    final css = styles[e] ?? const {};
    if (e.attributes['dir'] != null && e.attributes['dir'] != 'ltr') {
      return false;
    }
    if (!{
          null,
          'ltr',
          'initial',
          'inherit',
          'unset',
        }.contains(css['direction']) ||
        !{
          null,
          'normal',
          'initial',
          'inherit',
          'unset',
        }.contains(css['unicode-bidi']) ||
        !{
          null,
          'horizontal-tb',
          'initial',
          'inherit',
          'unset',
        }.contains(css['writing-mode']) ||
        !{null, 'static', 'initial'}.contains(css['position']) ||
        !{null, 'none', 'initial'}.contains(css['float']) ||
        !{null, 'none', 'initial'}.contains(css['transform']) ||
        !{null, 'baseline', 'initial'}.contains(css['vertical-align']) ||
        !{
          null,
          'normal',
          'initial',
          'inherit',
          'unset',
        }.contains(css['white-space'])) {
      return false;
    }
    if (!root && !{null, 'inline', 'initial'}.contains(local(e, 'display'))) {
      return false;
    }
    for (final entry in css.entries) {
      final k = entry.key, v = entry.value;
      if ({
            'width',
            'height',
            'min-width',
            'max-width',
            'min-height',
            'max-height',
          }.contains(k) &&
          !{'auto', 'none', 'initial'}.contains(v)) {
        return false;
      }
      if (k.startsWith('overflow') && !{'visible', 'initial'}.contains(v)) {
        return false;
      }
      if (k.startsWith('padding') ||
          k.startsWith('margin') ||
          k.startsWith('border') ||
          k == 'background-color' ||
          k == 'box-shadow') {
        if (!RegExp(
          r'^(?:0(?:px|em)?|none|transparent|initial)(?:\s+0(?:px|em)?)*$',
        ).hasMatch(v)) {
          return false;
        }
      }
    }
    return true;
  }

  // CSS unitless values inherit as multipliers; lengths inherit their computed
  // absolute value. Wrapper 1em therefore stays 1em for a .68em child.
  (double, double, bool)? lineHeight(dom.Element node) {
    for (
      var e = node as dom.Element?;
      e != null;
      e = e == owner ? null : e.parent
    ) {
      final v = styles[e]?['line-height'];
      if (v == null || v == 'inherit' || v == 'unset') continue;
      if (v == 'normal' || v == 'initial') return null;
      final m = RegExp(r'^(\d*\.?\d+)(em|px|%)?$').firstMatch(v);
      if (m == null) return (double.nan, 1, true);
      final n = double.parse(m[1]!);
      final scale = rich[e]?.scale ?? 1;
      final value = switch (m[2]) {
        null => n * (rich[node]?.scale ?? 1),
        'em' => n * scale,
        '%' => n / 100 * scale,
        _ => n / 16,
      };
      final basis = switch (m[2]) {
        null => rich[node]?.scale ?? 1.0,
        'em' || '%' => scale,
        _ => 1.0,
      };
      final font = rich[m[2] == null ? node : e];
      final fromReader =
          m[2] == 'px' ||
          font?.defaultHeading != true ||
          font?.fontSizeFromReader == true;
      return (value > 0 && value <= 8 ? value : double.nan, basis, fromReader);
    }
    return null;
  }

  var breaks = 0, count = 0, valid = true;
  final heights = <List<(double, double, bool)>>[[], []];
  void visit(dom.Node node, bool visible) {
    if (!valid || ++count > 128) {
      valid = false;
      return;
    }
    if (node is dom.Text) {
      if (visible && node.text.trim().isNotEmpty) {
        final h = lineHeight(node.parent!);
        if (h != null) {
          final row = heights[breaks.clamp(0, 1)];
          // A row with competing font bases needs richer line-box metadata.
          // Keep this bounded subset source-readable instead of approximating it.
          if (!h.$1.isFinite ||
              row.any((other) => other.$2 != h.$2 || other.$3 != h.$3)) {
            valid = false;
          } else {
            row.add(h);
          }
        }
      }
      return;
    }
    if (node is! dom.Element) return;
    final css = styles[node] ?? const {};
    if (node.attributes.containsKey('hidden') ||
        local(node, 'display') == 'none') {
      return;
    }
    visible = switch (css['visibility']) {
      'visible' || 'initial' => true,
      'hidden' || 'collapse' => false,
      _ => visible,
    };
    if (!{
          'span',
          'b',
          'i',
          'em',
          'strong',
          'small',
          'br',
        }.contains(node.localName) ||
        !simple(node, node == owner)) {
      valid = false;
      return;
    }
    if (node.localName == 'br') {
      if (visible && ++breaks > 1) valid = false;
      return;
    }
    for (final c in node.nodes) {
      visit(c, visible);
    }
  }

  visit(owner, inheritedVisible);
  if (!valid || breaks != 1) return null;
  return (
    upper: heights[0].isEmpty
        ? null
        : heights[0].reduce((a, b) => a.$1 > b.$1 ? a : b).$1,
    lower: heights[1].isEmpty
        ? null
        : heights[1].reduce((a, b) => a.$1 > b.$1 ? a : b).$1,
    upperBasis: heights[0].isEmpty ? 1 : heights[0].first.$2,
    lowerBasis: heights[1].isEmpty ? 1 : heights[1].first.$2,
    upperFromReader: heights[0].isEmpty ? true : heights[0].first.$3,
    lowerFromReader: heights[1].isEmpty ? true : heights[1].first.$3,
  );
}
