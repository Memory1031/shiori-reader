import 'contracts/local_books.dart';
import 'models/models.dart';

/// No layout or storage state enters this deterministic migration.
final class ReparsedPosition {
  const ReparsedPosition(this.progress, {required this.approximate});
  final ReadingProgress? progress;
  final bool approximate;
}

String? _text(ContentBlock b) => switch (b) {
  ParagraphBlock(:final text) => text,
  HeadingBlock(:final text) => text,
  _ => null,
};
String _semantic(ContentBlock b) => switch (b) {
  ParagraphBlock(:final text) => 'text:$text',
  HeadingBlock(:final text) => 'text:$text',
  ImageBlock(:final media) => 'image:${media.mediaId}',
  _ => 'divider',
};

ReparsedPosition migrateLocalPosition(
  LocalBookContent old,
  LocalBookContent next,
  ReadingProgress? saved,
) {
  if (saved == null) return const ReparsedPosition(null, approximate: false);
  if (old.detail.summary.key != next.detail.summary.key ||
      saved.novelKey != next.detail.summary.key ||
      next.chapters.isEmpty) {
    throw ArgumentError('Mismatched migration');
  }
  final before = old.chapters
      .where((c) => c.key == saved.chapterKey)
      .firstOrNull;
  final same = next.chapters
      .where((c) => c.key == saved.chapterKey)
      .firstOrNull;
  final pos = saved.position;
  final validOld =
      before != null &&
      before.contentRevision == pos.contentRevision &&
      pos.blockIndex < before.blocks.length &&
      before.blocks[pos.blockIndex].blockKey == pos.blockKey;
  ReparsedPosition result(ChapterContent c, int i, double f, bool approximate) {
    final position = ReaderPosition(
      contentRevision: c.contentRevision,
      blockKey: c.blocks[i].blockKey,
      blockIndex: i,
      blockFraction: f,
      chapterFraction: ReaderPosition.fractionFor(
        blockIndex: i,
        blockFraction: f,
        blockCount: c.blocks.length,
      ),
    );
    return ReparsedPosition(
      ReadingProgress(
        snapshot: next.detail.summary,
        chapterKey: c.key,
        chapterOrdinalSnapshot: next.chapters.indexOf(c),
        catalogRevision: next.catalog.revision,
        position: position,
        completed: !approximate && saved.completed,
        bookProgress: next.progressMetrics.at(
          c.key,
          position.chapterFraction,
          terminal:
              !approximate && old.catalog.revision == next.catalog.revision
              ? saved.bookProgress?.terminal ?? BookTerminalState.reading
              : BookTerminalState.reading,
        ),
        lastReadAt: saved.lastReadAt,
      ),
      approximate: approximate,
    );
  }

  if (same != null &&
      same.contentRevision == pos.contentRevision &&
      pos.blockIndex < same.blocks.length &&
      same.blocks[pos.blockIndex].blockKey == pos.blockKey) {
    return result(same, pos.blockIndex, pos.blockFraction, false);
  }
  if (validOld) {
    final block = before.blocks[pos.blockIndex];
    final semantic = _semantic(block);
    bool context(ChapterContent c, int i) {
      for (final delta in [-1, 1]) {
        final a = pos.blockIndex + delta, b = i + delta;
        if (a >= 0 &&
            a < before.blocks.length &&
            b >= 0 &&
            b < c.blocks.length &&
            _semantic(before.blocks[a]) == _semantic(c.blocks[b])) {
          return true;
        }
      }
      return false;
    }

    final candidates = <(ChapterContent, int)>[];
    for (final c in same == null ? next.chapters : [same]) {
      for (var i = 0; i < c.blocks.length; i++) {
        if (_semantic(c.blocks[i]) == semantic) candidates.add((c, i));
      }
    }
    // A repeated paragraph's occurrence ordinal alone is not evidence.
    final oldCount = before.blocks
        .where((b) => _semantic(b) == semantic)
        .length;
    final matches = candidates.length == 1 && oldCount == 1
        ? candidates
        : candidates.where((v) => context(v.$1, v.$2)).toList();
    if (matches.length == 1 && block is! DividerBlock) {
      return result(
        matches.single.$1,
        matches.single.$2,
        pos.blockFraction,
        false,
      );
    }
    // Bounded character context tolerates split/merged paragraphs. Only text
    // windows of <=3 adjacent blocks, <=16384 scalars each, are considered.
    final text = _text(block);
    if (text != null && text.runes.length <= 16384) {
      final units = text.runes.toList();
      final offset = (pos.blockFraction * units.length).round().clamp(
        0,
        units.length,
      );
      final left = (offset - 32).clamp(0, units.length);
      final right = (offset + 32).clamp(0, units.length);
      final needle = String.fromCharCodes(units.sublist(left, right));
      final found = <String, (ChapterContent, int, double)>{};
      if (needle.runes.length >= 12) {
        for (final c in same == null ? next.chapters : [same]) {
          for (var start = 0; start < c.blocks.length; start++) {
            final lengths = <int>[];
            final buffer = StringBuffer();
            var total = 0;
            for (var j = start; j < c.blocks.length && j < start + 3; j++) {
              final t = _text(c.blocks[j]);
              if (t == null || t.length > 32768) break;
              final count = t.runes.length;
              if (total + count > 16384) break;
              total += count;
              lengths.add(count);
              buffer.write(t);
              final haystack = buffer.toString();
              var at = haystack.indexOf(needle);
              while (at >= 0) {
                var point =
                    haystack.substring(0, at).runes.length + offset - left;
                var index = start;
                for (final size in lengths) {
                  if (point <= size) break;
                  point -= size;
                  index++;
                }
                final size = lengths[index - start];
                found['${c.key.chapterId}:$index:$point'] = (
                  c,
                  index,
                  size == 0 ? 0 : point / size,
                );
                if (found.length > 1) break;
                at = haystack.indexOf(needle, at + 1);
              }
              if (found.length > 1) break;
            }
            if (found.length > 1) break;
          }
          if (found.length > 1) break;
        }
      }
      if (found.length == 1) {
        final match = found.values.single;
        return result(match.$1, match.$2, match.$3, true);
      }
    }
  }
  final target =
      same ??
      next.chapters[saved.chapterOrdinalSnapshot.clamp(
        0,
        next.chapters.length - 1,
      )];
  final point = same == null ? 0.0 : pos.chapterFraction * target.blocks.length;
  final index = point.floor().clamp(0, target.blocks.length - 1);
  return result(target, index, (point - index).clamp(0, 1), true);
}
