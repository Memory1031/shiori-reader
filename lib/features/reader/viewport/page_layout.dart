import 'dart:math' as math;
import 'paragraph_flow.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import 'render_chunk.dart';
import '../position/position_resolver.dart';
import 'block_style.dart';
import 'reader_box.dart';
import '../reader_inline_images.dart';

/// A cursor in transient chunks; exposed/persisted positions always use Domain.
final class PageCursor {
  const PageCursor(this.unit, this.offset);
  final int unit;
  final int offset;
}

final class PageFragment {
  const PageFragment(
    this.unit,
    this.start,
    this.end,
    this.height,
    this.text, {
    this.flow,
    this.linkLayout,
    this.boxTop = 0,
    this.boxBottom = 0,
    this.boxContentHeight,
  });
  final int unit;
  final int start;
  final int end;
  final double height;
  final String? text;
  final double boxTop, boxBottom;

  /// Actual placeholder row reservation, shared with the painted box geometry.
  final double? boxContentHeight;
  final ParagraphFlow? flow;
  final ReaderLinkLayout? linkLayout;
}

final class ReaderPage {
  ReaderPage(
    this.start,
    this.end,
    List<PageFragment> fragments, {
    this.columnBreak,
    this.fullWidth = false,
    this.centered = false,
  }) : fragments = List.unmodifiable(fragments);
  final PageCursor start;
  final PageCursor end;
  final List<PageFragment> fragments;
  final int? columnBreak;
  final bool fullWidth;

  /// Standalone full-page images center vertically instead of hugging the top.
  final bool centered;
}

