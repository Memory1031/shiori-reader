import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import 'reader_authored_colors.dart';

/// The book owner changes only the notifier value; page metrics never depend on it.
class ReaderSearchHighlightScope extends InheritedWidget {
  const ReaderSearchHighlightScope({
    super.key,
    required this.active,
    required this.content,
    required super.child,
  });
  final ValueListenable<LocalSearchBodyHit?> active;
  final ChapterContent content;
  static ReaderSearchHighlightScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReaderSearchHighlightScope>();
  @override
  bool updateShouldNotify(ReaderSearchHighlightScope old) =>
      active != old.active || content != old.content;
}

/// Source identity and range projection. No query text is matched at paint time.
@immutable
class ReaderGlyphHighlight {
  const ReaderGlyphHighlight(
    this.active,
    this.chapter,
    this.revision,
    this.blockKey,
    this.blockIndex,
    this.container,
    this.primary,
    this.foregroundAt,
  );
  final ValueListenable<LocalSearchBodyHit?> active;
  final ChapterKey chapter;
  final String revision, blockKey;
  final int blockIndex;
  final Color container, primary;
  final Color Function(int) foregroundAt;
  Color get color {
    final ink = foregroundAt(active.value?.start ?? 0);
    final surface =
        readerColorContrast(ink, primary) > readerColorContrast(ink, container)
        ? primary
        : container;
    if (readerColorContrast(ink, surface) >= 4.5) return surface;
    // Preserve authored ink; adjust only the accent background's lightness.
    final edge =
        readerColorContrast(ink, Colors.black) >
            readerColorContrast(ink, Colors.white)
        ? Colors.black
        : Colors.white;
    var low = 0.0, high = 1.0;
    for (var i = 0; i < 8; i++) {
      final middle = (low + high) / 2;
      if (readerColorContrast(ink, Color.lerp(surface, edge, middle)!) >= 4.5) {
        high = middle;
      } else {
        low = middle;
      }
    }
    return Color.lerp(surface, edge, high)!;
  }

  static ReaderGlyphHighlight? of(
    BuildContext context,
    String? blockKey,
    int? blockIndex, {
    Color Function(int)? foregroundAt,
  }) {
    final scope = ReaderSearchHighlightScope.of(context);
    if (scope == null || blockKey == null || blockIndex == null) return null;
    final theme = Theme.of(context);
    return ReaderGlyphHighlight(
      scope.active,
      scope.content.key,
      scope.content.contentRevision,
      blockKey,
      blockIndex,
      theme.colorScheme.primaryContainer,
      theme.colorScheme.primary,
      foregroundAt ?? (_) => theme.colorScheme.onSurface,
    );
  }

  ({int start, int end})? range(int offset, int length) {
    final hit = active.value;
    if (hit == null ||
        hit.chapter != chapter ||
        hit.contentRevision != revision ||
        hit.blockKey != blockKey ||
        hit.blockIndex != blockIndex) {
      return null;
    }
    final start = math.max(hit.start, offset),
        end = math.min(hit.end, offset + length);
    return end <= start ? null : (start: start - offset, end: end - offset);
  }

  TextSelection? selection(String text, int offset) {
    final runes = text.runes.toList(),
        range = this.range(offset, text.runes.length);
    if (range == null) return null;
    final from = String.fromCharCodes(runes.take(range.start)).length;
    final to =
        from +
        String.fromCharCodes(
          runes.skip(range.start).take(range.end - range.start),
        ).length;
    return expandReaderGlyphSelection(
      text,
      TextSelection(baseOffset: from, extentOffset: to),
    );
  }

  void paint(Canvas canvas, Iterable<Rect> boxes) {
    final brush = Paint()..color = color;
    for (final rect in boxes) {
      canvas.drawRect(rect, brush);
    }
  }
}

/// A combining sequence remains one visible glyph even if a substring selects
/// only some of its source code points. Semantic hit offsets stay unchanged.
TextSelection expandReaderGlyphSelection(String text, TextSelection selected) {
  var at = 0, start = selected.start, end = selected.end;
  for (final cluster in text.characters) {
    final next = at + cluster.length;
    if (at < selected.start && next > selected.start) start = at;
    if (at < selected.end && next > selected.end) end = next;
    at = next;
    if (at >= selected.end) break;
  }
  return TextSelection(baseOffset: start, extentOffset: end);
}

