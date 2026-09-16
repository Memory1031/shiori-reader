import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import 'render_chunk.dart';
import '../position/position_resolver.dart';
import 'block_style.dart';
import '../reader_inline_images.dart';

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
    this.locale,
    this.textHeightBehavior,
    this.paragraphSpacing = 16,
  }) {
    if (width < 1 || height < 1) {
      throw ArgumentError('Page needs positive dimensions');
    }
  }
  final ChunkIndex index;
  final double width;
  final double height;
  final TextStyle style;
  final double paragraphSpacing;
  final TextScaler scaler;
  final TextDirection direction;
  final Locale? locale;
  final TextHeightBehavior? textHeightBehavior;
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
    final desired =
        (readerCharacterOffset(resolved.fraction, chunk.total) - chunk.start)
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
    required int blockOffset,
  }) {
    if (text.isEmpty) return (text: '', count: 0, height: 16);
    measuredChunks++;
    final textWidth = readerBlockWidth(
      block,
      width,
      style,
      scaler,
      direction,
      chapter: index.content.key,
      locale: locale,
    );
    final prefix = readerIndentPrefix(
      block,
      startsBlock,
      textWidth,
      style,
      scaler,
      chapter: index.content.key,
    );
    final blockStyle = readerBlockStyle(
      block,
      style,
      chapter: index.content.key,
    );
    final painter =
        TextPainter(
            text: TextSpan(
              children: [
                TextSpan(text: prefix),
                ...readerInlineSpans(
                  text: text,
                  offset: blockOffset,
                  images: block.inlineImages,
                  style: blockStyle,
                ),
              ],
              style: blockStyle,
            ),
            textDirection: direction,
            locale: locale,
            textHeightBehavior: textHeightBehavior,
            textScaler: scaler,
            textAlign: readerBlockAlign(block, chapter: index.content.key),
          )
          ..setPlaceholderDimensions(
            readerInlineDimensions(
              offset: blockOffset,
              length: text.runes.length,
              images: block.inlineImages,
              style: blockStyle,
              scaler: scaler,
              maxWidth: textWidth,
            ),
          )
          ..layout(maxWidth: textWidth);
    try {
      final lines = painter.computeLineMetrics();
      var used = readerBlockSpacing(
        block,
        paragraphSpacing,
        chapter: index.content.key,
      );
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
          direction == TextDirection.ltr ? 0 : textWidth,
          boundaryLine.baseline - boundaryLine.ascent * .5,
        ),
      );
      var boundary = (painter.getLineBoundary(point).start - prefix.length)
          .clamp(0, text.length);
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
        final fullPageImage =
            index.content.blocks[chunk.blockIndex] is ImageBlock &&
            extent >= height * .6;
        if (extent > remaining + .01 || fullPageImage && fragments.isNotEmpty) {
          break;
        }
        fragments.add(PageFragment(cursor.unit, 0, 1, extent, text));
        remaining -= extent;
        cursor = PageCursor(cursor.unit + 1, 0);
        if (fullPageImage) break;
      } else {
        final rest = _slice(text, cursor.offset, text.runes.length);
        final block = index.content.blocks[chunk.blockIndex];
        // Bounded lookahead: keep a complete heading with the first two body
        // lines when that combination can fit on a fresh page.
        if (block is HeadingBlock &&
            cursor.offset == 0 &&
            fragments.isNotEmpty &&
            cursor.unit + 1 < index.chunks.length) {
          final heading = _fit(
            rest,
            height,
            backwards: false,
            block: block,
            startsBlock: chunk.start == 0,
            blockOffset: chunk.start + cursor.offset,
          );
          final next = index.chunks[cursor.unit + 1];
          final nextBlock = index.content.blocks[next.blockIndex];
          if (heading != null &&
              heading.count == rest.runes.length &&
              next.text?.isNotEmpty == true &&
              nextBlock is ParagraphBlock) {
            final firstLines =
                scaler.scale(style.fontSize ?? 18) * (style.height ?? 1.7) * 2 +
                readerBlockSpacing(
                  nextBlock,
                  paragraphSpacing,
                  chapter: index.content.key,
                );
            final required = heading.height + firstLines;
            if (required <= height && required > remaining) break;
          }
        }
        final fitted = _fit(
          rest,
          remaining,
          backwards: false,
          block: index.content.blocks[chunk.blockIndex],
          startsBlock: chunk.start == 0 && cursor.offset == 0,
          blockOffset: chunk.start + cursor.offset,
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
        final fullPageImage =
            index.content.blocks[chunk.blockIndex] is ImageBlock &&
            extent >= height * .6;
        if (extent > remaining + .01 || fullPageImage && fragments.isNotEmpty) {
          break;
        }
        fragments.add(PageFragment(cursor.unit, 0, 1, extent, text));
        remaining -= extent;
        cursor = PageCursor(cursor.unit, 0);
        if (fullPageImage) break;
      } else {
        final prefix = _slice(text, 0, cursor.offset);
        final fitted = _fit(
          prefix,
          remaining,
          backwards: true,
          block: index.content.blocks[chunk.blockIndex],
          startsBlock: chunk.start == 0,
          blockOffset: chunk.start,
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
