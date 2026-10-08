import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A single shared pair of shaped rows. No scale-to-fit or internal wrapping:
/// the caller expands oversized units back to their untouched source text.
final class ReaderInlineStackLayout {
  ReaderInlineStackLayout({
    required this.upper,
    required this.lower,
    required this.upperText,
    required this.lowerText,
    required this.style,
    required this.scaler,
    required this.direction,
    this.locale,
  });
  final InlineSpan upper, lower;
  final String upperText, lowerText;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;
  final Locale? locale;
  T _withPainters<T>(T Function(TextPainter, TextPainter) use) {
    final a = TextPainter(
      text: upper,
      textDirection: direction,
      textScaler: TextScaler.noScaling,
      locale: locale,
    )..layout();
    final b = TextPainter(
      text: lower,
      textDirection: direction,
      textScaler: TextScaler.noScaling,
      locale: locale,
    )..layout();
    try {
      return use(a, b);
    } finally {
      a.dispose();
      b.dispose();
    }
  }

  late final geometry = _withPainters(
    (a, b) => (
      size: Size(math.max(a.width, b.width), a.height + b.height),
      baseline:
          a.height + b.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      upper: Rect.fromLTWH(
        (math.max(a.width, b.width) - a.width) / 2,
        0,
        a.width,
        a.height,
      ),
      lower: Rect.fromLTWH(
        (math.max(a.width, b.width) - b.width) / 2,
        a.height,
        b.width,
        b.height,
      ),
    ),
  );
  void paint(Canvas canvas) => _withPainters((a, b) {
    a.paint(canvas, geometry.upper.topLeft);
    b.paint(canvas, geometry.lower.topLeft);
  });
}

class ReaderInlineStack extends LeafRenderObjectWidget {
  const ReaderInlineStack({super.key, required this.layout});
  final ReaderInlineStackLayout layout;
  double get factor {
    final font = layout.style.fontSize ?? 20;
    return layout.scaler.scale(font) / font;
  }

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderInlineStack(layout, factor);
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderInlineStack).update(layout, factor);
}

class _RenderInlineStack extends RenderBox {
  _RenderInlineStack(this.stackLayout, this.factor);
  ReaderInlineStackLayout stackLayout;
  double factor;
  void update(ReaderInlineStackLayout next, double f) {
    stackLayout = next;
    factor = f;
    markNeedsLayout();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(stackLayout.geometry.size / factor);
  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      stackLayout.geometry.baseline / factor;
  @override
  double computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => stackLayout.geometry.baseline / factor;
  @override
  void paint(PaintingContext context, Offset offset) {
    final c = context.canvas;
    c.save();
    c.translate(offset.dx, offset.dy);
    c.scale(1 / factor);
    stackLayout.paint(c);
    c.restore();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.label = '${stackLayout.upperText}\n${stackLayout.lowerText}';
    config.textDirection = stackLayout.direction;
  }
}
