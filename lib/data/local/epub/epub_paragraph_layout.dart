import 'package:characters/characters.dart';
import 'package:html/dom.dart' as dom;
import 'epub_rich_styles.dart';

/// Resolve inherited properties only. Margins/float/clear remain local.
String? epubInheritedProperty(
  dom.Element? node,
  Map<dom.Element, Map<String, String>> styles,
  String name,
) {
  for (var e = node; e != null; e = e.parent) {
    final value = styles[e]?[name];
    if (value == null || value == 'inherit' || value == 'unset') continue;
    return value == 'initial' ? null : value;
  }
  return null;
}

double? _em(String? value) {
  if (!RegExp(r'^[+-]?(?:\d*\.)?\d+em$').hasMatch(value ?? '')) return null;
  final n = double.tryParse(value!.substring(0, value.length - 2));
  return n != null && n.isFinite ? n : null;
}

/// Deliberately excludes directional overrides and non-flow containers, rather
/// than interpreting physical left/right as logical start/end.
bool _flow(dom.Element owner, Map<dom.Element, Map<String, String>> styles) {
  for (var e = owner as dom.Element?; e != null; e = e.parent) {
    final css = styles[e] ?? const {};
    if (e.attributes['dir'] != null && e.attributes['dir'] != 'ltr' ||
        !{
          null,
          'ltr',
          'initial',
          'inherit',
          'unset',
        }.contains(css['direction']) ||
        !{null, 'normal', 'initial', 'unset'}.contains(css['unicode-bidi']) ||
        !{
          null,
          'horizontal-tb',
          'initial',
          'inherit',
          'unset',
        }.contains(css['writing-mode']) ||
        !{null, 'static', 'relative', 'initial'}.contains(css['position']) ||
        !{null, 'block', 'inline', 'initial'}.contains(css['display']) ||
        !{null, 'none', 'initial'}.contains(css['float'])) {
      return false;
    }
  }
  return true;
}

({double? hanging, dom.Element? label}) epubParagraphLayout(
  dom.Element? owner,
  Map<dom.Element, Map<String, String>> styles,
  Iterable<dom.Element> visibleFloats,
  Map<dom.Element, EpubRichStyle> richStyles,
) {
  if (owner != null &&
      styles[owner]?['margin-left'] == null &&
      visibleFloats.isEmpty) {
    return (hanging: null, label: null);
  }
  if (owner == null ||
      !_flow(owner, styles) ||
      !{
        null,
        'left',
        'start',
      }.contains(epubInheritedProperty(owner, styles, 'text-align'))) {
    return (hanging: null, label: null);
  }
  // Nested direction/position changes have readable text fallback.
  if (owner
          .querySelectorAll('[dir]')
          .any((e) => e.attributes['dir'] != 'ltr') ||
      owner.querySelectorAll('*').any((e) {
        final css = styles[e] ?? const {};
        return !{
              null,
              'ltr',
              'inherit',
              'initial',
              'unset',
            }.contains(css['direction']) ||
            !{
              null,
              'normal',
              'initial',
              'unset',
            }.contains(css['unicode-bidi']) ||
            !{
              null,
              'horizontal-tb',
              'initial',
              'inherit',
              'unset',
            }.contains(css['writing-mode']);
      })) {
    return (hanging: null, label: null);
  }
  final localMargin = _em(styles[owner]?['margin-left']);
  final margin = localMargin == null
      ? null
      : localMargin * (richStyles[owner]?.scale ?? 1);
  double? indent;
  // Inherited em lengths are computed using the declaring element's font,
  // not recalculated against a descendant's potentially different size.
  for (var e = owner as dom.Element?; e != null; e = e.parent) {
    final value = styles[e]?['text-indent'];
    if (value == null || value == 'inherit' || value == 'unset') continue;
    final em = _em(value);
    indent = em == null ? null : em * (richStyles[e]?.scale ?? 1);
    break;
  }
  final hanging =
      margin != null &&
          margin > 0 &&
          margin <= 32 &&
          indent != null &&
          (margin + indent).abs() < .000001
      ? margin
      : null;
  final floats = visibleFloats.toList();
  dom.Element? label;
  if (floats.length == 1 &&
      {'both', 'right'}.contains(styles[owner]?['clear'])) {
    final node = floats.single;
    final css = styles[node] ?? const {};
    if (node.parent == owner &&
        node.localName == 'span' &&
        node.children.isEmpty &&
        css['float'] == 'right' &&
        {
          '0',
          '0em',
          '0px',
        }.contains(epubInheritedProperty(node, styles, 'text-indent') ?? '0') &&
        !node.attributes.containsKey('dir') &&
        !{'absolute', 'fixed'}.contains(css['position']) &&
        !{'block', 'flex', 'grid', 'table'}.contains(css['display']) &&
        css['width'] == null &&
        css['height'] == null) {
      label = node;
    }
  }
  return (hanging: hanging, label: label);
}

/// Coordinates have already passed through the shared whitespace writer.
int? epubTrailingLabelStart(String text, int start, int end) {
  if (start <= 0 || end != text.length || start >= end) return null;
  final suffix = text.substring(start);
  if (suffix.runes.length > 64 ||
      suffix.trim().isEmpty ||
      suffix.contains('\n') ||
      suffix.contains('\uFFFC')) {
    return null;
  }
  var boundary = 0;
  for (final cluster in text.characters) {
    if (boundary == start) return text.substring(0, start).runes.length;
    boundary += cluster.length;
  }
  return null;
}
