import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../domain/models/models.dart';
import '../reader_authored_colors.dart';
import 'block_style.dart';
import '../reader_inline_images.dart';
import '../../../domain/contracts/contracts.dart';
import '../../../shared/source_image.dart';

class ReaderLinkLayout {
  const ReaderLinkLayout(this.width, this.height, this.padding, this.radius);
  final double width, height, radius;
  final EdgeInsets padding;
}

/// Measure the actual label, using the same spans as the painted native text.
ReaderLinkLayout? readerLinkLayout(
  ParagraphBlock block,
  double width,
  TextStyle base,
  TextScaler scaler,
  TextDirection direction, {
  Locale? locale,
  TextHeightBehavior? heightBehavior,
  ChapterKey? chapter,
  ReaderBoxGeometry? box,
}) {
  final decoration = block.linkDecoration;
  if (decoration == null) return null;
  final em = scaler.scale((base.fontSize ?? 20) * decoration.fontScale);
  double length(LayoutLength? v) =>
      (v?.resolve(width, em) ?? 0).clamp(0, em * 2);
  var left = length(decoration.padding.left),
      right = length(decoration.padding.right);
  final room = math.max(0.0, width - math.min(width, em * 4));
  if (left + right > room && left + right > 0) {
    final factor = room / (left + right);
    left *= factor;
    right *= factor;
  }
  final padding = decoration.onBlock && box != null
      ? EdgeInsets.fromLTRB(
          box.paddingLeft,
          box.paddingTop,
          box.paddingRight,
          box.paddingBottom,
        )
      : EdgeInsets.fromLTRB(
          left,
          length(decoration.padding.top),
          right,
          length(decoration.padding.bottom),
        );
  final style = readerBlockStyle(block, base, chapter: chapter);
  final painter =
      TextPainter(
        text: TextSpan(
          style: style,
          children: readerInlineSpans(
            text: block.text,
            offset: 0,
            images: const [],
            styles: block.inlineStyles,
            style: style,
            readerFontSize: base.fontSize,
          ),
        ),
        textDirection: direction,
        textAlign: readerBlockAlign(block, chapter: chapter),
        textScaler: scaler,
        locale: locale,
        textHeightBehavior: heightBehavior,
      )..layout(
        maxWidth: math.max(
          1.0,
          decoration.onBlock ? width : width - padding.horizontal,
        ),
      );
  try {
    final w = decoration.onBlock
            ? width + padding.horizontal
            : math.min(width, painter.width + padding.horizontal),
        h = painter.height + padding.vertical;
    return ReaderLinkLayout(
      w,
      h,
      padding,
      (decoration.radius?.resolve(width, em) ?? 0).clamp(0, math.min(w, h) / 2),
    );
  } finally {
    painter.dispose();
  }
}

