import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../domain/models/models.dart';
import '../reader_inline_images.dart';
import 'block_style.dart';

bool readerUsesParagraphFlow(ContentBlock block, TextDirection direction) =>
    direction == TextDirection.ltr &&
    block is ParagraphBlock &&
    (block.hangingIndentEm != null ||
        block.trailingLabelStart != null ||
        block.tableRow != null);

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
  ParagraphFlow(
    List<ParagraphFlowLine> lines, {
    this.minimumHeight = 0,
    this.dividerX,
    this.dividerWidth = 0,
    this.dividerColor = 0xff000000,
  }) : lines = List.unmodifiable(lines);
  final List<ParagraphFlowLine> lines;

  /// A top-aligned cell must fit even when only a prefix of its neighbor fits.
  final double minimumHeight;
  final double? dividerX;
  final double dividerWidth;
  final int dividerColor;
  double heightThrough(ParagraphFlowLine line) =>
      math.max(minimumHeight, line.top + line.height);
  double get height => lines.isEmpty ? 0 : heightThrough(lines.last);
  int get end => lines.isEmpty ? 0 : lines.last.end;
  ParagraphFlow take(int count) => ParagraphFlow(
    lines.take(count).toList(),
    minimumHeight: minimumHeight,
    dividerX: dividerX,
    dividerWidth: dividerWidth,
    dividerColor: dividerColor,
  );
}

/// Bounded to the current render chunk. A first line is special only at source
/// offset zero, independent of page/column/chunk boundaries. No text is added.
ParagraphFlow readerParagraphFlow({
  required ParagraphBlock block,
  List<InlineStack> stacks = const [],
  required String text,
  required int offset,
  required double width,
  required TextStyle style,
  required TextScaler scaler,
  ChapterKey? chapter,
  double? tableLeftWidth,
  double? readerFontSize,
  double pageHeight = double.infinity,
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
            stacks: stacks,
            styles: block.inlineStyles,
            readerFontSize: readerFontSize,
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
          stacks: stacks,
          text: source,
          styles: block.inlineStyles,
          readerFontSize: readerFontSize,
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
          stacks: stacks,
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
      final stack = stacks.where((s) => s.start == offset + start).firstOrNull;
      final ruby = block.inlineRuby
          .where((r) => r.start == offset + start)
          .firstOrNull;
      stop =
          start +
          (stack?.length ??
              ruby?.length ??
              slice(start, end).characters.first.runes.length);
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

  if (block.tableRow case final row?) {
    final naturalLeft =
        tableLeftWidth ??
        readerTableLabelWidth(block, style, scaler, locale: locale);
    final divider = row.dividerWidth;
    final lp = row.leftPaddingEm * em, rp = row.rightPaddingEm * em;
    // Preserve a readable right column at very narrow widths. The label can
    // wrap within its capped cell; source offsets still appear exactly once.
    final left = math.max(
      1.0,
      math.min(
        math.max(row.leftWidthEm * em, naturalLeft),
        width - lp - rp - divider - em,
      ),
    );
    final dividerX = math.min(width - 1, left + lp);
    final rightX = math.min(width - 1, dividerX + divider + rp);
    final available = math.max(1.0, width - rightX);
    final lines = <ParagraphFlowLine>[];
    var cursor = (row.rightStart - offset).clamp(0, runes.length);
    var top = 0.0;
    TextPainter? labelPainter;
    if (offset < row.leftEnd) {
      labelPainter = painter(
        0,
        (row.leftEnd - offset).clamp(0, runes.length),
        left,
      );
    }
    final labelHeight = labelPainter?.height ?? 0.0;
    try {
      while (cursor < runes.length) {
        if (top > maxHeight) break;
        final m = measure(cursor, runes.length, available);
        final first = lines.isEmpty;
        final start = first ? 0 : cursor;
        final endsRow = offset + m.end == block.text.runes.length;
        // The right cell advances by its own line height. Only the fragment's
        // extent (and final gap) must also contain the independently laid-out label.
        final lastExtent = math.max(m.height, labelHeight - top);
        final h = endsRow
            ? lastExtent +
                  math.min(
                    row.gapAfterEm * em,
                    math.max(0.0, pageHeight - lastExtent),
                  )
            : m.height;
        lines.add(
          ParagraphFlowLine(start, m.end, top, h, [
            if (first && labelPainter != null)
              ParagraphFlowPiece(
                0,
                (row.leftEnd - offset).clamp(0, runes.length),
                Rect.fromLTWH(0, top, labelPainter.width, labelPainter.height),
                left,
              ),
            ParagraphFlowPiece(
              cursor,
              m.end,
              Rect.fromLTWH(rightX, top, m.width, m.height),
              available,
            ),
          ]),
        );
        top += m.height;
        cursor = m.end;
      }
    } finally {
      labelPainter?.dispose();
    }
    return ParagraphFlow(
      lines,
      minimumHeight: labelHeight,
      dividerX: dividerX,
      dividerWidth: divider,
      dividerColor: row.dividerColor,
    );
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

/// Measures only the short source label, never the right-hand prose.
double readerTableLabelWidth(
  ParagraphBlock block,
  TextStyle style,
  TextScaler scaler, {
  Locale? locale,
}) {
  final row = block.tableRow!;
  final label = String.fromCharCodes(block.text.runes.take(row.leftEnd));
  final painter = TextPainter(
    text: TextSpan(
      style: style,
      children: readerInlineSpans(
        text: label,
        offset: 0,
        images: const [],
        ruby: const [],
        styles: block.inlineStyles,
        style: style,
        scaler: scaler,
        maxWidth: double.infinity,
        locale: locale,
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    locale: locale,
  )..layout();
  try {
    return painter.width + .01;
  } finally {
    painter.dispose();
  }
}
