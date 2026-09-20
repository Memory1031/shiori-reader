import 'identity.dart';
import 'novel.dart';
import 'value_model.dart';

/// Chapter completion remains separate from deliberately crossing the book end.
enum BookTerminalState { reading, finished, caughtUp, currentEnd }

BookTerminalState bookEndState({
  required bool local,
  required NovelStatus status,
}) => local || status == NovelStatus.completed
    ? BookTerminalState.finished
    : status == NovelStatus.ongoing
    ? BookTerminalState.caughtUp
    : BookTerminalState.currentEnd;

/// Bound to ReadingProgress.catalogRevision and its terminal chapter identity.
final class BookProgressSnapshot extends ValueModel {
  BookProgressSnapshot({
    required double fraction,
    required int chapterCount,
    this.terminal = BookTerminalState.reading,
  }) : fraction = finiteRange(fraction, 0, 1, 'bookFraction'),
       chapterCount = nonNegative(chapterCount, 'chapterCount') {
    if (chapterCount == 0 ||
        terminal != BookTerminalState.reading && fraction != 1) {
      throw ArgumentError('Invalid book progress');
    }
  }
  final double fraction;
  final int chapterCount;
  final BookTerminalState terminal;
  Map<String, Object?> toJson() => {
    'fraction': fraction,
    'chapterCount': chapterCount,
    'terminal': terminal.name,
  };
  factory BookProgressSnapshot.fromJson(Map<String, dynamic> json) =>
      BookProgressSnapshot(
        fraction: (json['fraction'] as num).toDouble(),
        chapterCount: json['chapterCount'] as int,
        terminal: BookTerminalState.values.byName(json['terminal'] as String),
      );
  @override
  List<Object?> get values => [fraction, chapterCount, terminal];
}

/// Immutable prefix weights: O(1) sampling; independent of rendered layout.
/// Local adapters provide block counts. Online catalogs use one per chapter.
final class BookProgressMetrics {
  BookProgressMetrics({
    required this.revision,
    required Iterable<ChapterKey> order,
    required Iterable<int> weights,
  }) : order = List.unmodifiable(order) {
    final values = weights.toList();
    if (this.order.length != values.length ||
        this.order.toSet().length != this.order.length ||
        values.any((w) => w <= 0)) {
      throw ArgumentError('Invalid book weights');
    }
    var sum = 0;
    for (var i = 0; i < values.length; i++) {
      _entries[this.order[i]] = (sum, values[i], i);
      sum += values[i];
    }
    total = sum;
  }
  factory BookProgressMetrics.online(Catalog catalog) {
    final chapters = catalog.flatChapters.toList();
    return BookProgressMetrics(
      revision: catalog.revision,
      order: chapters.map((c) => c.key),
      weights: chapters.map((_) => 1),
    );
  }
  final String revision;
  final List<ChapterKey> order;
  final _entries = <ChapterKey, (int, int, int)>{};
  late final int total;
  int? ordinal(ChapterKey chapter) => _entries[chapter]?.$3;
  bool isLast(ChapterKey chapter) => order.isNotEmpty && order.last == chapter;
  BookProgressSnapshot? at(
    ChapterKey chapter,
    double fraction, {
    BookTerminalState terminal = BookTerminalState.reading,
  }) {
    finiteRange(fraction, 0, 1, 'chapterFraction');
    final entry = _entries[chapter];
    if (entry == null || total <= 0) return null;
    final end = isLast(chapter) && fraction == 1;
    return BookProgressSnapshot(
      fraction: (entry.$1 + entry.$2 * fraction) / total,
      chapterCount: order.length,
      terminal: end ? terminal : BookTerminalState.reading,
    );
  }
}
