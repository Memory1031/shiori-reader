import 'package:characters/characters.dart';

import '../../../domain/models/models.dart';
import '../position/position_resolver.dart';

/// Transient presentation metadata. Offsets count Unicode code points, not
/// UTF-16 code units, and boundaries never split an extended grapheme cluster.
final class RenderChunk {
  const RenderChunk({
    required this.blockIndex,
    required this.blockKey,
    required this.start,
    required this.end,
    required this.total,
    this.text,
  });
  final int blockIndex;
  final String blockKey;
  final int start;
  final int end;
  final int total;
  final String? text;
}

final class ChunkIndex {
  ChunkIndex(this.content, {this.maxCodePoints = 800}) {
    if (maxCodePoints < 16) {
      throw ArgumentError.value(maxCodePoints, 'maxCodePoints');
    }
    final result = <RenderChunk>[];
    for (var i = 0; i < content.blocks.length; i++) {
      final block = content.blocks[i];
      final text = switch (block) {
        ParagraphBlock(:final text) || HeadingBlock(:final text) => text,
        _ => null,
      };
      final total = text?.runes.length ?? 0;
      if (text == null || total == 0) {
        result.add(
          RenderChunk(
            blockIndex: i,
            blockKey: block.blockKey,
            start: 0,
            end: 0,
            total: 0,
            text: text,
          ),
        );
        continue;
      }
      var start = 0;
      var length = 0;
      var buffer = StringBuffer();
      void flush() {
        if (length == 0) return;
        result.add(
          RenderChunk(
            blockIndex: i,
            blockKey: block.blockKey,
            start: start,
            end: start + length,
            total: total,
            text: buffer.toString(),
          ),
        );
        start += length;
        length = 0;
        buffer = StringBuffer();
      }

      var rubyIndex = 0;
      for (final grapheme in text.characters) {
        final count = grapheme.runes.length;
        while (rubyIndex < block.inlineRuby.length &&
            block.inlineRuby[rubyIndex].end <= start + length) {
          rubyIndex++;
        }
        final insideRuby =
            rubyIndex < block.inlineRuby.length &&
            block.inlineRuby[rubyIndex].start < start + length;
        if (length + count > maxCodePoints && !insideRuby) flush();
        buffer.write(grapheme);
        length += count;
      }
      flush();
    }
    chunks = List.unmodifiable(result);
  }
  final ChapterContent content;
  final int maxCodePoints;
  late final List<RenderChunk> chunks;

  /// Content identity wins. Only a missing semantic key uses the coarse chapter
  /// fraction; callers can surface [usedFallback] rather than hiding the change.
  ({int chunk, double fraction, bool usedFallback}) resolve(
    ReaderPosition? position,
  ) {
    if (position == null) return (chunk: 0, fraction: 0, usedFallback: false);
    final resolved = resolveReaderPosition(content, position);
    final block = resolved.position.blockIndex;
    final fraction = resolved.position.blockFraction;
    var selected = chunks.indexWhere((c) => c.blockIndex == block);
    final total = chunks[selected].total;
    final offset = total == 0
        ? 0
        : readerCharacterOffset(fraction, total).clamp(0, total - 1);
    while (selected + 1 < chunks.length &&
        chunks[selected].end <= offset &&
        chunks[selected + 1].blockIndex == block) {
      selected++;
    }
    return (
      chunk: selected,
      fraction: fraction,
      usedFallback: resolved.usedFallback,
    );
  }

  ReaderPosition position(int unit, double fraction) {
    final chunk = chunks[unit];
    return ReaderPosition(
      contentRevision: content.contentRevision,
      blockKey: chunk.blockKey,
      blockIndex: chunk.blockIndex,
      blockFraction: fraction.clamp(0, 1),
      chapterFraction: ReaderPosition.fractionFor(
        blockIndex: chunk.blockIndex,
        blockFraction: fraction.clamp(0, 1),
        blockCount: content.blocks.length,
      ),
    );
  }
}
