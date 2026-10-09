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
    this.bold,
    this.italic,
    this.hasFontSize = false,
    this.fontSizeFromReader = false,
    this.defaultHeading = false,
  });
  final int? color;
  final double scale;
  final bool? bold, italic;
  final bool hasFontSize, fontSizeFromReader, defaultHeading;
  bool get isDefault =>
      color == null &&
      scale == 1 &&
      !fontSizeFromReader &&
      bold == null &&
      italic == null;
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
    fontSizeFromReader: fontSizeFromReader,
    bold: bold,
    italic: italic,
  );
}

/// Absolute keywords resolve against the reader's medium. Only em and %
/// multiply the computed parent. Publisher root sizes are deliberately ignored.
double? epubFontScale(String? value, double parent) {
  const keywords = {
    'xx-small': 3 / 5,
    'x-small': 3 / 4,
    'small': 8 / 9,
    'medium': 1.0,
    'large': 6 / 5,
    'x-large': 3 / 2,
    'xx-large': 2.0,
    'xxx-large': 3.0,
  };
  return keywords[value] ??
      (_length(value, parent * 16) == null
          ? null
          : (_length(value, parent * 16)! / 16).clamp(.25, 4));
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
    final size = root ? null : epubFontScale(css['font-size'], parent.scale);
    final heading = RegExp(r'^h[1-6]$').hasMatch(e.localName ?? '');
    final relative =
        css['font-size']?.endsWith('em') == true ||
        css['font-size']?.endsWith('%') == true;
    final weight = css['font-weight'];
    final fontStyle = css['font-style'];
    result[e] = EpubRichStyle(
      color: css['color'] == 'initial'
          ? null
          : epubColor(css['color']) ?? parent.color,
      scale: size ?? parent.scale,
      hasFontSize: size != null || parent.hasFontSize,
      fontSizeFromReader: size == null
          ? parent.fontSizeFromReader
          : !relative ||
                heading ||
                !parent.defaultHeading ||
                parent.fontSizeFromReader,
      defaultHeading: heading
          ? size == null && !parent.hasFontSize
          : parent.defaultHeading,
      bold: weight == 'normal' || weight == '400'
          ? false
          : weight == 'bold' ||
                weight == 'bolder' ||
                (int.tryParse(weight ?? '') ?? 0) >= 600
          ? true
          : {'b', 'strong'}.contains(e.localName)
          ? true
          : parent.bold,
      italic: fontStyle == 'normal'
          ? false
          : {'italic', 'oblique'}.contains(fontStyle) ||
                {'i', 'em'}.contains(e.localName)
          ? true
          : parent.italic,
    );
  }
  return result;
}

LayoutLength? epubLayoutLength(String? value, {bool percentage = true}) {
  final match = RegExp(r'^(\d*\.?\d+)(px|em|%)?$').firstMatch(value ?? '');
  if (match == null) return null;
  final n = double.tryParse(match[1]!);
  if (n == null || !n.isFinite || n < 0) return null;
  final unit = switch (match[2]) {
    'em' => LayoutUnit.em,
    '%' => LayoutUnit.fraction,
    _ => LayoutUnit.px,
  };
  if (unit == LayoutUnit.fraction && !percentage) return null;
  final v = unit == LayoutUnit.fraction ? n / 100 : n;
  return v <= 4096 ? LayoutLength(v, unit) : null;
}

LinkDecoration? epubLinkDecoration(
  dom.Element? owner,
  Map<dom.Element, Map<String, String>> styles,
  Map<dom.Element, EpubRichStyle> rich,
) {
  if (owner == null || owner.localName != 'p') return null;
  final links = owner.querySelectorAll('a[href]');
  if (links.length != 1) return null;
  final link = links.single;
  bool visible(dom.Element e) {
    for (dom.Element? n = e; n != null; n = n.parent) {
      if (n.attributes.containsKey('hidden') ||
          styles[n]?['display'] == 'none' ||
          {'hidden', 'collapse'}.contains(styles[n]?['visibility'])) {
        return false;
      }
      if (n == owner) break;
    }
    return true;
  }

  final nodes = [owner, ...owner.querySelectorAll('*')].where(visible).toList();
  var breaks = 0;
  var textAfterBreak = false;
  void checkBreaks(dom.Node n) {
    if (n is dom.Element && !visible(n)) return;
    if (n is dom.Element && n.localName == 'br') breaks++;
    if (n is dom.Text && n.text.trim().isNotEmpty && breaks > 0) {
      textAfterBreak = true;
    }
    for (final child in n.nodes) {
      checkBreaks(child);
    }
  }

  checkBreaks(owner);
  if (breaks > 1 || textAfterBreak) return null;
  if (nodes.any(
    (e) =>
        e != owner &&
            !{
              'a',
              'span',
              'b',
              'strong',
              'i',
              'em',
              'br',
            }.contains(e.localName) ||
        !{null, 'static'}.contains(styles[e]?['position']) ||
        !{null, 'none'}.contains(styles[e]?['float']) ||
        !{null, 'none'}.contains(styles[e]?['transform']) ||
        {
          'flex',
          'grid',
          'inline-flex',
          'inline-grid',
        }.contains(styles[e]?['display']) ||
        e != owner && styles[e]?['display'] == 'block',
  )) {
    return null;
  }
  final candidates = nodes
      .where((e) => epubColor(styles[e]?['background-color']) != null)
      .toList();
  if (candidates.length != 1) return null;
  final node = candidates.single;
  if (node != owner &&
      (node != link && !link.querySelectorAll('*').contains(node) ||
          node.text != link.text)) {
    return null;
  }
  if (nodes.any(
    (e) => (styles[e] ?? const <String, String>{}).keys.any(
      (key) =>
          key.startsWith('border-') && key != 'border-radius' ||
          e != node && (key.startsWith('padding-') || key == 'border-radius') ||
          {
            'height',
            'min-height',
            'max-height',
            'min-width',
            'box-sizing',
            'left',
            'right',
            'top',
            'bottom',
          }.contains(key) ||
          {'width', 'max-width'}.contains(key) &&
              (e != owner || epubLayoutLength(styles[e]![key]) == null),
    ),
  )) {
    return null;
  }
  final css = styles[node]!;
  final radius = epubLayoutLength(css['border-radius'], percentage: false);
  if (css['border-radius'] != null && radius == null) return null;
  return LinkDecoration(
    backgroundColor: epubColor(css['background-color'])!,
    radius: radius,
    padding: BoxInsets(
      top: epubLayoutLength(css['padding-top']),
      right: epubLayoutLength(css['padding-right']),
      bottom: epubLayoutLength(css['padding-bottom']),
      left: epubLayoutLength(css['padding-left']),
    ),
    fontScale: rich[node]?.scale ?? 1,
    onBlock: node == owner,
  );
}