/// Geometry for one bounded box. Width is the border box; margins stay outside
/// paint. Percentages always resolve against the containing content width.
class ReaderBoxGeometry {
  ReaderBoxGeometry(
    this.box,
    double available,
    this.em,
    double pageHeight, {
    double? minimumContentHeight,
    double leadingOffset = 0,
    double trailingOffset = 0,
  }) {
    final cap = pageHeight.isFinite
        ? math.max(0.0, (pageHeight - (minimumContentHeight ?? em * 1.6)) / 2)
        : double.infinity;
    double length(LayoutLength? v) => v?.resolve(available, em) ?? 0;
    final m = box.margins, p = box.paddingEdges;
    requestedMarginTop = length(m?.top);
    var ml = length(m?.left), mr = length(m?.right);
    final horizontalBudget = math.max(
      0.0,
      available - math.min(available, em * 4),
    );
    final ms = ml + mr;
    if (ms > horizontalBudget && ms > 0) {
      ml *= horizontalBudget / ms;
      mr *= horizontalBudget / ms;
    }
    double border(BoxBorderSide? s) => s == null
        ? box.borders == null
              ? box.borderWidth
              : 0
        : s.style == BoxBorderStyle.none
        ? 0
        : length(s.width).clamp(0, 8);
    borderTop = math.min(border(box.borders?.top), cap);
    borderRight = border(box.borders?.right);
    borderBottom = math.min(border(box.borders?.bottom), cap);
    borderLeft = border(box.borders?.left);
    var pl = p == null ? box.padding : length(p.left),
        pr = p == null ? box.padding : length(p.right);
    final room = math.max(
      0.0,
      available -
          ml -
          mr -
          borderLeft -
          borderRight -
          math.min(available, em * 4),
    );
    if (pl + pr > room && pl + pr > 0) {
      final factor = room / (pl + pr);
      pl *= factor;
      pr *= factor;
    }
    paddingLeft = pl;
    paddingRight = pr;
    final inset = pl + pr + borderLeft + borderRight;
    final contentRoom = math.max(1.0, available - ml - mr - inset);
    final requestedWidth =
        box.widthLength?.resolve(available, em) ??
        (box.widthFraction == null
            ? box.width
            : available * box.widthFraction!);
    final requestedMax =
        box.maxWidthLength?.resolve(available, em) ??
        (box.maxWidthFraction == null
            ? box.maxWidth
            : available * box.maxWidthFraction!);
    contentWidth = math
        .min(
          requestedWidth ?? contentRoom,
          math.min(requestedMax ?? contentRoom, contentRoom),
        )
        .clamp(1, contentRoom);
    width = contentWidth + inset;
    radius = length(box.radius);
    final free = math.max(0.0, available - width - ml - mr);
    if (box.centered || box.autoLeft && box.autoRight) {
      ml += free / 2;
      mr += free / 2;
    } else if (box.autoLeft) {
      ml += free;
    }
    marginLeft = ml + leadingOffset;
    marginRight = mr + trailingOffset;
    // Optional whitespace shrinks on a fresh short page; reserve content room.
    void vertical(double margin, double padding, double border, bool top) {
      final requested = margin + padding;
      final budget = math.max(0.0, cap - border);
      final factor = requested > budget && requested > 0
          ? budget / requested
          : 1.0;
      if (top) {
        marginTop = margin * factor;
        paddingTop = padding * factor;
      } else {
        marginBottom = margin * factor;
        paddingBottom = padding * factor;
      }
    }

    vertical(
      requestedMarginTop,
      p == null ? box.padding : length(p.top),
      borderTop,
      true,
    );
    vertical(
      length(m?.bottom),
      p == null ? box.padding : length(p.bottom),
      borderBottom,
      false,
    );
  }
  final BlockBox box;
  final double em;
  late final double requestedMarginTop,
      marginTop,
      marginRight,
      marginBottom,
      marginLeft;
  late final double paddingTop, paddingRight, paddingBottom, paddingLeft;
  late final double borderTop,
      borderRight,
      borderBottom,
      borderLeft,
      width,
      contentWidth,
      radius;
  double get top => marginTop + paddingTop + borderTop;
  double get bottom => marginBottom + paddingBottom + borderBottom;
}

ReaderBoxGeometry? readerBoxGeometry(
  BlockBox? box,
  ContentBlock block,
  double available,
  TextStyle style,
  TextScaler scaler, {
  double pageHeight = double.infinity,
  double? minimumContentHeight,
  double leadingOffset = 0,
  double trailingOffset = 0,
}) {
  if (box == null) return null;
  final headingScale = box.headingRelative
      ? (readerBlockStyle(block, style).fontSize ?? 20) / (style.fontSize ?? 20)
      : 1.0;
  return ReaderBoxGeometry(
    box,
    available,
    scaler.scale((style.fontSize ?? 20) * box.fontScale * headingScale),
    pageHeight,
    minimumContentHeight: minimumContentHeight,
    leadingOffset: leadingOffset,
    trailingOffset: trailingOffset,
  );
}