/// Forward layout measures bounded chunks without a global page count. Cold
/// reverse spread layout replays the prefix to recover canonical pairing;
/// the viewport normally reuses PageBoundaries from its incremental forward seek.
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
    this.columns = 1,
  }) {
    if (width < 1 || height < 1 || (columns != 1 && columns != 2)) {
      throw ArgumentError('Page needs positive dimensions');
    }
  }
  final ChunkIndex index;
  final double width;
  final double height;
  final TextStyle style;
  final double paragraphSpacing;
  final int columns;
  final TextScaler scaler;
  final TextDirection direction;
  final Locale? locale;
  final TextHeightBehavior? textHeightBehavior;
  final Map<MediaRef, double> imageHeights;
  final double Function(ImageBlock)? imageExtent;
  int measuredChunks = 0;
  late final Map<int, double> _tableWidths = () {
    final widths = <int, double>{};
    for (final block in index.content.blocks) {
      if (block is! ParagraphBlock || block.tableRow == null) continue;
      final group = block.tableRow!.group;
      final measured = readerTableLabelWidth(
        block,
        readerBlockStyle(block, style, chapter: index.content.key),
        scaler,
        locale: locale,
      );
      if (measured > (widths[group] ?? 0)) widths[group] = measured;
    }
    return widths;
  }();
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
    final block = index.content.blocks[chunk.blockIndex];
    for (final ruby in block.inlineRuby) {
      if (ruby.start < chunk.start + offset &&
          chunk.start + offset < ruby.end) {
        offset = ruby.start - chunk.start;
        break;
      }
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
  ({
    String text,
    int count,
    double height,
    double boxTop,
    double boxBottom,
    double? boxContentHeight,
    ParagraphFlow? flow,
    ReaderLinkLayout? linkLayout,
  })?
  _fit(
    String text,
    double available, {
    required bool backwards,
    required ContentBlock block,
    required bool startsBlock,
    required int blockOffset,
    required int blockIndex,
  }) {
    if (text.isEmpty) {
      return (
        text: '',
        count: 0,
        height: 16,
        boxTop: 0,
        boxBottom: 0,
        boxContentHeight: null,
        flow: null,
        linkLayout: null,
      );
    }
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
    if (block is ParagraphBlock &&
        block.linkDecoration != null &&
        blockOffset == 0 &&
        text.runes.length == block.text.runes.length) {
      final link = readerLinkLayout(
        block,
        textWidth,
        style,
        scaler,
        direction,
        locale: locale,
        heightBehavior: textHeightBehavior,
        chapter: index.content.key,
      )!;
      final edges = readerBoxEdges(
        index.content,
        blockIndex,
        width: width,
        style: style,
        scaler: scaler,
        pageHeight: height,
      );
      final spacing = readerBlockSpacing(
        block,
        paragraphSpacing,
        chapter: index.content.key,
        pageHeight: height,
      );
      final total = link.height + edges.top + edges.bottom + spacing;
      // Move an intact label to the next page; too-tall labels lose decoration
      // and use the ordinary source-preserving text pagination below.
      if (total <= height + .01) {
        if (total > available + .01) return null;
        return (
          text: text,
          count: text.runes.length,
          height: total,
          boxTop: edges.top,
          boxBottom: edges.bottom,
          boxContentHeight: null,
          flow: null,
          linkLayout: link,
        );
      }
    }
    final table = block is ParagraphBlock ? block.tableRow : null;
    final em = scaler.scale(style.fontSize ?? 20);
    final tableFits =
        table == null ||
        ((_tableWidths[table.group] ?? 0) > table.leftWidthEm * em
                    ? _tableWidths[table.group]!
                    : table.leftWidthEm * em) +
                (table.leftPaddingEm + table.rightPaddingEm) * em +
                table.dividerWidth <=
            textWidth - em;
    if (readerUsesParagraphFlow(block, direction) && tableFits) {
      final paragraph = block as ParagraphBlock;
      var edges = readerBoxEdges(
        index.content,
        blockIndex,
        width: width,
        style: style,
        scaler: scaler,
        pageHeight: height,
      );
      var top = startsBlock ? edges.top : 0.0;
      final spacing = readerBlockSpacing(
        block,
        paragraphSpacing,
        pageHeight: height,
        chapter: index.content.key,
      );
      ParagraphFlow measureFlow(double contentHeight) => readerParagraphFlow(
        block: paragraph,
        tableLeftWidth: paragraph.tableRow == null
            ? null
            : _tableWidths[paragraph.tableRow!.group],
        chapter: index.content.key,
        text: text,
        offset: blockOffset,
        maxHeight: available,
        pageHeight: contentHeight,
        width: textWidth,
        style: readerBlockStyle(block, style, chapter: index.content.key),
        readerFontSize: style.fontSize,
        scaler: scaler,
        locale: locale,
        textHeightBehavior: textHeightBehavior,
      );
      var flow = measureFlow(
        (height - top - edges.bottom - spacing).clamp(0.0, height),
      );
      double? boxContentHeight;
      if ((block.box != null || block.layout != null) &&
          (block.inlineImages.isNotEmpty || block.inlineRuby.isNotEmpty)) {
        boxContentHeight = flow.lines.fold<double>(
          flow.minimumHeight,
          (h, line) => math.max(h, line.height),
        );
        edges = readerBoxEdges(
          index.content,
          blockIndex,
          width: width,
          style: style,
          scaler: scaler,
          pageHeight: height,
          minimumContentHeight: boxContentHeight,
        );
        top = startsBlock ? edges.top : 0.0;
        flow = measureFlow(
          (height - top - edges.bottom - spacing).clamp(0.0, height),
        );
      }
      var count = 0;
      for (final line in flow.lines) {
        final bottom = blockOffset + line.end == paragraph.text.runes.length
            ? edges.bottom
            : 0.0;
        if (flow.heightThrough(line) + spacing + top + bottom >
            available + .01) {
          break;
        }
        count++;
      }
      if (count == 0) return null;
      final selected = flow.take(count);
      final bottom = blockOffset + selected.end == paragraph.text.runes.length
          ? edges.bottom
          : 0.0;
      return (
        text: _slice(text, 0, selected.end),
        count: selected.end,
        height: selected.height + spacing + top + bottom,
        boxTop: top,
        boxBottom: bottom,
        boxContentHeight: boxContentHeight,
        flow: selected,
        linkLayout: null,
      );
    }
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
                  ruby: block.inlineRuby,
                  scaler: scaler,
                  direction: direction,
                  locale: locale,
                  maxWidth: textWidth,
                  styles: block.inlineStyles,
                  style: blockStyle,
                  readerFontSize: style.fontSize,
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
              ruby: block.inlineRuby,
              text: text,
              direction: direction,
              locale: locale,
              styles: block.inlineStyles,
              style: blockStyle,
              readerFontSize: style.fontSize,
              scaler: scaler,
              maxWidth: textWidth,
            ),
          )
          ..layout(maxWidth: textWidth);
    try {
      final lines = painter.computeLineMetrics();
      double? boxContentHeight;
      if ((block.box != null || block.layout != null) &&
          (block.inlineImages.isNotEmpty || block.inlineRuby.isNotEmpty)) {
        // Placeholder-only rows can have paragraph leading beyond line metrics.
        // Reserve the measured tallest row and that leading, not just font size.
        final rowHeight = lines.fold<double>(
          0,
          (h, line) => math.max(h, line.height),
        );
        final lineHeight = lines.fold<double>(0, (h, line) => h + line.height);
        boxContentHeight =
            rowHeight + math.max(0.0, painter.height - lineHeight);
      }
      final edges = readerBoxEdges(
        index.content,
        blockIndex,
        width: width,
        style: style,
        scaler: scaler,
        pageHeight: height,
        minimumContentHeight: boxContentHeight,
      );
      final blockLength = switch (block) {
        ParagraphBlock(:final text) ||
        HeadingBlock(:final text) => text.runes.length,
        _ => 0,
      };
      final top = startsBlock ? edges.top : 0.0;
      final bottom = blockOffset + text.runes.length == blockLength
          ? edges.bottom
          : 0.0;
      final spacing = readerBlockSpacing(
        block,
        paragraphSpacing,
        pageHeight: height,
        chapter: index.content.key,
      );
      // Placeholder-only lines can report shorter line metrics than their
      // paragraph: Flutter still reserves leading around the inline image.
      final fullHeight = painter.height + spacing + top + bottom;
      if (fullHeight <= available + .01) {
        return (
          text: text,
          count: text.runes.length,
          height: fullHeight,
          boxTop: top,
          boxBottom: bottom,
          boxContentHeight: boxContentHeight,
          flow: null,
          linkLayout: null,
        );
      }
      // A split box keeps only its outermost top/bottom edges, like CSS slice.
      final keptTop = backwards ? 0.0 : top;
      final keptBottom = backwards ? bottom : 0.0;
      var used = spacing + keptTop + keptBottom;
      var count = 0;
      for (final line in backwards ? lines.reversed : lines) {
        if (used + line.height > available + .01) break;
        used += line.height;
        count++;
      }
      if (count == 0) return null;
      if (count == lines.length) {
        // Text fits but the terminating box padding does not; move one line.
        count--;
        if (count == 0) return null;
        used -= (backwards ? lines.first : lines.last).height;
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
      var boundary = readerInlineSourceBoundary(
        text,
        blockOffset,
        block.inlineRuby,
        (painter.getLineBoundary(point).start - prefix.length).clamp(
          0,
          text.length,
        ),
      );
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
      if (block.inlineImages.isNotEmpty || block.inlineRuby.isNotEmpty) {
        // A new fragment has its own leading and placeholder baselines.
        // Measure the strictly shorter slice instead of summing line heights.
        if (selected.length >= text.length) return null;
        return _fit(
          selected,
          available,
          backwards: backwards,
          block: block,
          startsBlock: !backwards && startsBlock,
          blockOffset: backwards
              ? blockOffset + text.runes.length - selected.runes.length
              : blockOffset,
          blockIndex: blockIndex,
        );
      }
      return (
        text: selected,
        count: selected.runes.length,
        height: used,
        boxTop: keptTop,
        boxBottom: keptBottom,
        boxContentHeight: boxContentHeight,
        flow: null,
        linkLayout: null,
      );
    } finally {
      painter.dispose();
    }
  }

  double _objectHeight(int unit) {
    final at = index.chunks[unit].blockIndex, block = index.content.blocks[at];
    final edges = readerBoxEdges(
      index.content,
      at,
      width: width,
      style: style,
      scaler: scaler,
      pageHeight: height,
    );
    final inner = readerBoxInnerWidth(
      block,
      width,
      style: style,
      scaler: scaler,
    );
    final body = block is ImageBlock
        ? imageExtent?.call(block) ??
              imageHeights[block.media] ??
              (block.width != null && block.height != null
                  ? inner * block.height! / block.width!
                  : 180.0)
        : block is ParagraphBlock
        ? readerBlankHeight(block, style, scaler)
        : 24.0;
    return body.clamp(1, math.max(1.0, height - edges.top - edges.bottom)) +
        edges.top +
        edges.bottom;
  }

  /// A large illustration owns one column, not necessarily the whole spread.
  bool isIllustrationColumn(List<PageFragment> fragments) =>
      fragments.length == 1 &&
      index.content.blocks[index.chunks[fragments.single.unit].blockIndex]
          is ImageBlock &&
      index
              .content
              .blocks[index.chunks[fragments.single.unit].blockIndex]
              .box ==
          null &&
      index
              .content
              .blocks[index.chunks[fragments.single.unit].blockIndex]
              .layout ==
          null &&
      (fragments.single.height >= height * .6 ||
          index.content.blocks.length == 1);

  bool _fullPageImage(int blockIndex, double extent) =>
      index.content.blocks[blockIndex] is ImageBlock &&
      (extent >= height * .6 || index.content.blocks.length == 1);

  ReaderPage? forward(PageCursor from) {
    final first = _forwardColumn(from);
    if (first == null || columns == 1) return first;
    if (index.content.blocks.length == 1 &&
        index.content.blocks.single is ImageBlock &&
        index.content.blocks.single.box == null &&
        index.content.blocks.single.layout == null) {
      return ReaderPage(
        first.start,
        first.end,
        first.fragments,
        fullWidth: true,
        centered: true,
      );
    }
    final second = _forwardColumn(first.end);
    if (second == null) return first;
    return ReaderPage(first.start, second.end, [
      ...first.fragments,
      ...second.fragments,
    ], columnBreak: first.fragments.length);
  }

  ReaderPage? backward(PageCursor until) {
    if (columns == 1 &&
        !index.content.blocks.any(
          (b) =>
              b.box != null ||
              b.layout != null ||
              b is ParagraphBlock && b.linkDecoration != null ||
              readerUsesParagraphFlow(b, direction),
        )) {
      return _backwardColumn(until);
    }
    final end = normalize(until);
    if (end.unit == 0 && end.offset == 0) return null;
    // Packing from the end loses column parity (and text/heading boundaries).
    // A caller without known boundaries must recover the forward chain. No
    // rendered pages or persistent page numbers are retained here.
    var cursor = const PageCursor(0, 0);
    ReaderPage? previous;
    while (true) {
      final page = forward(cursor);
      if (page == null) return previous;
      if (page.end.unit > end.unit ||
          page.end.unit == end.unit && page.end.offset >= end.offset) {
        return page;
      }
      previous = page;
      cursor = page.end;
    }
  }

  ReaderPage? _forwardColumn(PageCursor from) {
    final start = normalize(from);
    var cursor = start;
    var remaining = height;
    final fragments = <PageFragment>[];
    while (cursor.unit < index.chunks.length) {
      final chunk = index.chunks[cursor.unit];
      final text = chunk.text;
      if (text == null || text.isEmpty) {
        final extent = _objectHeight(cursor.unit);
        final fullPageImage = _fullPageImage(chunk.blockIndex, extent);
        if (extent > remaining + .01 || fullPageImage && fragments.isNotEmpty) {
          break;
        }
        final edges = readerBoxEdges(
          index.content,
          chunk.blockIndex,
          width: width,
          style: style,
          scaler: scaler,
          pageHeight: height,
        );
        fragments.add(
          PageFragment(
            cursor.unit,
            0,
            1,
            extent,
            text,
            boxTop: edges.top,
            boxBottom: edges.bottom,
          ),
        );
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
            blockIndex: chunk.blockIndex,
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
          blockIndex: chunk.blockIndex,
        );
        if (fitted == null) break;
        fragments.add(
          PageFragment(
            cursor.unit,
            cursor.offset,
            cursor.offset + fitted.count,
            fitted.height,
            fitted.text,
            flow: fitted.flow,
            linkLayout: fitted.linkLayout,
            boxTop: fitted.boxTop,
            boxBottom: fitted.boxBottom,
            boxContentHeight: fitted.boxContentHeight,
          ),
        );
        remaining -= fitted.height;
        cursor = normalize(
          PageCursor(cursor.unit, cursor.offset + fitted.count),
        );
      }
    }
    return fragments.isEmpty
        ? null
        : ReaderPage(
            start,
            cursor,
            fragments,
            centered: isIllustrationColumn(fragments),
          );
  }

  ReaderPage? _backwardColumn(PageCursor until) {
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
        final fullPageImage = _fullPageImage(chunk.blockIndex, extent);
        if (extent > remaining + .01 || fullPageImage && fragments.isNotEmpty) {
          break;
        }
        final edges = readerBoxEdges(
          index.content,
          chunk.blockIndex,
          width: width,
          style: style,
          scaler: scaler,
          pageHeight: height,
        );
        fragments.add(
          PageFragment(
            cursor.unit,
            0,
            1,
            extent,
            text,
            boxTop: edges.top,
            boxBottom: edges.bottom,
          ),
        );
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
          blockIndex: chunk.blockIndex,
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
            flow: fitted.flow,
            linkLayout: fitted.linkLayout,
            boxTop: fitted.boxTop,
            boxBottom: fitted.boxBottom,
            boxContentHeight: fitted.boxContentHeight,
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
            centered: isIllustrationColumn(fragments),
          );
  }
}
