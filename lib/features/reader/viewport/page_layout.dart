import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import 'render_chunk.dart';
import 'block_style.dart';

/// A cursor in transient chunks; exposed/persisted positions always use Domain.
final class PageCursor {
  const PageCursor(this.unit, this.offset);
  final int unit;
  final int offset;
}

final class PageFragment {
  const PageFragment(this.unit, this.start, this.end, this.height, this.text);
  final int unit;
  final int start;
  final int end;
  final double height;
  final String? text;
}

final class ReaderPage {
  ReaderPage(this.start, this.end, List<PageFragment> fragments)
    : fragments = List.unmodifiable(fragments);
  final PageCursor start;
  final PageCursor end;
  final List<PageFragment> fragments;
}

/// Only lays out bounded chunks around a requested semantic anchor. It does not
/// calculate a global page count or paginate the unseen chapter prefix.
final class PageLayout {
  PageLayout({
    required this.index,
    required this.width,
    required this.height,
    required this.style,
    required this.scaler,
    required this.direction,
    this.imageHeights = const {},
    this.imageExtent,
  }) {
    if (width < 1 || height < 1) {
      throw ArgumentError('Page needs positive dimensions');
    }
  }
  final ChunkIndex index;
  final double width;
  final double height;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;
  final Map<MediaRef, double> imageHeights;
  final double Function(ImageBlock)? imageExtent;
  int measuredChunks = 0;
  int _length(int unit) =>
      (index.chunks[unit].text?.runes.length ?? 1).clamp(1, 1000000000);
  PageCursor normalize(PageCursor cursor) {
    var unit = cursor.unit;
    var offset = cursor.offset;
    while (unit < index.chunks.length && offset >= _length(unit)) {
      offset -= _length(unit);
      unit++;
    }
    return PageCursor(unit, offset);
  }

  PageCursor cursor(ReaderPosition? position) {
    final resolved = index.resolve(position);
    final chunk = index.chunks[resolved.chunk];
    if (chunk.text == null) return PageCursor(resolved.chunk, 0);
    final desired = ((resolved.fraction * chunk.total).floor() - chunk.start)
        .clamp(0, (chunk.end - chunk.start - 1).clamp(0, chunk.total));
    var offset = 0;
    for (final grapheme in chunk.text!.characters) {
      final next = offset + grapheme.runes.length;
      if (next > desired) break;
      offset = next;
    }
    return normalize(PageCursor(resolved.chunk, offset));
  }

  ReaderPosition position(PageCursor cursor) {
    if (cursor.unit >= index.chunks.length) {
      return index.position(index.chunks.length - 1, 1);
    }
    final chunk = index.chunks[cursor.unit];
    return index.position(
      cursor.unit,
      chunk.total == 0 ? 0 : (chunk.start + cursor.offset) / chunk.total,
    );
  }

  String _slice(String text, int start, int end) =>
      String.fromCharCodes(text.runes.skip(start).take(end - start));
  ({String text, int count, double height})? _fit(
    String text,
    double available, {
    required bool backwards,
    required ContentBlock block,
    required bool startsBlock,
  }) {
    if (text.isEmpty) return (text: '', count: 0, height: 16);
    measuredChunks++;
    final painter =
        TextPainter(
          text: TextSpan(text: text, style: readerBlockStyle(block, style)),
          textDirection: direction,
          textScaler: scaler,
          textAlign: readerBlockAlign(block),
        )..layout(
          maxWidth:
              width -
              readerBlockIndent(block, style, scaler, width, startsBlock),
        );
    try {
      final lines = painter.computeLineMetrics();
      var used = 16.0;
      var count = 0;
      for (final line in backwards ? lines.reversed : lines) {
        if (used + line.height > available + .01) break;
        used += line.height;
        count++;
      }
      if (count == 0) return null;
      if (count == lines.length) {
        return (text: text, count: text.runes.length, height: used);
      }
      final boundaryLine = backwards
          ? lines[lines.length - count]
          : lines[count];
      final point = painter.getPositionForOffset(
        Offset(
          direction == TextDirection.ltr ? 0 : width,
          boundaryLine.baseline - boundaryLine.ascent * .5,
        ),
      );
      var boundary = painter.getLineBoundary(point).start;
      // A Flutter line break is normally grapheme-safe; snap defensively.
      var safe = 0;
      for (final grapheme in text.characters) {
        if (safe + grapheme.length > boundary) break;
        safe += grapheme.length;
      }
      boundary = safe;
      final selected = backwards
          ? text.substring(boundary)
          : text.substring(0, boundary);
      if (selected.isEmpty) return null;
      return (text: selected, count: selected.runes.length, height: used);
    } finally {
      painter.dispose();
    }
  }

