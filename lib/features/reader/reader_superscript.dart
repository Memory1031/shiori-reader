import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'reader_search_highlight.dart';
import 'reader_inline_border.dart';

/// A short source-preserving run. Measurement and paint share the raised baseline.
final class ReaderSuperscriptLayout {
  ReaderSuperscriptLayout({
    required this.span,
    required this.scaler,
    required this.direction,
    this.locale,
  });
  final TextSpan span;
  String get text => span.text!;
  TextStyle get style => span.style!;
  final TextScaler scaler;
  final TextDirection direction;
  final Locale? locale;
  double get rise => scaler.scale(style.fontSize ?? 20) * .45;
  double get factor =>
      scaler.scale(style.fontSize ?? 20) / (style.fontSize ?? 20);
  T _withPainter<T>(T Function(TextPainter) use) {
    final p = TextPainter(
      text: span,
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
    )..layout();
    try {
      return use(p);
    } finally {
      p.dispose();
    }
  }

  late final metrics = _withPainter(
    (p) => (
      size: Size(p.width, p.height + rise),
      baseline:
          p.computeDistanceToActualBaseline(TextBaseline.alphabetic) + rise,
    ),
  );
  List<Rect> selectedBoxes(ReaderGlyphHighlight? highlight, int start) =>
      _withPainter(
        (p) => readerGlyphBoxes(p, Offset.zero, highlight, text, start),
      );
  void paint(Canvas canvas, ReaderGlyphHighlight? highlight, int start) =>
      _withPainter((p) {
        paintReaderGlyphRange(canvas, p, Offset.zero, highlight, text, start);
        p.paint(canvas, Offset.zero);
        paintReaderPainterBorders(canvas, p, Offset.zero, scaler: scaler);
      });
}

class ReaderSuperscript extends LeafRenderObjectWidget {
  const ReaderSuperscript({
    super.key,
    required this.layout,
    required this.sourceStart,
    this.highlight,
  });
  final ReaderSuperscriptLayout layout;
  final int sourceStart;
  final ReaderGlyphHighlight? highlight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RaisedText(layout, sourceStart, highlight);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) => (renderObject as _RaisedText).update(layout, sourceStart, highlight);
}

class _RaisedText extends RenderBox {
  _RaisedText(this.raisedLayout, this.sourceStart, this.highlight);
  ReaderSuperscriptLayout raisedLayout;
  int sourceStart;
  ReaderGlyphHighlight? highlight;
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

  void update(
    ReaderSuperscriptLayout next,
    int start,
    ReaderGlyphHighlight? mark,
  ) {
    if (attached && highlight?.active != mark?.active) {
      highlight?.active.removeListener(markNeedsPaint);
      mark?.active.addListener(markNeedsPaint);
    }
    raisedLayout = next;
    sourceStart = start;
    highlight = mark;
    markNeedsLayout();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(raisedLayout.metrics.size / raisedLayout.factor);
  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      raisedLayout.metrics.baseline / raisedLayout.factor;
  @override
  double computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => raisedLayout.metrics.baseline / raisedLayout.factor;
  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(1 / raisedLayout.factor);
    raisedLayout.paint(canvas, highlight, sourceStart);
    canvas.restore();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.label = raisedLayout.text;
    config.textDirection = raisedLayout.direction;
  }
}
