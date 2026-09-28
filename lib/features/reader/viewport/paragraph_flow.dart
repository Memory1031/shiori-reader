import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../domain/models/models.dart';
import '../reader_inline_images.dart';
import 'block_style.dart';

bool readerUsesParagraphFlow(ContentBlock block, TextDirection direction) =>
    direction == TextDirection.ltr &&
    block is ParagraphBlock &&
    (block.hangingIndentEm != null || block.trailingLabelStart != null);

/// Transient source positions (code points) and shared measurement/paint boxes.
final class ParagraphFlowPiece {
  const ParagraphFlowPiece(
    this.start,
    this.end,
    this.rect,
    this.width, {
    this.label = false,
  });
  final int start, end;
  final Rect rect;
  final double width;
  final bool label;
}

final class ParagraphFlowLine {
  ParagraphFlowLine(
    this.start,
    this.end,
    this.top,
    this.height,
    List<ParagraphFlowPiece> pieces,
  ) : pieces = List.unmodifiable(pieces);
  final int start, end;
  final double top, height;
  final List<ParagraphFlowPiece> pieces;
}

final class ParagraphFlow {
  ParagraphFlow(List<ParagraphFlowLine> lines)
    : lines = List.unmodifiable(lines);
  final List<ParagraphFlowLine> lines;
  double get height => lines.isEmpty ? 0 : lines.last.top + lines.last.height;
  int get end => lines.isEmpty ? 0 : lines.last.end;
  ParagraphFlow take(int count) => ParagraphFlow(lines.take(count).toList());
}

