import 'dart:math' as math;
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

/// Bounds include the paragraph's existing leading, never new layout padding.
List<ReaderBorderStroke> readerBorderStrokes(
  InlineSpan text,
  TextScaler scaler,
  Size size,
  List<TextBox> Function(TextSelection) boxes,
) {
  final plain = text.toPlainText(includeSemanticsLabels: false);
  final all = boxes(TextSelection(baseOffset: 0, extentOffset: plain.length));
  final result = <ReaderBorderStroke>[];
  var offset = 0;
  void visit(InlineSpan span) {
    if (span is! TextSpan) {
      offset++;
      return;
    }
    final start = offset;
    offset += span.text?.length ?? 0;
    if (span is ReaderBorderSpan && offset > start) {
      final font = span.style?.fontSize ?? 20,
          em = scaler.scale(span.style?.fontSize ?? 20);
      final thickness = math
          .min(span.width * em / font * .6, em * .045)
          .clamp(.5, math.max(.5, em * .06))
          .toDouble();
      for (final box in boxes(
        TextSelection(baseOffset: start, extentOffset: offset),
      )) {
        final nextTop = all
            .where(
              (b) => b.top >= box.bottom - .01 && b.bottom > box.bottom + .01,
            )
            .fold<double>(size.height, (top, b) => math.min(top, b.top));
        final ceiling = nextTop < size.height
            ? nextTop - em * .03
            : size.height;
        final bottom = math.min(
          box.bottom + em * .08 + thickness,
          math.max(thickness, ceiling),
        );
        final left = box.left.clamp(0.0, size.width),
            right = box.right.clamp(0.0, size.width);
        if (right > left) {
          result.add((
            rect: Rect.fromLTRB(
              left,
              math.max(0.0, bottom - thickness),
              right,
              bottom,
            ),
            color: span.color,
            style: span.borderStyle,
          ));
        }
      }
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child);
    }
  }

  visit(text);
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
    painter.getBoxesForSelection,
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
        paragraph.getBoxesForSelection,
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
