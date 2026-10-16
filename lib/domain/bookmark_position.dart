import 'models/models.dart';
import 'reparse_position.dart' show migrationText;

final class BookmarkResolution {
  const BookmarkResolution(this.location, {this.chapter, this.anchor});
  final BookmarkLocation location;
  final ChapterKey? chapter;
  final BookmarkAnchor? anchor;
  bool get located => anchor != null;
}

/// One ephemeral preparation shared by a batch, never a persistent text index.
final class BookmarkPositionIndex {
  BookmarkPositionIndex(Iterable<ChapterContent> chapters)
    : chapters = {for (final c in chapters) c.key: c};
  final Map<ChapterKey, ChapterContent> chapters;
  final _runs = <ChapterKey, List<_TextRun>>{};
  List<_TextRun> _text(ChapterContent c) => _runs.putIfAbsent(c.key, () {
    final runs = <_TextRun>[];
    var first = 0;
    final texts = <String>[];
    void flush() {
      if (texts.isNotEmpty) runs.add(_TextRun(first, List.of(texts)));
      texts.clear();
    }

    for (var i = 0; i < c.blocks.length; i++) {
      final t = migrationText(c.blocks[i]);
      if (t == null) {
        flush();
        continue;
      }
      if (texts.isEmpty) first = i;
      texts.add(t);
    }
    flush();
    return runs;
  });

  bool valid(ChapterContent c, ReaderPosition p) =>
      p.contentRevision == c.contentRevision &&
      p.blockIndex < c.blocks.length &&
      c.blocks[p.blockIndex].blockKey == p.blockKey;

  BookmarkAnchor? capture(ChapterKey chapter, ReaderPosition p) {
    final c = chapters[chapter];
    if (c == null || !valid(c, p)) return null;
    final block = c.blocks[p.blockIndex],
        text = migrationText(c.blocks[p.blockIndex]);
    var quote = '', offset = 0;
    bool unique;
    if (text != null) {
      final run = _text(c).firstWhere(
        (r) =>
            r.first <= p.blockIndex &&
            p.blockIndex < r.first + r.lengths.length,
      );
      final point = run.point(
        p.blockIndex,
        _offset(p.blockFraction, text.runes.length),
      );
      final left = (point - 32).clamp(0, run.units.length),
          right = (point + 32).clamp(0, run.units.length);
      quote = String.fromCharCodes(run.units.sublist(left, right));
      offset = point - left;
      unique = _matches(c, quote, offset).length == 1;
    } else {
      unique =
          block is! DividerBlock &&
          c.blocks
                  .where((b) => b.semanticDigest == block.semanticDigest)
                  .length ==
              1;
    }
    final length = text?.runes.length ?? 0;
    final fraction = length == 0
        ? p.blockFraction
        : _offset(p.blockFraction, length) / length;
    return BookmarkAnchor(
      position: ReaderPosition(
        contentRevision: c.contentRevision,
        blockKey: block.blockKey,
        blockIndex: p.blockIndex,
        blockFraction: fraction,
        chapterFraction: ReaderPosition.fractionFor(
          blockIndex: p.blockIndex,
          blockFraction: fraction,
          blockCount: c.blocks.length,
        ),
      ),
      quote: quote,
      quoteOffset: offset,
      unique: unique,
      blockDigest: block.semanticDigest,
    );
  }

  BookmarkResolution resolve(
    ChapterKey chapter,
    BookmarkAnchor a, {
    BookmarkPositionIndex? old,
  }) {
    final same = chapters[chapter], p = a.position;
    if (same != null && valid(same, p)) {
      return BookmarkResolution(
        BookmarkLocation.exact,
        chapter: chapter,
        anchor: a,
      );
    }
    if (!a.unique) return const BookmarkResolution(BookmarkLocation.inexact);
    final source = old?.chapters[chapter];
    // Local migration must validate the original snapshot too.
    if (old != null && (source == null || !old.valid(source, p))) {
      return const BookmarkResolution(BookmarkLocation.unavailable);
    }
    List<(ChapterContent, int, double)> matches(
      Iterable<ChapterContent> candidates,
    ) => [
      for (final c in candidates)
        if (a.quote.runes.length >= 12)
          ..._matches(c, a.quote, a.quoteOffset).map((m) => (c, m.$1, m.$2))
        else if (a.quote.isEmpty)
          for (var i = 0; i < c.blocks.length; i++)
            if (migrationText(c.blocks[i]) == null &&
                c.blocks[i].semanticDigest == a.blockDigest)
              (c, i, p.blockFraction),
    ];
    var found = matches(same == null ? const [] : [same]);
    if (found.isEmpty && old != null) {
      // Changing chapters requires uniqueness in both complete snapshots.
      if (matches(old.chapters.values).length != 1) {
        return const BookmarkResolution(BookmarkLocation.inexact);
      }
      found = matches(chapters.values);
    }
    if (found.length != 1) {
      return BookmarkResolution(
        found.isEmpty ? BookmarkLocation.unavailable : BookmarkLocation.inexact,
      );
    }
    final (c, i, f) = found.single;
    final target = capture(
      c.key,
      ReaderPosition(
        contentRevision: c.contentRevision,
        blockKey: c.blocks[i].blockKey,
        blockIndex: i,
        blockFraction: f,
        chapterFraction: ReaderPosition.fractionFor(
          blockIndex: i,
          blockFraction: f,
          blockCount: c.blocks.length,
        ),
      ),
    );
    return BookmarkResolution(
      BookmarkLocation.migrated,
      chapter: c.key,
      anchor: target,
    );
  }

  List<(int, double)> _matches(ChapterContent c, String quote, int offset) {
    if (quote.isEmpty) return const [];
    final matches = <(int, double)>[];
    for (final run in _text(c)) {
      var at = run.text.indexOf(quote);
      while (at >= 0) {
        var point = run.text.substring(0, at).runes.length + offset;
        var block = 0;
        while (block + 1 < run.lengths.length && point >= run.lengths[block]) {
          point -= run.lengths[block++];
        }
        matches.add((
          run.first + block,
          run.lengths[block] == 0 ? 0 : point / run.lengths[block],
        ));
        if (matches.length > 1) return matches;
        at = run.text.indexOf(quote, at + 1);
      }
    }
    return matches;
  }
}

int _offset(double fraction, int length) =>
    (fraction * length).round().clamp(0, length);

final class _TextRun {
  _TextRun(this.first, List<String> blocks)
    : text = blocks.join(),
      lengths = [for (final b in blocks) b.runes.length];
  final int first;
  final String text;
  final List<int> lengths;
  late final units = text.runes.toList();
  int point(int block, int offset) =>
      lengths.take(block - first).fold(offset, (a, b) => a + b);
}

List<UserBookmark> migrateBookmarks(
  Iterable<ChapterContent> before,
  Iterable<ChapterContent> after,
  List<UserBookmark> bookmarks,
) {
  final old = BookmarkPositionIndex(before),
      next = BookmarkPositionIndex(after);
  return [
    for (final b in bookmarks)
      () {
        final r = next.resolve(b.chapter, b.anchor, old: old);
        return b.resolved(
          r.chapter ?? b.chapter,
          r.anchor ?? b.anchor,
          r.location,
        );
      }(),
  ];
}
