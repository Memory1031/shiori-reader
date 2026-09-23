import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Identical glyph layout for pagination placeholders and the painted ruby.
/// The whole pair is one line-breaking unit; oversized pairs fit the line.
final class ReaderRubyLayout {
  ReaderRubyLayout({
    required this.base,
    required this.annotation,
    required this.style,
    required this.scaler,
    required this.direction,
    required this.maxWidth,
    this.locale,
  });
  final InlineSpan base;
  final String annotation;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;
  final double maxWidth;
  final Locale? locale;

  T _withPainters<T>(T Function(TextPainter, TextPainter) use) {
    final body = TextPainter(
      text: base,
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
    )..layout();
    final small = style.copyWith(
      fontSize: scaler.scale((style.fontSize ?? 20) * .5),
      height: 1,
      letterSpacing: 0,
    );
    final note = TextPainter(
      text: TextSpan(text: annotation, style: small),
      textDirection: direction,
      locale: locale,
    )..layout();
    try {
      return use(body, note);
    } finally {
      body.dispose();
      note.dispose();
    }
  }

  double _fit(TextPainter body, TextPainter note) =>
      math.min(1, maxWidth / math.max(body.width, note.width));

  late final ({Size size, double baseline}) metrics = _withPainters(
    (body, note) => (
      size:
          Size(math.max(body.width, note.width), body.height + note.height) *
          _fit(body, note),
      baseline:
          (note.height +
              body.computeDistanceToActualBaseline(TextBaseline.alphabetic)) *
          _fit(body, note),
    ),
  );

  void paint(Canvas canvas) => _withPainters((body, note) {
    final width = math.max(body.width, note.width);
    canvas.save();
    canvas.scale(_fit(body, note));
    note.paint(canvas, Offset((width - note.width) / 2, 0));
    body.paint(canvas, Offset((width - body.width) / 2, note.height));
    canvas.restore();
  });
}

class ReaderRuby extends StatelessWidget {
  const ReaderRuby({super.key, required this.layout, required this.baseText});
  final ReaderRubyLayout layout;
  final String baseText;
  @override
  Widget build(BuildContext context) {
    // WidgetSpan applies this scale itself. Undo it inside the child so both
    // nonlinear text scaling and the pagination placeholder use logical pixels.
    final font = layout.style.fontSize ?? 20;
    final factor = layout.scaler.scale(font) / font;
    return Semantics(
      label: '$baseText（${layout.annotation}）',
      child: _RubyPaint(layout: layout, factor: factor),
    );
  }
}

class _RubyPaint extends LeafRenderObjectWidget {
  const _RubyPaint({required this.layout, required this.factor});
  final ReaderRubyLayout layout;
  final double factor;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRuby(layout, factor);
  @override
  void updateRenderObject(BuildContext context, _RenderRuby renderObject) {
    renderObject.update(layout, factor);
  }
}

class _RenderRuby extends RenderBox {
  _RenderRuby(this.rubyLayout, this.factor);
  ReaderRubyLayout rubyLayout;
  double factor;
  void update(ReaderRubyLayout next, double scale) {
    rubyLayout = next;
    factor = scale;
    markNeedsLayout();
    markNeedsPaint();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(rubyLayout.metrics.size / factor);
  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      rubyLayout.metrics.baseline / factor;
  @override
  double computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => rubyLayout.metrics.baseline / factor;
  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(1 / factor);
    rubyLayout.paint(canvas);
    canvas.restore();
  }
}