({ReaderBoxGeometry? outer, ReaderBoxGeometry? local, double innerWidth})
readerBlockBoxes(
  ContentBlock block,
  double available,
  TextStyle style,
  TextScaler scaler, {
  double pageHeight = double.infinity,
  double? minimumContentHeight,
}) {
  final textStyle = block is HeadingBlock
      ? readerBlockStyle(block, style)
      : style;
  var font = textStyle.fontSize ?? 20;
  for (final span in block.inlineStyles) {
    final base = span.fontSizeFromReader
        ? style.fontSize ?? 20
        : textStyle.fontSize ?? 20;
    font = math.max(font, base * span.fontScale);
  }
  final contentHeight = math.max(
    scaler.scale(font) * (textStyle.height ?? 1.6),
    minimumContentHeight ?? 0,
  );
  final levels = block.box != null && block.layout != null ? 2 : 1;
  // Reserve one real text row across the bounded pair of boxes, including
  // authored heading size. Each level shares only the optional edge budget.
  final edgeHeight = (pageHeight - contentHeight) / levels + contentHeight;
  var outer = readerBoxGeometry(
    block.box,
    block,
    available,
    style,
    scaler,
    pageHeight: edgeHeight,
    minimumContentHeight: contentHeight,
  );
  final columns = block.box?.decorationColumns;
  var localAvailable = outer?.contentWidth ?? available;
  var columnOffset = 0.0, trailingOffset = 0.0;
  if (columns != null && outer != null) {
    final cellWidth = localAvailable * columns.contentFraction;
    // Keep ordinary text readable at narrow widths / large user font sizes.
    if (cellWidth < scaler.scale(font) * 4) {
      outer = null;
      localAvailable = available;
    } else {
      columnOffset = localAvailable * columns.leadingFraction;
      trailingOffset = localAvailable * columns.trailingFraction;
      localAvailable = cellWidth;
    }
  }
  final local = readerBoxGeometry(
    block.layout,
    block,
    localAvailable,
    style,
    scaler,
    pageHeight: edgeHeight,
    minimumContentHeight: contentHeight,
    leadingOffset: columnOffset,
    trailingOffset: trailingOffset,
  );
  return (
    outer: outer,
    local: local,
    innerWidth: local?.contentWidth ?? outer?.contentWidth ?? available,
  );
}

double readerBoxOuterWidth(
  ContentBlock block,
  double available, {
  TextStyle style = const TextStyle(fontSize: 16),
  TextScaler scaler = TextScaler.noScaling,
}) {
  final boxes = readerBlockBoxes(block, available, style, scaler);
  return boxes.outer?.width ?? boxes.local?.width ?? available;
}

double readerBoxInnerWidth(
  ContentBlock block,
  double available, {
  TextStyle style = const TextStyle(fontSize: 16),
  TextScaler scaler = TextScaler.noScaling,
}) => readerBlockBoxes(block, available, style, scaler).innerWidth;

({
  double top,
  double bottom,
  double outerTop,
  double outerBottom,
  double localTop,
  double localBottom,
})
readerBoxEdges(
  ChapterContent content,
  int index, {
  double width = 300,
  TextStyle style = const TextStyle(fontSize: 16),
  TextScaler scaler = TextScaler.noScaling,
  double pageHeight = double.infinity,
  double? minimumContentHeight,
}) {
  final block = content.blocks[index], box = block.box;
  final boxes = readerBlockBoxes(
    block,
    width,
    style,
    scaler,
    pageHeight: pageHeight,
    minimumContentHeight: minimumContentHeight,
  );
  final outerTop =
      boxes.outer != null &&
          (index == 0 || content.blocks[index - 1].box?.group != box?.group)
      ? boxes.outer!.top
      : 0.0;
  final outerBottom =
      boxes.outer != null &&
          (index + 1 == content.blocks.length ||
              content.blocks[index + 1].box?.group != box?.group)
      ? boxes.outer!.bottom
      : 0.0;
  final localTop = boxes.local?.top ?? 0.0,
      localBottom = boxes.local?.bottom ?? 0.0;
  return (
    top: outerTop + localTop,
    bottom: outerBottom + localBottom,
    outerTop: outerTop,
    outerBottom: outerBottom,
    localTop: localTop,
    localBottom: localBottom,
  );
}

