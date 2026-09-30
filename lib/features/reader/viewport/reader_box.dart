import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../domain/models/models.dart';
import '../reader_authored_colors.dart';
import 'block_style.dart';
import '../reader_inline_images.dart';

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
  final padding = EdgeInsets.fromLTRB(
    left,
    length(decoration.padding.top),
    right,
    length(decoration.padding.bottom),
  );
  final style = readerBlockStyle(block, base, chapter: chapter);
  final painter = TextPainter(
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
  )..layout(maxWidth: math.max(1.0, width - padding.horizontal));
  try {
    final w = math.min(width, painter.width + padding.horizontal),
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
    double em,
    double pageHeight, {
    double? minimumContentHeight,
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
    final free = math.max(0.0, available - width - ml - mr);
    if (box.centered || box.autoLeft && box.autoRight) {
      ml += free / 2;
      mr += free / 2;
    } else if (box.autoLeft) {
      ml += free;
    }
    marginLeft = ml;
    marginRight = mr;
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
      contentWidth;
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
  final outer = readerBoxGeometry(
    block.box,
    block,
    available,
    style,
    scaler,
    pageHeight: edgeHeight,
    minimumContentHeight: contentHeight,
  );
  final local = readerBoxGeometry(
    block.layout,
    block,
    outer?.contentWidth ?? available,
    style,
    scaler,
    pageHeight: edgeHeight,
    minimumContentHeight: contentHeight,
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
      box != null &&
          (index == 0 || content.blocks[index - 1].box?.group != box.group)
      ? boxes.outer!.top
      : 0.0;
  final outerBottom =
      box != null &&
          (index + 1 == content.blocks.length ||
              content.blocks[index + 1].box?.group != box.group)
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
  });
  final BlockBox? box;
  final double width, top, bottom;
  final Widget child;
  final ReaderBoxGeometry? geometry;
  final bool? starts, ends;
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
            painter: ReaderBoxPainter(
              b,
              g,
              start,
              end,
              ReaderAuthoredColors(Theme.of(context)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                g.paddingLeft + g.borderLeft,
                math.max(0, top - mt),
                g.paddingRight + g.borderRight,
                math.max(0, bottom - mb),
              ),
              child: child,
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
    if (background != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = background);
    }
    void edge(Offset a, Offset b, double width, BoxBorderSide? side) {
      if (width <= 0) return;
      final type =
          side?.style ??
          (box.dashed ? BoxBorderStyle.dashed : BoxBorderStyle.solid);
      final paint = Paint()
        ..color = colors.resolve(
          Color(side?.color ?? box.borderColor ?? 0xff808080),
          ReaderColorRole.border,
          background: background,
        )
        ..strokeWidth = width;
      if (type == BoxBorderStyle.solid) {
        canvas.drawLine(a, b, paint);
        return;
      }
      final distance = (b - a).distance;
      if (distance <= 0) return;
      final step = width * (type == BoxBorderStyle.dotted ? 1 : 4);
      if (type == BoxBorderStyle.dotted) paint.strokeCap = StrokeCap.round;
      for (var d = 0.0; d < distance; d += step * 2) {
        canvas.drawLine(
          a + (b - a) * (d / distance),
          a + (b - a) * ((d + step).clamp(0, distance) / distance),
          paint,
        );
      }
    }

    final g = geometry;
    edge(
      Offset(g.borderLeft / 2, 0),
      Offset(g.borderLeft / 2, size.height),
      g.borderLeft,
      box.borders?.left,
    );
    edge(
      Offset(size.width - g.borderRight / 2, 0),
      Offset(size.width - g.borderRight / 2, size.height),
      g.borderRight,
      box.borders?.right,
    );
    if (top) {
      edge(
        Offset(0, g.borderTop / 2),
        Offset(size.width, g.borderTop / 2),
        g.borderTop,
        box.borders?.top,
      );
    }
    if (bottom) {
      edge(
        Offset(0, size.height - g.borderBottom / 2),
        Offset(size.width, size.height - g.borderBottom / 2),
        g.borderBottom,
        box.borders?.bottom,
      );
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
