import 'value_model.dart';

/// Authored relative typography; layout metadata never changes text identity.
final class InlineTextStyle extends ValueModel {
  InlineTextStyle({
    required this.start,
    required this.length,
    this.color,
    this.fontScale = 1,
    this.bold,
    this.italic,
  }) {
    if (start < 0 ||
        length <= 0 ||
        !fontScale.isFinite ||
        fontScale < .25 ||
        fontScale > 4 ||
        (color != null && (color! < 0 || color! > 0xffffffff))) {
      throw ArgumentError('Invalid authored text style');
    }
  }
  final int start, length;
  final int? color;
  final double fontScale;
  /// Null inherits the reader base; false is an explicit authored reset.
  final bool? bold, italic;
  bool get isNoOp =>
      color == null && fontScale == 1 && bold == null && italic == null;
  Map<String, Object?> toJson() => {
    'start': start,
    'length': length,
    'color': color,
    'fontScale': fontScale,
    'bold': bold,
    'italic': italic,
  };
  factory InlineTextStyle.fromJson(Map<String, dynamic> j) => InlineTextStyle(
    start: j['start'] as int,
    length: j['length'] as int,
    color: j['color'] as int?,
    fontScale: (j['fontScale'] as num).toDouble(),
    bold: j['bold'] as bool?,
    italic: j['italic'] as bool?,
  );
  @override
  List<Object?> get values => [start, length, color, fontScale, bold, italic];
}

void validateInlineStyles(String text, List<InlineTextStyle> styles) {
  if (styles.isEmpty) return;
  var end = 0;
  final length = text.runes.length;
  for (final style in styles) {
    if (style.start < end || style.start + style.length > length) {
      throw ArgumentError('Authored style ranges must be ordered and disjoint');
    }
    end = style.start + style.length;
  }
}

/// One simple authored container shared by consecutive semantic blocks.
/// CSS pixels remain layout units; widths are capped to the reading viewport.
final class BlockBox extends ValueModel {
  BlockBox({
    required this.group,
    this.width,
    this.maxWidth,
    this.widthFraction,
    this.maxWidthFraction,
    this.padding = 0,
    this.borderWidth = 0,
    this.borderColor,
    this.backgroundColor,
    this.dashed = false,
  }) {
    if ([
          widthFraction,
          maxWidthFraction,
        ].any((v) => v != null && (!v.isFinite || v <= 0 || v > 1)) ||
        group < 0 ||
        [
          width,
          maxWidth,
        ].any((v) => v != null && (!v.isFinite || v <= 0 || v > 4096)) ||
        !padding.isFinite ||
        padding < 0 ||
        padding > 64 ||
        !borderWidth.isFinite ||
        borderWidth < 0 ||
        borderWidth > 8 ||
        [
          borderColor,
          backgroundColor,
        ].any((v) => v != null && (v < 0 || v > 0xffffffff))) {
      throw ArgumentError('Invalid authored box');
    }
  }
  final int group;
  final double? width, maxWidth, widthFraction, maxWidthFraction;
  final double padding, borderWidth;
  final int? borderColor, backgroundColor;
  final bool dashed;
  Map<String, Object?> toJson() => {
    'group': group,
    'width': width,
    'maxWidth': maxWidth,
    'widthFraction': widthFraction,
    'maxWidthFraction': maxWidthFraction,
    'padding': padding,
    'borderWidth': borderWidth,
    'borderColor': borderColor,
    'backgroundColor': backgroundColor,
    'dashed': dashed,
  };
  factory BlockBox.fromJson(Map<String, dynamic> j) => BlockBox(
    group: j['group'] as int,
    width: (j['width'] as num?)?.toDouble(),
    maxWidth: (j['maxWidth'] as num?)?.toDouble(),
    widthFraction: (j['widthFraction'] as num?)?.toDouble(),
    maxWidthFraction: (j['maxWidthFraction'] as num?)?.toDouble(),
    padding: (j['padding'] as num).toDouble(),
    borderWidth: (j['borderWidth'] as num).toDouble(),
    borderColor: j['borderColor'] as int?,
    backgroundColor: j['backgroundColor'] as int?,
    dashed: j['dashed'] as bool,
  );
  @override
  List<Object?> get values => [
    group,
    width,
    maxWidth,
    widthFraction,
    maxWidthFraction,
    padding,
    borderWidth,
    borderColor,
    backgroundColor,
    dashed,
  ];
}