/// Only decoded decorations may keep light author ink. Failed or omitted
/// backgrounds retain the reader's normal contrast policy.
class ReaderBackgroundPresence extends InheritedWidget {
  const ReaderBackgroundPresence({
    super.key,
    required this.visible,
    required super.child,
  });
  final bool visible;
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ReaderBackgroundPresence>()
          ?.visible ??
      false;
  @override
  bool updateShouldNotify(ReaderBackgroundPresence oldWidget) =>
      visible != oldWidget.visible;
}

class _ReaderBackgroundReady extends StatefulWidget {
  const _ReaderBackgroundReady({
    required this.media,
    required this.repository,
    required this.builder,
  });
  final MediaRef? media;
  final ImageRepository? repository;
  final Widget Function(BuildContext, ValueChanged<Size>) builder;
  @override
  State<_ReaderBackgroundReady> createState() => _ReaderBackgroundReadyState();
}

class _ReaderBackgroundReadyState extends State<_ReaderBackgroundReady> {
  bool _ready = false;
  @override
  void didUpdateWidget(_ReaderBackgroundReady oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.media != oldWidget.media ||
        widget.repository != oldWidget.repository) {
      _ready = false;
    }
  }

  @override
  Widget build(BuildContext context) => ReaderBackgroundPresence(
    visible: _ready || ReaderBackgroundPresence.of(context),
    child: Builder(
      builder: (context) => widget.builder(context, (_) {
        if (mounted && !_ready) setState(() => _ready = true);
      }),
    ),
  );
}

