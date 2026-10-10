import 'value_model.dart';
import 'identity.dart';
import 'embedded_font.dart';
export 'embedded_font.dart';

/// Authored relative typography; layout metadata never changes text identity.
final class InlineTextStyle extends ValueModel {
  InlineTextStyle({
    required this.start,
    required this.length,
    this.color,
    this.fontScale = 1,
    this.fontSizeFromReader = false,
    this.bold,
    this.italic,
    Iterable<EmbeddedFontFamily> fonts = const [],
  }) : fonts = List.unmodifiable(fonts) {
    if (start < 0 ||
        length <= 0 ||
        this.fonts.length > 8 ||
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

  /// Absolute authored sizes use the user's medium, not a heading's default.
  final bool fontSizeFromReader;

  /// Null inherits the reader base; false is an explicit authored reset.
  final bool? bold, italic;
  final List<EmbeddedFontFamily> fonts;
  bool get isNoOp =>
      color == null &&
      fontScale == 1 &&
      !fontSizeFromReader &&
      bold == null &&
      italic == null &&
      fonts.isEmpty;
  Map<String, Object?> toJson() => {
    'start': start,
    'length': length,
    'color': color,
    'fontScale': fontScale,
    if (fontSizeFromReader) 'fontSizeFromReader': true,
    'bold': bold,
    'italic': italic,
    if (fonts.isNotEmpty) 'fonts': fonts.map((f) => f.toJson()).toList(),
  };
  factory InlineTextStyle.fromJson(Map<String, dynamic> j) => InlineTextStyle(
    start: j['start'] as int,
    length: j['length'] as int,
    color: j['color'] as int?,
    fontScale: (j['fontScale'] as num).toDouble(),
    fontSizeFromReader: j['fontSizeFromReader'] as bool? ?? false,
    bold: j['bold'] as bool?,
    italic: j['italic'] as bool?,
    fonts: (j['fonts'] as List? ?? const []).map(
      (f) => EmbeddedFontFamily.fromJson(f as Map<String, dynamic>),
    ),
  );
  @override
  List<Object?> get values => [
    start,
    length,
    color,
    fontScale,
    fontSizeFromReader,
    bold,
    italic,
    fonts,
  ];
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

enum LayoutUnit { px, em, fraction }

/// Optional CSS geometry, resolved against the actual containing content box.
final class LayoutLength extends ValueModel {
  LayoutLength(this.value, [this.unit = LayoutUnit.px]) {
    if (!value.isFinite || value < 0 || value > 4096) {
      throw ArgumentError('Invalid layout length');
    }
  }
  final double value;
  final LayoutUnit unit;
  double resolve(double width, double em) => switch (unit) {
    LayoutUnit.px => value,
    LayoutUnit.em => value * em,
    LayoutUnit.fraction => value * width,
  };
  Map<String, Object?> toJson() => {'value': value, 'unit': unit.name};
  factory LayoutLength.fromJson(Map<String, dynamic> j) => LayoutLength(
    (j['value'] as num).toDouble(),
    LayoutUnit.values.byName(j['unit'] as String),
  );
  @override
  List<Object?> get values => [value, unit];
}

final class BoxInsets extends ValueModel {
  BoxInsets({this.top, this.right, this.bottom, this.left});
  final LayoutLength? top, right, bottom, left;
  Map<String, Object?> toJson() => {
    for (final side in {
      'top': top,
      'right': right,
      'bottom': bottom,
      'left': left,
    }.entries)
      if (side.value != null) side.key: side.value!.toJson(),
  };
  factory BoxInsets.fromJson(Map<String, dynamic> j) {
    LayoutLength? side(String key) => j[key] == null
        ? null
        : LayoutLength.fromJson(j[key] as Map<String, dynamic>);
    return BoxInsets(
      top: side('top'),
      right: side('right'),
      bottom: side('bottom'),
      left: side('left'),
    );
  }
  @override
  List<Object?> get values => [top, right, bottom, left];
}

enum BoxBorderStyle { none, solid, dashed, dotted, doubleLine, ridge, groove }

/// A single whole-paragraph native link label; text and link ranges are intact.
final class LinkDecoration extends ValueModel {
  LinkDecoration({
    required this.backgroundColor,
    required this.padding,
    this.radius,
    this.fontScale = 1,
    this.onBlock = false,
  }) {
    if (backgroundColor < 0 ||
        backgroundColor > 0xffffffff ||
        !fontScale.isFinite ||
        fontScale < .25 ||
        fontScale > 4 ||
        radius?.unit == LayoutUnit.fraction) {
      throw ArgumentError('Invalid link decoration');
    }
  }
  final int backgroundColor;
  final BoxInsets padding;
  final LayoutLength? radius;
  final double fontScale;

  /// The paragraph box supplies width and padding; the link paints it once.
  final bool onBlock;
  Map<String, Object?> toJson() => {
    'backgroundColor': backgroundColor,
    'padding': padding.toJson(),
    if (radius != null) 'radius': radius!.toJson(),
    'fontScale': fontScale,
    if (onBlock) 'onBlock': true,
  };
  factory LinkDecoration.fromJson(Map<String, dynamic> j) => LinkDecoration(
    backgroundColor: j['backgroundColor'] as int,
    padding: BoxInsets.fromJson(j['padding'] as Map<String, dynamic>),
    radius: j['radius'] == null
        ? null
        : LayoutLength.fromJson(j['radius'] as Map<String, dynamic>),
    fontScale: (j['fontScale'] as num?)?.toDouble() ?? 1,
    onBlock: j['onBlock'] as bool? ?? false,
  );
  @override
  List<Object?> get values => [
    backgroundColor,
    padding,
    radius,
    fontScale,
    onBlock,
  ];
}

final class BoxBorderSide extends ValueModel {
  BoxBorderSide({
    required this.width,
    this.style = BoxBorderStyle.solid,
    this.color,
  }) {
    if (color != null && (color! < 0 || color! > 0xffffffff)) {
      throw ArgumentError('Invalid border color');
    }
  }
  final LayoutLength width;
  final BoxBorderStyle style;
  final int? color;
  Map<String, Object?> toJson() => {
    'width': width.toJson(),
    'style': style.name,
    'color': color,
  };
  factory BoxBorderSide.fromJson(Map<String, dynamic> j) => BoxBorderSide(
    width: LayoutLength.fromJson(j['width'] as Map<String, dynamic>),
    style: BoxBorderStyle.values.byName(j['style'] as String),
    color: j['color'] as int?,
  );
  @override
  List<Object?> get values => [width, style, color];
}

final class BoxBorders extends ValueModel {
  BoxBorders({this.top, this.right, this.bottom, this.left});
  final BoxBorderSide? top, right, bottom, left;
  Map<String, Object?> toJson() => {
    for (final side in {
      'top': top,
      'right': right,
      'bottom': bottom,
      'left': left,
    }.entries)
      if (side.value != null) side.key: side.value!.toJson(),
  };
  factory BoxBorders.fromJson(Map<String, dynamic> j) {
    BoxBorderSide? side(String key) => j[key] == null
        ? null
        : BoxBorderSide.fromJson(j[key] as Map<String, dynamic>);
    return BoxBorders(
      top: side('top'),
      right: side('right'),
      bottom: side('bottom'),
      left: side('left'),
    );
  }
  @override
  List<Object?> get values => [top, right, bottom, left];
}

/// Two empty side cells around one content cell in a bounded decoration row.
final class DecorationColumns extends ValueModel {
  DecorationColumns({
    required this.leadingFraction,
    required this.trailingFraction,
  }) {
    if (!leadingFraction.isFinite ||
        !trailingFraction.isFinite ||
        leadingFraction <= 0 ||
        trailingFraction <= 0 ||
        leadingFraction + trailingFraction >= 1) {
      throw ArgumentError('Invalid decoration columns');
    }
  }
  final double leadingFraction, trailingFraction;
  double get contentFraction => 1 - leadingFraction - trailingFraction;
  Map<String, Object?> toJson() => {
    'leadingFraction': leadingFraction,
    'trailingFraction': trailingFraction,
  };
  factory DecorationColumns.fromJson(Map<String, dynamic> j) =>
      DecorationColumns(
        leadingFraction: (j['leadingFraction'] as num).toDouble(),
        trailingFraction: (j['trailingFraction'] as num).toDouble(),
      );
  @override
  List<Object?> get values => [leadingFraction, trailingFraction];
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
    this.backgroundImage,
    this.dashed = false,
    this.centered = false,
    this.widthLength,
    this.maxWidthLength,
    this.margins,
    this.paddingEdges,
    this.borders,
    this.decorationColumns,
    this.radius,
    this.fontScale = 1,
    this.headingRelative = false,
    this.autoLeft = false,
    this.autoRight = false,
  }) {
    if (radius?.unit == LayoutUnit.fraction ||
        !fontScale.isFinite ||
        fontScale < .25 ||
        fontScale > 4 ||
        [
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
  final BlockBackgroundImage? backgroundImage;
  final bool dashed;

  /// Both horizontal CSS margins are auto; independent of text alignment.
  final bool centered;
  final LayoutLength? widthLength, maxWidthLength;
  final BoxInsets? margins, paddingEdges;

  /// Null preserves legacy uniform borders. CSS boxes always store all sides.
  final BoxBorders? borders;

  /// Absent in older manifests. The bottom edge has an opening at the content cell.
  final DecorationColumns? decorationColumns;

  /// Uniform circular corners; absent in older manifests. Paint-only geometry.
  final LayoutLength? radius;
  final double fontScale;
  final bool headingRelative, autoLeft, autoRight;
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
    if (backgroundImage != null) 'backgroundImage': backgroundImage!.toJson(),
    'dashed': dashed,
    'centered': centered,
    if (widthLength != null) 'widthLength': widthLength!.toJson(),
    if (maxWidthLength != null) 'maxWidthLength': maxWidthLength!.toJson(),
    if (margins != null) 'margins': margins!.toJson(),
    if (paddingEdges != null) 'paddingEdges': paddingEdges!.toJson(),
    if (borders != null) 'borders': borders!.toJson(),
    if (decorationColumns != null)
      'decorationColumns': decorationColumns!.toJson(),
    if (radius != null) 'radius': radius!.toJson(),
    'fontScale': fontScale,
    'headingRelative': headingRelative,
    'autoLeft': autoLeft,
    'autoRight': autoRight,
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
    backgroundImage: j['backgroundImage'] == null
        ? null
        : BlockBackgroundImage.fromJson(
            j['backgroundImage'] as Map<String, dynamic>,
          ),
    dashed: j['dashed'] as bool,
    centered: j['centered'] as bool? ?? false,
    widthLength: j['widthLength'] == null
        ? null
        : LayoutLength.fromJson(j['widthLength'] as Map<String, dynamic>),
    maxWidthLength: j['maxWidthLength'] == null
        ? null
        : LayoutLength.fromJson(j['maxWidthLength'] as Map<String, dynamic>),
    margins: j['margins'] == null
        ? null
        : BoxInsets.fromJson(j['margins'] as Map<String, dynamic>),
    paddingEdges: j['paddingEdges'] == null
        ? null
        : BoxInsets.fromJson(j['paddingEdges'] as Map<String, dynamic>),
    borders: j['borders'] == null
        ? null
        : BoxBorders.fromJson(j['borders'] as Map<String, dynamic>),
    decorationColumns: j['decorationColumns'] == null
        ? null
        : DecorationColumns.fromJson(
            j['decorationColumns'] as Map<String, dynamic>,
          ),
    radius: j['radius'] == null
        ? null
        : LayoutLength.fromJson(j['radius'] as Map<String, dynamic>),
    fontScale: (j['fontScale'] as num?)?.toDouble() ?? 1,
    headingRelative: j['headingRelative'] as bool? ?? false,
    autoLeft: j['autoLeft'] as bool? ?? false,
    autoRight: j['autoRight'] as bool? ?? false,
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
    backgroundImage,
    dashed,
    centered,
    widthLength,
    maxWidthLength,
    margins,
    paddingEdges,
    borders,
    decorationColumns,
    radius,
    fontScale,
    headingRelative,
    autoLeft,
    autoRight,
  ];
}

/// One nonrepeating raster decoration, positioned inside a block's padding box.
final class BlockBackgroundImage extends ValueModel {
  BlockBackgroundImage({
    required this.media,
    required this.intrinsicWidth,
    required this.intrinsicHeight,
    this.width,
    this.height,
    this.x = 0,
    this.y = 0,
  }) {
    if (intrinsicWidth <= 0 ||
        intrinsicHeight <= 0 ||
        intrinsicWidth > 32768 ||
        intrinsicHeight > 32768 ||
        !x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1 ||
        width?.value == 0 ||
        height?.value == 0) {
      throw ArgumentError('Invalid background image');
    }
  }
  final MediaRef media;
  final int intrinsicWidth, intrinsicHeight;
  final LayoutLength? width, height;
  final double x, y;
  Map<String, Object?> toJson() => {
    'media': media.toJson(),
    'intrinsicWidth': intrinsicWidth,
    'intrinsicHeight': intrinsicHeight,
    if (width != null) 'width': width!.toJson(),
    if (height != null) 'height': height!.toJson(),
    'x': x,
    'y': y,
  };
  factory BlockBackgroundImage.fromJson(Map<String, dynamic> j) =>
      BlockBackgroundImage(
        media: MediaRef.fromJson(j['media'] as Map<String, dynamic>),
        intrinsicWidth: j['intrinsicWidth'] as int,
        intrinsicHeight: j['intrinsicHeight'] as int,
        width: j['width'] == null
            ? null
            : LayoutLength.fromJson(j['width'] as Map<String, dynamic>),
        height: j['height'] == null
            ? null
            : LayoutLength.fromJson(j['height'] as Map<String, dynamic>),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
      );
  @override
  List<Object?> get values => [
    media,
    intrinsicWidth,
    intrinsicHeight,
    width,
    height,
    x,
    y,
  ];
}
