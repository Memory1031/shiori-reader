import 'contracts/local_book_decoder.dart';
import 'models/models.dart';

/// Ephemeral, layout-independent metadata from one imported content snapshot.
final class LocalChapterDocument {
  LocalChapterDocument(ChapterContent content)
    : key = content.key,
      revision = content.contentRevision,
      blocks = List.unmodifiable(content.blocks.map((b) => b.blockKey));
  final ChapterKey key;
  final String revision;
  final List<String> blocks;
  bool matches(ChapterContent content) =>
      key == content.key && revision == content.contentRevision;
}

final class LocalChapterTarget {
  const LocalChapterTarget(this.chapter, this.position);
  final ChapterKey chapter;
  final ReaderPosition position;
}

final class LocalChapterSection {
  const LocalChapterSection(this.entry, this.start, this.end, this.reliable);
  final LocalNavigationEntry entry;
  final int start, end;
  final bool reliable;
  String get title => entry.title;
  double fraction(double coordinate) =>
      ((coordinate - start) / (end - start)).clamp(0.0, 1.0);
}

/// Navigation targets partition the existing integer block-weight coordinate.
/// Neither title equality nor resource/href equality merges distinct targets.
final class LocalChapterProgressIndex {
  LocalChapterProgressIndex._(
    this.metrics,
    this.documents,
    this.navigation,
    this.sections,
    this._prefixes,
  );
  final BookProgressMetrics metrics;
  final Map<ChapterKey, LocalChapterDocument> documents;
  final List<LocalNavigationEntry> navigation;
  final List<LocalChapterSection> sections;
  final List<int> _prefixes;

  static LocalChapterProgressIndex? build({
    required BookProgressMetrics metrics,
    required Iterable<ChapterContent> chapters,
    required List<LocalNavigationEntry> navigation,
  }) {
    final docs = {for (final c in chapters) c.key: LocalChapterDocument(c)};
    final prefixes = <int>[];
    var total = 0;
    for (final key in metrics.order) {
      final doc = docs[key];
      if (doc == null ||
          doc.blocks.isEmpty ||
          metrics.weight(key) != doc.blocks.length) {
        return null;
      }
      prefixes.add(total);
      total += doc.blocks.length;
    }
    if (total != metrics.total || total == 0) return null;
    final starts = <int, (LocalNavigationEntry, int)>{};
    final unknown = <(int, int)>[];
    void collect(List<LocalNavigationEntry> entries, int depth) {
      for (final entry in entries) {
        final ordinal = metrics.ordinal(entry.chapterKey);
        if (ordinal != null) {
          final doc = docs[entry.chapterKey]!;
          final block = entry.blockKey == null
              ? 0
              : doc.blocks.indexOf(entry.blockKey!);
          if (block < 0) {
            unknown.add((
              prefixes[ordinal],
              prefixes[ordinal] + doc.blocks.length,
            ));
          } else if (entry.title.trim().isNotEmpty) {
            final coordinate = prefixes[ordinal] + block;
            final old = starts[coordinate];
            // Deepest label wins; equal-depth ties retain tree traversal order.
            if (old == null || depth > old.$2) {
              starts[coordinate] = (entry, depth);
            }
          }
        }
        collect(entry.children, depth + 1);
      }
    }

    collect(navigation, 0);
    final ordered = starts.keys.toList()..sort();
    final sections = <LocalChapterSection>[];
    for (var i = 0; i < ordered.length; i++) {
      final start = ordered[i],
          end = i + 1 == ordered.length ? total : ordered[i + 1];
      sections.add(
        LocalChapterSection(
          starts[start]!.$1,
          start,
          end,
          !unknown.any((r) => r.$1 < end && start < r.$2),
        ),
      );
    }
    return LocalChapterProgressIndex._(
      metrics,
      Map.unmodifiable(docs),
      List.unmodifiable(navigation),
      List.unmodifiable(sections),
      List.unmodifiable(prefixes),
    );
  }

  int _floor(List<int> values, double coordinate) {
    var lo = 0, hi = values.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (values[mid] <= coordinate) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo - 1;
  }

  late final List<int> _starts = sections
      .map((s) => s.start)
      .toList(growable: false);
  LocalChapterSection? sectionAt(ChapterKey chapter, ReaderPosition? anchor) {
    final ordinal = metrics.ordinal(chapter), doc = documents[chapter];
    if (ordinal == null || doc == null) return null;
    if (anchor != null &&
        (anchor.contentRevision != doc.revision ||
            anchor.blockIndex >= doc.blocks.length ||
            doc.blocks[anchor.blockIndex] != anchor.blockKey)) {
      return null;
    }
    // Ownership uses the anchor's block, never the visible document endpoint.
    final at = _floor(
      _starts,
      (_prefixes[ordinal] + (anchor?.blockIndex ?? 0)).toDouble(),
    );
    return at < 0 || !sections[at].reliable ? null : sections[at];
  }

  double? coordinate(ChapterKey chapter, double fraction) =>
      metrics.coordinate(chapter, fraction);
  double bookFractionAt(LocalChapterSection section, double fraction) =>
      (section.start +
          (section.end - section.start) * fraction.clamp(0.0, 1.0)) /
      metrics.total;
  LocalChapterSection? adjacent(LocalChapterSection section, int direction) {
    final at = _floor(_starts, section.start.toDouble()) + direction;
    return at < 0 || at >= sections.length || !sections[at].reliable
        ? null
        : sections[at];
  }

  LocalChapterTarget target(LocalChapterSection section, double fraction) {
    if (!fraction.isFinite ||
        fraction < 0 ||
        fraction > 1 ||
        !sections.contains(section) ||
        !section.reliable) {
      throw ArgumentError('Invalid logical chapter target');
    }
    // 100% belongs to the preceding real block at fraction 1. No epsilon, and
    // no next-section or book-completion navigation is synthesized.
    final coordinate = fraction == 1
        ? section.end.toDouble()
        : section.start + (section.end - section.start) * fraction;
    final blockCoordinate = fraction == 1
        ? section.end - 1
        : coordinate.floor().clamp(section.start, section.end - 1);
    final ordinal = _floor(_prefixes, blockCoordinate.toDouble());
    final chapter = metrics.order[ordinal], doc = documents[chapter]!;
    final block = blockCoordinate - _prefixes[ordinal];
    final within = (coordinate - blockCoordinate).clamp(0.0, 1.0);
    return LocalChapterTarget(
      chapter,
      ReaderPosition(
        contentRevision: doc.revision,
        blockKey: doc.blocks[block],
        blockIndex: block,
        blockFraction: within,
        chapterFraction: ReaderPosition.fractionFor(
          blockIndex: block,
          blockFraction: within,
          blockCount: doc.blocks.length,
        ),
      ),
    );
  }
}
