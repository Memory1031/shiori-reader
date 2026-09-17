import 'package:html/dom.dart' as dom;
import '../../../domain/models/models.dart';

int? epubColor(String? value) {
  if (value == null) return null;
  var v = value.trim().toLowerCase();
  const named = {
    'black': '#000000',
    'white': '#ffffff',
    'red': '#ff0000',
    'green': '#008000',
    'blue': '#0000ff',
    'yellow': '#ffff00',
    'purple': '#800080',
    'gray': '#808080',
    'grey': '#808080',
    'orange': '#ffa500',
    'pink': '#ffc0cb',
  };
  v = named[v] ?? v;
  if (RegExp(r'^#[0-9a-f]{3}$').hasMatch(v)) {
    v = '#${v[1]}${v[1]}${v[2]}${v[2]}${v[3]}${v[3]}';
  }
  if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(v)) {
    return 0xff000000 | int.parse(v.substring(1), radix: 16);
  }
  final rgb = RegExp(
    r'^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$',
  ).firstMatch(v);
  if (rgb != null) {
    final c = [for (var i = 1; i <= 3; i++) int.parse(rgb[i]!)];
    if (c.every((v) => v <= 255)) {
      return 0xff000000 | c[0] << 16 | c[1] << 8 | c[2];
    }
  }
  return null;
}

double? _length(String? value, double em) {
  final match = RegExp(r'^(\d*\.?\d+)(px|em|%)?$').firstMatch(value ?? '');
  if (match == null) return null;
  final n = double.tryParse(match[1]!);
  if (n == null || !n.isFinite) return null;
  return switch (match[2]) {
    'em' => n * em,
    '%' => n / 100 * em,
    _ => n,
  };
}

class EpubRichStyle {
  const EpubRichStyle({
    this.color,
    this.scale = 1,
    this.bold = false,
    this.italic = false,
  });
  final int? color;
  final double scale;
  final bool bold, italic;
  bool get isDefault => color == null && scale == 1 && !bold && !italic;
  InlineTextStyle range(
    int start,
    int length, {
    bool preserveNeutral = false,
  }) => InlineTextStyle(
    start: start,
    length: length,
    color: !preserveNeutral && (color == 0xff000000 || color == 0xffffffff)
        ? null
        : color,
    fontScale: scale,
    bold: bold,
    italic: italic,
  );
}

/// Computed inherited typography for the bounded native subset. Root sizing
/// and publisher rhythm never replace the reader's base font/line/paragraph settings.
Map<dom.Element, EpubRichStyle> epubRichStyles(
  dom.Document doc,
  Map<dom.Element, Map<String, String>> styles,
) {
  final result = <dom.Element, EpubRichStyle>{};
  for (final e in doc.querySelectorAll('*')) {
    final parent = result[e.parent] ?? const EpubRichStyle();
    final css = styles[e] ?? const {};
    final root = e.localName == 'body' || e.localName == 'html';
    final size = root ? null : _length(css['font-size'], parent.scale * 16);
    final weight = css['font-weight'];
    final fontStyle = css['font-style'];
    result[e] = EpubRichStyle(
      color: css['color'] == 'initial'
          ? null
          : epubColor(css['color']) ?? parent.color,
      scale: size == null ? parent.scale : (size / 16).clamp(.25, 4),
      bold: weight == 'normal' || weight == '400'
          ? false
          : weight == 'bold' ||
                weight == 'bolder' ||
                (int.tryParse(weight ?? '') ?? 0) >= 600
          ? true
          : {'b', 'strong'}.contains(e.localName) || parent.bold,
      italic: fontStyle == 'normal'
          ? false
          : {'italic', 'oblique'}.contains(fontStyle) ||
                {'i', 'em'}.contains(e.localName) ||
                parent.italic,
    );
  }
  return result;
}

BlockBox? epubBlockBox(
  Map<String, String> css,
  int group,
  EpubRichStyle style,
) {
  // Only simple decorated containers, never generic body width/margins.
  final background = epubColor(css['background-color']);
  final border = css['border'] ?? '';
  if (background == null &&
      border.isEmpty &&
      css['border-width'] == null &&
      css['width'] == null &&
      css['max-width'] == null) {
    return null;
  }
  if ({'absolute', 'fixed'}.contains(css['position']) ||
      {'flex', 'grid'}.contains(css['display']) ||
      css['float'] != null && css['float'] != 'none') {
    return null;
  }
  final tokens = border.split(RegExp(r'\s+'));
  final borderWidth =
      _length(
        css['border-width'] ??
            tokens.where((t) => RegExp(r'^\d').hasMatch(t)).firstOrNull,
        style.scale * 16,
      ) ??
      0;
  final borderColor =
      epubColor(css['border-color']) ??
      tokens.map(epubColor).whereType<int>().firstOrNull ??
      style.color;
  double? size(String key) {
    if (css[key]?.endsWith('%') == true) return null;
    final v = _length(css[key], style.scale * 16);
    return v != null && v > 0 && v <= 4096 ? v : null;
  }

  double? fraction(String key) {
    final value = css[key];
    if (value == null || !value.endsWith('%')) return null;
    final n = double.tryParse(value.substring(0, value.length - 1));
    return n != null && n.isFinite && n > 0 ? (n / 100).clamp(.01, 1) : null;
  }

  // v1 accepts uniform padding; unsupported shorthand does not invent geometry.
  final padding = _length(css['padding'], style.scale * 16) ?? 0;
  return BlockBox(
    group: group,
    width: size('width'),
    maxWidth: size('max-width'),
    widthFraction: fraction('width'),
    maxWidthFraction: fraction('max-width'),
    padding: padding.clamp(0, 64),
    borderWidth: borderWidth.clamp(0, 8),
    borderColor: borderColor,
    backgroundColor: background,
    dashed: (css['border-style'] ?? border).contains('dashed'),
  );
}