class ReaderPaintedSearchText extends SingleChildRenderObjectWidget {
  const ReaderPaintedSearchText({
    super.key,
    required super.child,
    required this.highlight,
    required this.text,
    required this.prefix,
    required this.offset,
    required this.collapsed,
  });
  final ReaderGlyphHighlight highlight;
  final String text, prefix;
  final int offset;
  final List<(int, int)> collapsed;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      ReaderSearchTextRender(this);
  @override
  void updateRenderObject(
    BuildContext context,
    ReaderSearchTextRender renderObject,
  ) => renderObject.update(this);
}

class ReaderSearchTextRender extends RenderProxyBox {
  ReaderSearchTextRender(this.configuration);
  ReaderPaintedSearchText configuration;
  void update(ReaderPaintedSearchText next) {
    if (attached && configuration.highlight.active != next.highlight.active) {
      configuration.highlight.active.removeListener(markNeedsPaint);
      next.highlight.active.addListener(markNeedsPaint);
    }
    configuration = next;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    configuration.highlight.active.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    configuration.highlight.active.removeListener(markNeedsPaint);
    super.detach();
  }

  RenderParagraph? _paragraph(RenderObject node) {
    if (node is RenderParagraph) return node;
    RenderParagraph? result;
    node.visitChildren((child) {
      result ??= _paragraph(child);
    });
    return result;
  }

  /// The same boxes used for painting, exposed as geometry for layout regression tests.
  List<Rect> get selectedBoxes {
    final c = configuration, runes = configuration.text.runes.toList();
    final hit = c.highlight.range(c.offset, runes.length);
    final paragraph = child == null ? null : _paragraph(child!);
    if (hit == null || paragraph == null) return const [];
    final collapsed = [...c.collapsed]..sort((a, b) => a.$1.compareTo(b.$1));
    int display(int source) {
      var point = 0, units = c.prefix.length;
      for (final range in collapsed) {
        final start = range.$1 - c.offset, end = start + range.$2;
        if (source <= start) break;
        units += String.fromCharCodes(runes.sublist(point, start)).length;
        if (source < end) return units;
        units++;
        point = end;
      }
      return units + String.fromCharCodes(runes.sublist(point, source)).length;
    }

    final pieces = <(int, int)>[];
    var cursor = hit.start;
    for (final r in collapsed) {
      final start = (r.$1 - c.offset).clamp(hit.start, hit.end),
          end = (r.$1 + r.$2 - c.offset).clamp(hit.start, hit.end);
      if (start > cursor) pieces.add((cursor, start));
      if (end > cursor) cursor = end;
    }
    if (cursor < hit.end) pieces.add((cursor, hit.end));
    final plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
    return [
      for (final part in pieces)
        for (final box in paragraph.getBoxesForSelection(
          expandReaderGlyphSelection(
            plain,
            TextSelection(
              baseOffset: display(part.$1),
              extentOffset: display(part.$2),
            ),
          ),
        ))
          MatrixUtils.transformRect(
            paragraph.getTransformTo(this),
            box.toRect(),
          ).intersect(Offset.zero & size),
    ];
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.save();
    context.canvas.clipRect(offset & size);
    configuration.highlight.paint(
      context.canvas,
      selectedBoxes.map((r) => r.shift(offset)),
    );
    context.canvas.restore();
    super.paint(context, offset);
  }
}

void paintReaderGlyphRange(
  Canvas canvas,
  TextPainter painter,
  Offset at,
  ReaderGlyphHighlight? mark,
  String text,
  int sourceStart,
) {
  mark?.paint(canvas, readerGlyphBoxes(painter, at, mark, text, sourceStart));
}

List<Rect> readerGlyphBoxes(
  TextPainter painter,
  Offset at,
  ReaderGlyphHighlight? mark,
  String text,
  int sourceStart,
) {
  final selected = mark?.selection(text, sourceStart);
  return selected == null
      ? const []
      : painter
            .getBoxesForSelection(selected)
            .map((b) => b.toRect().shift(at))
            .toList();
}
