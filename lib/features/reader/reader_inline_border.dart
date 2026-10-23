import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../domain/models/models.dart';

/// Paint-only metadata: shaping and semantic text remain ordinary TextSpans.
class ReaderBorderSpan extends TextSpan {
  const ReaderBorderSpan({
    required super.text,
    required super.style,
    required this.borderStyle,
    required this.color,
    required this.width,
    super.recognizer,
    super.semanticsLabel,
  });
  final BoxBorderStyle borderStyle;
  final Color color;
  final double width;

  @override
  bool operator ==(Object other) =>
      other is ReaderBorderSpan &&
      super == other &&
      borderStyle == other.borderStyle &&
      color == other.color &&
      width == other.width;

  @override
  int get hashCode => Object.hash(super.hashCode, borderStyle, color, width);

  @override
  RenderComparison compareTo(InlineSpan other) {
    final comparison = super.compareTo(other);
    if (comparison.index < RenderComparison.paint.index &&
        other is ReaderBorderSpan &&
        (borderStyle != other.borderStyle ||
            color != other.color ||
            width != other.width)) {
      return RenderComparison.paint;
    }
    return comparison;
  }
}

TextSpan readerCopyTextSpan(
  TextSpan span, {
  TextStyle? style,
  String? semanticsLabel,
  GestureRecognizer? recognizer,
}) {
  if (span is ReaderBorderSpan) {
    return ReaderBorderSpan(
      text: span.text,
      style: style ?? span.style,
      borderStyle: span.borderStyle,
      color: span.color,
      width:
          span.width *
          (style?.fontSize ?? span.style?.fontSize ?? 20) /
          (span.style?.fontSize ?? 20),
      recognizer: recognizer ?? span.recognizer,
      semanticsLabel: semanticsLabel ?? span.semanticsLabel,
    );
  }
  return TextSpan(
    text: span.text,
    style: style ?? span.style,
    recognizer: recognizer ?? span.recognizer,
    semanticsLabel: semanticsLabel ?? span.semanticsLabel,
  );
}

typedef ReaderBorderStroke = ({Rect rect, Color color, BoxBorderStyle style});

typedef _BorderDecoration = ({
  Color color,
  BoxBorderStyle style,
  double thickness,
  double em,
});
typedef _BorderRange = ({int start, int end, _BorderDecoration decoration});
typedef _BorderLine = ({double top, double bottom});
const _geometryEpsilon = .01;

/// [boxes] uses max-height, tight-width boxes from the existing text layout.
List<ReaderBorderStroke> readerBorderStrokes(
  InlineSpan text,
  TextScaler scaler,
  Size size,
  List<TextBox> Function(TextSelection) boxes,
) {
  final ranges = <_BorderRange>[];
  var offset = 0;
  void visit(InlineSpan span) {
    if (span is! TextSpan) {
      offset++;
      return;
    }
    final start = offset;
    offset += span.text?.length ?? 0;
    if (span is ReaderBorderSpan && offset > start) {
      final font = span.style?.fontSize ?? 20;
      final em = scaler.scale(font);
      final decoration = (
        color: span.color,
        style: span.borderStyle,
        thickness: math
            .min(span.width * em / font * .6, em * .045)
            .clamp(.5, math.max(.5, em * .06))
            .toDouble(),
        em: em,
      );
      if (ranges.isNotEmpty &&
          ranges.last.end == start &&
          ranges.last.decoration == decoration) {
        ranges[ranges.length - 1] = (
          start: ranges.last.start,
          end: offset,
          decoration: decoration,
        );
      } else {
        ranges.add((start: start, end: offset, decoration: decoration));
      }
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child);
    }
  }

  visit(text);
  if (ranges.isEmpty) return const [];

  final all = [...boxes(TextSelection(baseOffset: 0, extentOffset: offset))]
    ..sort((a, b) {
      final top = a.top.compareTo(b.top);
      return top == 0 ? a.bottom.compareTo(b.bottom) : top;
    });
  final lines = <_BorderLine>[];
  for (final box in all) {
    if (lines.isEmpty ||
        (lines.last.top - box.top).abs() > _geometryEpsilon ||
        (lines.last.bottom - box.bottom).abs() > _geometryEpsilon) {
      lines.add((top: box.top, bottom: box.bottom));
    }
  }
  final nextTops = [
    for (var i = 0; i < lines.length; i++)
      i + 1 < lines.length
          ? math.min(size.height, lines[i + 1].top)
          : size.height,
  ];
  int lowerBound(double top) {
    var lo = 0, hi = lines.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (lines[mid].top < top) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int lineIndex(TextBox box) {
    var found = -1;
    for (
      var i = lowerBound(box.top - _geometryEpsilon);
      i < lines.length && lines[i].top <= box.top + _geometryEpsilon;
      i++
    ) {
      if ((lines[i].bottom - box.bottom).abs() <= _geometryEpsilon) {
        if (found != -1) return -1;
        found = i;
      }
    }
    return found;
  }

  final result = <ReaderBorderStroke>[];
  void emit(
    List<({double left, double right})> intervals,
    double lineBottom,
    double nextTop,
    _BorderDecoration decoration,
  ) {
    final em = decoration.em, thickness = decoration.thickness;
    final ceiling = nextTop < size.height ? nextTop - em * .03 : size.height;
    final bottom = math.min(
      lineBottom + em * .08 + thickness,
      math.max(thickness, ceiling),
    );
    for (final interval in intervals) {
      result.add((
        rect: Rect.fromLTRB(
          interval.left,
          math.max(0.0, bottom - thickness),
          interval.right,
          bottom,
        ),
        color: decoration.color,
        style: decoration.style,
      ));
    }
  }

  for (final range in ranges) {
    final groups =
        <(int, TextDirection), List<({double left, double right})>>{};
    for (final box in boxes(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    )) {
      final left = box.left.clamp(0.0, size.width);
      final right = box.right.clamp(0.0, size.width);
      if (right <= left) continue;
      final index = lineIndex(box);
      final interval = (left: left, right: right);
      if (index < 0) {
        // Uncertain row identity must not connect otherwise unrelated boxes.
        final next = lowerBound(box.bottom - _geometryEpsilon);
        emit(
          [interval],
          box.bottom,
          next < lines.length
              ? math.min(size.height, lines[next].top)
              : size.height,
          range.decoration,
        );
      } else {
        (groups[(index, box.direction)] ??= []).add(interval);
      }
    }
    for (final entry in groups.entries) {
      final intervals = entry.value..sort((a, b) => a.left.compareTo(b.left));
      final merged = <({double left, double right})>[];
      for (final interval in intervals) {
        if (merged.isNotEmpty &&
            interval.left <= merged.last.right + _geometryEpsilon) {
          merged[merged.length - 1] = (
            left: merged.last.left,
            right: math.max(merged.last.right, interval.right),
          );
        } else {
          merged.add(interval);
        }
      }
      emit(
        merged,
        lines[entry.key.$1].bottom,
        nextTops[entry.key.$1],
        range.decoration,
      );
    }
  }
  return result;
}

