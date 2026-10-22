import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'reader_search_highlight.dart';
import 'reader_inline_border.dart';

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
  List<Rect> selectedBoxes(
    ReaderGlyphHighlight? highlight,
    int sourceStart,
    int separator,
  ) => _withPainters(
    (a, b) => [
      ...readerGlyphBoxes(
        a,
        geometry.upper.topLeft,
        highlight,
        upperText,
        sourceStart,
      ),
      ...readerGlyphBoxes(
        b,
        geometry.lower.topLeft,
        highlight,
        lowerText,
        separator + 1,
      ),
    ],
  );

  void paint(
    Canvas canvas, {
    ReaderGlyphHighlight? highlight,
    int sourceStart = 0,
    int separator = 0,
  }) => _withPainters((a, b) {
    paintReaderGlyphRange(
      canvas,
      a,
      geometry.upper.topLeft,
      highlight,
      upperText,
      sourceStart,
    );
    paintReaderGlyphRange(
      canvas,
      b,
      geometry.lower.topLeft,
      highlight,
      lowerText,
      separator + 1,
    );
    a.paint(canvas, geometry.upper.topLeft);
    b.paint(canvas, geometry.lower.topLeft);
    paintReaderPainterBorders(canvas, a, geometry.upper.topLeft);
    paintReaderPainterBorders(canvas, b, geometry.lower.topLeft);
  });
}

class ReaderInlineStack extends LeafRenderObjectWidget {
  const ReaderInlineStack({
    super.key,
    required this.layout,
    this.highlight,
    this.sourceStart = 0,
    this.separator = 0,
  });
  final ReaderGlyphHighlight? highlight;
  final int sourceStart, separator;
  final ReaderInlineStackLayout layout;
  double get factor {
    final font = layout.style.fontSize ?? 20;
    return layout.scaler.scale(font) / font;
  }

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderInlineStack(layout, factor, highlight, sourceStart, separator);
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderInlineStack).update(
        layout,
        factor,
        highlight,
        sourceStart,
        separator,
      );
}

class _RenderInlineStack extends RenderBox {
  _RenderInlineStack(
    this.stackLayout,
    this.factor,
    this.highlight,
    this.sourceStart,
    this.separator,
  );
  ReaderGlyphHighlight? highlight;
  int sourceStart, separator;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    highlight?.active.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    highlight?.active.removeListener(markNeedsPaint);
    super.detach();
  }

  ReaderInlineStackLayout stackLayout;
  double factor;
  void update(
    ReaderInlineStackLayout next,
    double f,
    ReaderGlyphHighlight? mark,
    int start,
    int split,
  ) {
    if (attached && highlight?.active != mark?.active) {
      highlight?.active.removeListener(markNeedsPaint);
      mark?.active.addListener(markNeedsPaint);
    }
    highlight = mark;
    sourceStart = start;
    separator = split;
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
    stackLayout.paint(
      c,
      highlight: highlight,
      sourceStart: sourceStart,
      separator: separator,
    );
    c.restore();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.label = '${stackLayout.upperText}\n${stackLayout.lowerText}';
    config.textDirection = stackLayout.direction;
  }
}