/// Bounded to the current render chunk. A first line is special only at source
/// offset zero, independent of page/column/chunk boundaries. No text is added.
ParagraphFlow readerParagraphFlow({
  required ParagraphBlock block,
  required String text,
  required int offset,
  required double width,
  required TextStyle style,
  required TextScaler scaler,
  ChapterKey? chapter,
  double maxHeight = double.infinity,
  Locale? locale,
  TextHeightBehavior? textHeightBehavior,
}) {
  final runes = text.runes.toList();
  String slice(int start, int end) =>
      String.fromCharCodes(runes.sublist(start, end));
  final em = scaler.scale(style.fontSize ?? 20);
  // Preserve the author value when at least four em remain; shrink only the
  // inset in constrained columns. Never shrink the user's body font.
  final inset = math.min(
    (block.hangingIndentEm ?? 0) * em,
    math.max(0.0, width - em * 4),
  );
  // Keep the existing indentation policy (including authored whitespace and
  // narrow-width limits), but express its measured width as source-free geometry.
  final prefix = readerIndentPrefix(
    block,
    offset == 0,
    width,
    style,
    scaler,
    chapter: chapter,
  );
  var firstInset = 0.0;
  if (prefix.isNotEmpty) {
    final indent = TextPainter(
      text: TextSpan(text: prefix, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      locale: locale,
    )..layout(maxWidth: width);
    firstInset = indent.width.clamp(0.0, math.max(0.0, width - 1));
    indent.dispose();
  }
  final label = block.trailingLabelStart;
  final bodyEnd = label == null
      ? runes.length
      : (label - offset).clamp(0, runes.length);
  TextPainter painter(int start, int end, double available) {
    var source = slice(start, end);
    // Newline belongs to the source range but does not add an empty painted row.
    if (source.endsWith('\n')) source = source.substring(0, source.length - 1);
    return TextPainter(
        text: TextSpan(
          style: style,
          children: readerInlineSpans(
            text: source,
            offset: offset + start,
            images: block.inlineImages,
            ruby: block.inlineRuby,
            styles: block.inlineStyles,
            style: style,
            scaler: scaler,
            maxWidth: available,
            locale: locale,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        locale: locale,
        textHeightBehavior: textHeightBehavior,
      )
      ..setPlaceholderDimensions(
        readerInlineDimensions(
          offset: offset + start,
          length: source.runes.length,
          images: block.inlineImages,
          ruby: block.inlineRuby,
          text: source,
          styles: block.inlineStyles,
          style: style,
          scaler: scaler,
          maxWidth: available,
          locale: locale,
        ),
      )
      ..layout(maxWidth: available);
  }

  ({int end, double height, double width, double baseline}) measure(
    int start,
    int end,
    double available,
  ) {
    final p = painter(start, end, available);
    int stop = end;
    try {
      final metrics = p.computeLineMetrics();
      if (metrics.length > 1) {
        final second = metrics[1];
        final point = p.getPositionForOffset(
          Offset(0, second.baseline - second.ascent / 2),
        );
        final boundary = readerInlineSourceBoundary(
          slice(start, end),
          offset + start,
          block.inlineRuby,
          p.getLineBoundary(point).start,
        );
        var safe = 0;
        for (final cluster in slice(start, end).characters) {
          if (safe + cluster.length > boundary) break;
          safe += cluster.length;
        }
        stop = start + slice(start, end).substring(0, safe).runes.length;
      }
    } finally {
      p.dispose();
    }
    if (stop <= start) {
      final ruby = block.inlineRuby
          .where((r) => r.start == offset + start)
          .firstOrNull;
      stop =
          start +
          (ruby?.length ?? slice(start, end).characters.first.runes.length);
    }
    final line = painter(start, stop, available);
    try {
      final metrics = line.computeLineMetrics();
      return (
        end: stop,
        height: line.height,
        width: metrics.isEmpty ? 0 : metrics.first.width,
        baseline: metrics.isEmpty ? line.height : metrics.first.baseline,
      );
    } finally {
      line.dispose();
    }
  }

  final lines = <ParagraphFlowLine>[];
  var cursor = 0;
  var top = 0.0;
  var lastBaseline = 0.0;
  while (cursor < bodyEnd) {
    if (top > maxHeight) return ParagraphFlow(lines);
    final x = offset + cursor == 0 ? firstInset : inset;
    final available = math.max(1.0, width - x);
    final m = measure(cursor, bodyEnd, available);
    lines.add(
      ParagraphFlowLine(cursor, m.end, top, m.height, [
        ParagraphFlowPiece(
          cursor,
          m.end,
          Rect.fromLTWH(x, top, m.width, m.height),
          available,
        ),
      ]),
    );
    cursor = m.end;
    top += m.height;
    lastBaseline = m.baseline;
  }
  while (cursor < runes.length) {
    if (top > maxHeight) return ParagraphFlow(lines);
    final m = measure(cursor, runes.length, width);
    final previous = lines.lastOrNull;
    final sameLine =
        cursor == bodyEnd &&
        previous != null &&
        m.end == runes.length &&
        !slice(previous.start, previous.end).endsWith('\n') &&
        previous.pieces.last.rect.right + em * .25 <= width - m.width;
    if (sameLine) {
      lines.removeLast();
      final baseline = math.max(lastBaseline, m.baseline);
      final h = math.max(
        previous.height + baseline - lastBaseline,
        m.height + baseline - m.baseline,
      );
      lines.add(
        ParagraphFlowLine(previous.start, m.end, previous.top, h, [
          for (final piece in previous.pieces)
            ParagraphFlowPiece(
              piece.start,
              piece.end,
              piece.rect.translate(0, baseline - lastBaseline),
              piece.width,
            ),
          ParagraphFlowPiece(
            cursor,
            m.end,
            Rect.fromLTWH(
              width - m.width,
              previous.top + baseline - m.baseline,
              m.width,
              m.height,
            ),
            m.width + .001,
            label: true,
          ),
        ]),
      );
      top = previous.top + h;
    } else {
      lines.add(
        ParagraphFlowLine(cursor, m.end, top, m.height, [
          ParagraphFlowPiece(
            cursor,
            m.end,
            Rect.fromLTWH(width - m.width, top, m.width, m.height),
            m.width + .001,
            label: true,
          ),
        ]),
      );
      top += m.height;
    }
    cursor = m.end;
  }
  return ParagraphFlow(lines);
}