class ReaderBoxFrame extends StatelessWidget {
  const ReaderBoxFrame({
    super.key,
    required this.box,
    required this.width,
    required this.top,
    required this.bottom,
    required this.child,
    this.geometry,
    this.starts,
    this.ends,
    this.linkOwnsDecoration = false,
    this.images,
  });
  final BlockBox? box;
  final double width, top, bottom;
  final Widget child;
  final ReaderBoxGeometry? geometry;
  final bool? starts, ends;
  final bool linkOwnsDecoration;
  final ImageRepository? images;
  @override
  Widget build(BuildContext context) {
    final b = box;
    if (b == null) return child;
    final g = geometry ?? ReaderBoxGeometry(b, width, 16, double.infinity);
    final start = starts ?? top > 0, end = ends ?? bottom > 0;
    final mt = start ? math.min(top, g.marginTop) : 0.0;
    final mb = end ? math.min(bottom, g.marginBottom) : 0.0;
    return Padding(
      padding: EdgeInsets.only(
        left: g.marginLeft,
        right: 0,
        top: mt,
        bottom: mb,
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: CustomPaint(
            painter: linkOwnsDecoration
                ? null
                : ReaderBoxPainter(
                    b,
                    g,
                    start,
                    end,
                    ReaderAuthoredColors(Theme.of(context)),
                  ),
            child: _ReaderBackgroundReady(
              repository: images,
              media: images != null && start && end
                  ? b.backgroundImage?.media
                  : null,
              builder: (context, onReady) => Stack(
                fit: StackFit.passthrough,
                children: [
                  if (b.backgroundImage != null &&
                      images != null &&
                      start &&
                      end)
                    Positioned.fill(
                      left: g.borderLeft,
                      right: g.borderRight,
                      top: g.borderTop,
                      bottom: g.borderBottom,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: ClipRRect(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.elliptical(
                                math.max(0, g.radius - g.borderLeft),
                                math.max(0, g.radius - g.borderTop),
                              ),
                              topRight: Radius.elliptical(
                                math.max(0, g.radius - g.borderRight),
                                math.max(0, g.radius - g.borderTop),
                              ),
                              bottomLeft: Radius.elliptical(
                                math.max(0, g.radius - g.borderLeft),
                                math.max(0, g.radius - g.borderBottom),
                              ),
                              bottomRight: Radius.elliptical(
                                math.max(0, g.radius - g.borderRight),
                                math.max(0, g.radius - g.borderBottom),
                              ),
                            ),
                            child: LayoutBuilder(
                              builder: (context, bounds) {
                                final image = b.backgroundImage!;
                                final em = g.em;
                                var w = image.width?.resolve(
                                      bounds.maxWidth,
                                      em,
                                    ),
                                    h = image.height?.resolve(
                                      bounds.maxHeight,
                                      em,
                                    );
                                if (w == null && h == null) {
                                  w = image.intrinsicWidth.toDouble();
                                  h = image.intrinsicHeight.toDouble();
                                }
                                w ??=
                                    h! *
                                    image.intrinsicWidth /
                                    image.intrinsicHeight;
                                h ??=
                                    w *
                                    image.intrinsicHeight /
                                    image.intrinsicWidth;
                                return Align(
                                  alignment: Alignment(
                                    image.x * 2 - 1,
                                    image.y * 2 - 1,
                                  ),
                                  child: OverflowBox(
                                    minWidth: w,
                                    maxWidth: w,
                                    minHeight: h,
                                    maxHeight: h,
                                    alignment: Alignment(
                                      image.x * 2 - 1,
                                      image.y * 2 - 1,
                                    ),
                                    child: SizedBox(
                                      width: w,
                                      height: h,
                                      child: SourceImage(
                                        media: image.media,
                                        repository: images!,
                                        placeholder: const SizedBox.shrink(),
                                        onIntrinsicSize: onReady,
                                        backgroundColor: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      linkOwnsDecoration ? 0 : g.paddingLeft + g.borderLeft,
                      math.max(0, top - mt),
                      linkOwnsDecoration ? 0 : g.paddingRight + g.borderRight,
                      math.max(0, bottom - mb),
                    ),
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paint only the requested sides; slice boundaries never close the container.
class ReaderBoxPainter extends CustomPainter {
  ReaderBoxPainter(this.box, this.geometry, this.top, this.bottom, this.colors);
  final BlockBox box;
  final ReaderBoxGeometry geometry;
  final bool top, bottom;
  final ReaderAuthoredColors colors;
  @override
  void paint(Canvas canvas, Size size) {
    final background = box.backgroundColor == null
        ? null
        : colors.resolve(
            Color(box.backgroundColor!),
            ReaderColorRole.background,
          );
    final g = geometry;
    if (size.isEmpty) return;
    final widths = [
      top ? g.borderTop : 0.0,
      g.borderRight,
      bottom ? g.borderBottom : 0.0,
      g.borderLeft,
    ];
    final radius = g.radius.clamp(0.0, math.min(size.width, size.height) / 2);
    RRect shape(double inset) {
      final t = widths[0] * inset,
          r = widths[1] * inset,
          b = widths[2] * inset,
          l = widths[3] * inset;
      Radius corner(bool enabled, double x, double y) => enabled
          ? Radius.elliptical(math.max(0, radius - x), math.max(0, radius - y))
          : Radius.zero;
      return RRect.fromRectAndCorners(
        Rect.fromLTRB(
          l,
          t,
          math.max(l, size.width - r),
          math.max(t, size.height - b),
        ),
        topLeft: corner(top, l, t),
        topRight: corner(top, r, t),
        bottomLeft: corner(bottom, l, b),
        bottomRight: corner(bottom, r, b),
      );
    }

    final outer = shape(0);
    if (background != null) {
      canvas.drawRRect(outer, Paint()..color = background);
    }
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    final rays = [
      Offset(widths[3], widths[0]),
      Offset(-widths[1], widths[0]),
      Offset(-widths[1], -widths[2]),
      Offset(widths[3], -widths[2]),
    ];
    final center = Offset(size.width / 2, size.height / 2);
    // Extend side joins beyond the inner rectangle to cover the rounded arcs.
    Offset extendedJoin(int i) {
      final ray = rays[i];
      final scale = math.min(
        ray.dx == 0 ? double.infinity : center.dx / ray.dx.abs(),
        ray.dy == 0 ? double.infinity : center.dy / ray.dy.abs(),
      );
      return scale.isFinite ? corners[i] + ray * scale : center;
    }

    final inside = [for (var i = 0; i < 4; i++) extendedJoin(i)];
    final sides = [
      box.borders?.top,
      box.borders?.right,
      box.borders?.bottom,
      box.borders?.left,
    ];
    for (var i = 0; i < 4; i++) {
      final width = widths[i];
      if (width <= 0) continue;
      final type =
          sides[i]?.style ??
          (box.dashed ? BoxBorderStyle.dashed : BoxBorderStyle.solid);
      if (type == BoxBorderStyle.none) continue;
      final color = colors.resolve(
        Color(sides[i]?.color ?? box.borderColor ?? 0xff808080),
        ReaderColorRole.border,
        background: background,
      );
      final next = (i + 1) % 4;
      canvas.save();
      canvas.clipRRect(outer);
      canvas.clipPath(
        Path()..addPolygon([
          corners[i],
          corners[next],
          inside[next],
          center,
          inside[i],
        ], true),
        doAntiAlias: false,
      );
      final columns = box.decorationColumns;
      if (i == 2 && columns != null) {
        final start = g.borderLeft + g.paddingLeft;
        canvas.clipPath(
          Path()
            ..addRect(
              Rect.fromLTRB(
                0,
                0,
                start + g.contentWidth * columns.leadingFraction,
                size.height,
              ),
            )
            ..addRect(
              Rect.fromLTRB(
                start + g.contentWidth * (1 - columns.trailingFraction),
                0,
                size.width,
                size.height,
              ),
            ),
        );
      }
      void band(double from, double to, Color ink) {
        canvas.drawPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRRect(shape(from))
            ..addRRect(shape(to)),
          Paint()..color = ink,
        );
      }

      switch (type) {
        case BoxBorderStyle.doubleLine:
          band(0, 1 / 3, color);
          band(2 / 3, 1, color);
        case BoxBorderStyle.ridge:
        case BoxBorderStyle.groove:
          final light = Color.lerp(
            color,
            Colors.white.withValues(alpha: color.a),
            .35,
          )!;
          final dark = Color.lerp(
            color,
            Colors.black.withValues(alpha: color.a),
            .35,
          )!;
          final raised = type == BoxBorderStyle.ridge;
          final lightOuter = raised == (i == 0 || i == 3);
          band(0, .5, lightOuter ? light : dark);
          band(.5, 1, lightOuter ? dark : light);
        case BoxBorderStyle.dashed:
        case BoxBorderStyle.dotted:
          // Follow the rounded perimeter, clipped to this side's corner joins.
          final paint = Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = width;
          if (type == BoxBorderStyle.dotted) {
            paint.strokeCap = StrokeCap.round;
          }
          final step = width * (type == BoxBorderStyle.dotted ? 1 : 4);
          for (final metric in (Path()..addRRect(shape(.5))).computeMetrics()) {
            for (var d = 0.0; d < metric.length; d += step * 2) {
              canvas.drawPath(
                metric.extractPath(d, math.min(d + step, metric.length)),
                paint,
              );
            }
          }
        case BoxBorderStyle.solid:
          band(0, 1, color);
        case BoxBorderStyle.none:
          break;
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ReaderBoxPainter old) =>
      old.box != box ||
      old.top != top ||
      old.bottom != bottom ||
      old.colors.paper != colors.paper ||
      old.colors.ink != colors.ink ||
      old.geometry != geometry;
}
