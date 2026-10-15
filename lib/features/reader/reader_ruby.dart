import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'reader_search_highlight.dart';

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

  List<Rect> selectedBoxes(ReaderGlyphHighlight? highlight, int sourceStart) =>
      _withPainters((body, note) {
        final fit = _fit(body, note);
        return readerGlyphBoxes(
              body,
              Offset(
                (math.max(body.width, note.width) - body.width) / 2,
                note.height,
              ),
              highlight,
              base.toPlainText(includeSemanticsLabels: false),
              sourceStart,
            )
            .map(
              (r) => Rect.fromLTRB(
                r.left * fit,
                r.top * fit,
                r.right * fit,
                r.bottom * fit,
              ),
            )
            .toList();
      });

  void paint(
    Canvas canvas, {
    ReaderGlyphHighlight? highlight,
    int sourceStart = 0,
  }) => _withPainters((body, note) {
    final width = math.max(body.width, note.width);
    canvas.save();
    canvas.scale(_fit(body, note));
    note.paint(canvas, Offset((width - note.width) / 2, 0));
    final at = Offset((width - body.width) / 2, note.height);
    body.paint(canvas, at);
    paintReaderGlyphRange(
      canvas,
      body,
      at,
      highlight,
      base.toPlainText(includeSemanticsLabels: false),
      sourceStart,
    );
    canvas.restore();
  });
}

class ReaderRuby extends StatelessWidget {
  const ReaderRuby({
    super.key,
    required this.layout,
    required this.baseText,
    this.highlight,
    this.sourceStart = 0,
  });
  final ReaderGlyphHighlight? highlight;
  final int sourceStart;
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
      child: _RubyPaint(
        layout: layout,
        factor: factor,
        highlight: highlight,
        sourceStart: sourceStart,
      ),
    );
  }
}

class _RubyPaint extends LeafRenderObjectWidget {
  const _RubyPaint({
    required this.layout,
    required this.factor,
    this.highlight,
    required this.sourceStart,
  });
  final ReaderGlyphHighlight? highlight;
  final int sourceStart;
  final ReaderRubyLayout layout;
  final double factor;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRuby(layout, factor, highlight, sourceStart);
  @override
  void updateRenderObject(BuildContext context, _RenderRuby renderObject) {
    renderObject.update(layout, factor, highlight, sourceStart);
  }
}

class _RenderRuby extends RenderBox {
  _RenderRuby(this.rubyLayout, this.factor, this.highlight, this.sourceStart);
  ReaderGlyphHighlight? highlight;
  int sourceStart;
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

  ReaderRubyLayout rubyLayout;
  double factor;
  void update(
    ReaderRubyLayout next,
    double scale,
    ReaderGlyphHighlight? mark,
    int source,
  ) {
    if (attached && highlight?.active != mark?.active) {
      highlight?.active.removeListener(markNeedsPaint);
      mark?.active.addListener(markNeedsPaint);
    }
    highlight = mark;
    sourceStart = source;
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
    rubyLayout.paint(canvas, highlight: highlight, sourceStart: sourceStart);
    canvas.restore();
  }
}