  double _objectHeight(int unit) {
    final block = index.content.blocks[index.chunks[unit].blockIndex];
    if (block is ImageBlock) {
      final known =
          imageExtent?.call(block) ??
          imageHeights[block.media] ??
          (block.width != null && block.height != null
              ? width * block.height! / block.width!
              : 180.0);
      return known.clamp(1.0, height);
    }
    return (block is ParagraphBlock ? 16.0 : 24.0).clamp(1.0, height);
  }

  ReaderPage? forward(PageCursor from) {
    final start = normalize(from);
    var cursor = start;
    var remaining = height;
    final fragments = <PageFragment>[];
    while (cursor.unit < index.chunks.length) {
      final chunk = index.chunks[cursor.unit];
      final text = chunk.text;
      if (text == null || text.isEmpty) {
        final extent = _objectHeight(cursor.unit);
        if (extent > remaining + .01) break;
        fragments.add(PageFragment(cursor.unit, 0, 1, extent, text));
        remaining -= extent;
        cursor = PageCursor(cursor.unit + 1, 0);
      } else {
        final rest = _slice(text, cursor.offset, text.runes.length);
        final fitted = _fit(
          rest,
          remaining,
          backwards: false,
          block: index.content.blocks[chunk.blockIndex],
          startsBlock: chunk.start == 0,
        );
        if (fitted == null) break;
        fragments.add(
          PageFragment(
            cursor.unit,
            cursor.offset,
            cursor.offset + fitted.count,
            fitted.height,
            fitted.text,
          ),
        );
        remaining -= fitted.height;
        cursor = normalize(
          PageCursor(cursor.unit, cursor.offset + fitted.count),
        );
      }
    }
    return fragments.isEmpty ? null : ReaderPage(start, cursor, fragments);
  }

  ReaderPage? backward(PageCursor until) {
    var cursor = normalize(until);
    final end = cursor;
    var remaining = height;
    final fragments = <PageFragment>[];
    while (cursor.unit > 0 || cursor.offset > 0) {
      if (cursor.offset == 0) {
        cursor = PageCursor(cursor.unit - 1, _length(cursor.unit - 1));
      }
      final chunk = index.chunks[cursor.unit];
      final text = chunk.text;
      if (text == null || text.isEmpty) {
        final extent = _objectHeight(cursor.unit);
        if (extent > remaining + .01) break;
        fragments.add(PageFragment(cursor.unit, 0, 1, extent, text));
        remaining -= extent;
        cursor = PageCursor(cursor.unit, 0);
      } else {
        final prefix = _slice(text, 0, cursor.offset);
        final fitted = _fit(
          prefix,
          remaining,
          backwards: true,
          block: index.content.blocks[chunk.blockIndex],
          startsBlock: chunk.start == 0,
        );
        if (fitted == null) break;
        final start = cursor.offset - fitted.count;
        fragments.add(
          PageFragment(
            cursor.unit,
            start,
            cursor.offset,
            fitted.height,
            fitted.text,
          ),
        );
        remaining -= fitted.height;
        cursor = PageCursor(cursor.unit, start);
      }
    }
    return fragments.isEmpty
        ? null
        : ReaderPage(
            PageCursor(fragments.last.unit, fragments.last.start),
            end,
            fragments.reversed.toList(),
          );
  }
}