BlockBox? epubBlockBox(
  Map<String, String> css,
  int group,
  EpubRichStyle style, {
  bool allowEdges = false,
  bool edgesOnly = false,
}) {
  if ({'absolute', 'fixed'}.contains(css['position']) ||
      {'flex', 'grid', 'inline-flex', 'inline-grid'}.contains(css['display']) ||
      css['float'] != null && css['float'] != 'none') {
    return null;
  }
  final background = edgesOnly ? null : epubColor(css['background-color']);
  BoxBorderSide side(String key) {
    final raw = css['border-$key-style'] ?? 'none';
    final type = switch (raw) {
      'none' || 'hidden' => BoxBorderStyle.none,
      'dashed' => BoxBorderStyle.dashed,
      'dotted' => BoxBorderStyle.dotted,
      _ => BoxBorderStyle.solid,
    };
    final width = switch (css['border-$key-width']) {
      'thin' => LayoutLength(1),
      'medium' || null => LayoutLength(3),
      'thick' => LayoutLength(5),
      _ =>
        epubLayoutLength(css['border-$key-width'], percentage: false) ??
            LayoutLength(0),
    };
    return BoxBorderSide(
      width: type == BoxBorderStyle.none || edgesOnly ? LayoutLength(0) : width,
      style: edgesOnly ? BoxBorderStyle.none : type,
      color: epubColor(css['border-$key-color']) ?? style.color,
    );
  }

  final borders = BoxBorders(
    top: side('top'),
    right: side('right'),
    bottom: side('bottom'),
    left: side('left'),
  );
  final decorated =
      background != null ||
      [
        borders.top,
        borders.right,
        borders.bottom,
        borders.left,
      ].any((s) => s!.style != BoxBorderStyle.none && s.width.value > 0);
  BoxInsets insets(String prefix) => BoxInsets(
    top: epubLayoutLength(css['$prefix-top']),
    right: epubLayoutLength(css['$prefix-right']),
    bottom: epubLayoutLength(css['$prefix-bottom']),
    left: epubLayoutLength(css['$prefix-left']),
  );
  final margin = insets('margin'), padding = insets('padding');
  final width = epubLayoutLength(css['width']),
      maxWidth = epubLayoutLength(css['max-width']);
  final hasEdges = [...margin.values, ...padding.values].any((v) => v != null);
  if (!decorated &&
      width == null &&
      maxWidth == null &&
      !(allowEdges && hasEdges)) {
    return null;
  }
  double? pixels(LayoutLength? v) =>
      v?.unit == LayoutUnit.px && v!.value > 0 ? v.value : null;
  double? fraction(LayoutLength? v) =>
      v?.unit == LayoutUnit.fraction && v!.value > 0
      ? v.value.clamp(.01, 1)
      : null;
  return BlockBox(
    group: group,
    width: pixels(width),
    maxWidth: pixels(maxWidth),
    widthFraction: fraction(width),
    maxWidthFraction: fraction(maxWidth),
    widthLength: width,
    maxWidthLength: maxWidth,
    margins: margin,
    paddingEdges: padding,
    borders: borders,
    backgroundColor: background,
    fontScale: style.scale,
    headingRelative: style.defaultHeading && !style.fontSizeFromReader,
    // Legacy accessors are retained; new measurement uses the explicit sides.
    padding:
        (epubLayoutLength(css['padding'])?.unit == LayoutUnit.px
                ? epubLayoutLength(css['padding'])!.value
                : 0)
            .clamp(0, 64)
            .toDouble(),
    borderWidth:
        (borders.top!.width.unit == LayoutUnit.px
                ? borders.top!.width.value
                : 0)
            .clamp(0, 8)
            .toDouble(),
    borderColor: borders.top!.color,
    dashed: borders.top!.style == BoxBorderStyle.dashed,
    centered: css['margin-left'] == 'auto' && css['margin-right'] == 'auto',
    autoLeft: css['margin-left'] == 'auto',
    autoRight: css['margin-right'] == 'auto',
  );
}