void paintReaderBorders(
  Canvas canvas,
  Iterable<ReaderBorderStroke> strokes,
  Offset at,
) {
  for (final stroke in strokes) {
    final rect = stroke.rect.shift(at), width = stroke.rect.height;
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = width;
    final y = rect.center.dy;
    switch (stroke.style) {
      case BoxBorderStyle.dotted:
        for (
          var x = rect.left + width / 2;
          x <= rect.right - width / 2;
          x += width * 2.8
        ) {
          canvas.drawCircle(Offset(x, y), width / 2, paint);
        }
      case BoxBorderStyle.dashed:
        for (var x = rect.left; x < rect.right; x += width * 5) {
          canvas.drawLine(
            Offset(x, y),
            Offset(math.min(x + width * 3, rect.right), y),
            paint,
          );
        }
      default:
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
  }
}

void paintReaderPainterBorders(
  Canvas canvas,
  TextPainter painter,
  Offset at, {
  TextScaler scaler = TextScaler.noScaling,
}) => paintReaderBorders(
  canvas,
  readerBorderStrokes(
    painter.text!,
    scaler,
    painter.size,
    (selection) => painter.getBoxesForSelection(
      selection,
      boxHeightStyle: ui.BoxHeightStyle.max,
      boxWidthStyle: ui.BoxWidthStyle.tight,
    ),
  ),
  at,
);

class ReaderPaintedInlineBorders extends SingleChildRenderObjectWidget {
  const ReaderPaintedInlineBorders({
    super.key,
    required super.child,
    required this.scaler,
  });
  final TextScaler scaler;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      ReaderInlineBorderRender(scaler);
  @override
  void updateRenderObject(
    BuildContext context,
    ReaderInlineBorderRender renderObject,
  ) {
    renderObject.scaler = scaler;
    renderObject.markNeedsPaint();
  }
}

class ReaderInlineBorderRender extends RenderProxyBox {
  ReaderInlineBorderRender(this.scaler);
  TextScaler scaler;
  RenderParagraph? _paragraph(RenderObject object) {
    if (object is RenderParagraph) return object;
    RenderParagraph? found;
    object.visitChildren((child) {
      found ??= _paragraph(child);
    });
    return found;
  }

  List<ReaderBorderStroke> get strokes {
    final paragraph = child == null ? null : _paragraph(child!);
    if (paragraph == null) return const [];
    final transform = paragraph.getTransformTo(this);
    return [
      for (final stroke in readerBorderStrokes(
        paragraph.text,
        scaler,
        paragraph.size,
        (selection) => paragraph.getBoxesForSelection(
          selection,
          boxHeightStyle: ui.BoxHeightStyle.max,
          boxWidthStyle: ui.BoxWidthStyle.tight,
        ),
      ))
        (
          rect: MatrixUtils.transformRect(transform, stroke.rect),
          color: stroke.color,
          style: stroke.style,
        ),
    ];
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    paintReaderBorders(context.canvas, strokes, offset);
  }
}
