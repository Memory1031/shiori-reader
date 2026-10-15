import '../models/models.dart';
import '../models/value_model.dart';
import 'cancellation.dart';
import 'local_content_links.dart';
import 'result.dart';

/// Transient publication identity, independent of chapter semantic revisions.
final class LocalSearchSnapshotId extends ValueModel {
  LocalSearchSnapshotId(String value) : value = nonBlank(value, 'snapshot');
  final String value;
  @override
  List<Object?> get values => [value];
}

/// Opaque, single-use continuation bound to one session and query.
final class LocalSearchCursor extends ValueModel {
  LocalSearchCursor(String value) : value = nonBlank(value, 'cursor');
  final String value;
  @override
  List<Object?> get values => [value];
}

final class LocalSearchSnippet extends ValueModel {
  const LocalSearchSnippet({
    required this.before,
    required this.match,
    required this.after,
  });
  final String before, match, after;
  @override
  List<Object?> get values => [before, match, after];
}

sealed class LocalSearchHit extends ValueModel {
  LocalSearchHit({
    required this.snapshot,
    required this.chapter,
    required this.contentRevision,
    required this.blockKey,
    required int blockIndex,
    required this.snippet,
  }) : blockIndex = nonNegative(blockIndex, 'blockIndex');
  final LocalSearchSnapshotId snapshot;
  final ChapterKey chapter;
  final String contentRevision, blockKey;
  final int blockIndex;
  final LocalSearchSnippet snippet;
  @override
  List<Object?> get values => [
    snapshot,
    chapter,
    contentRevision,
    blockKey,
    blockIndex,
    snippet,
  ];
}

final class LocalSearchBodyHit extends LocalSearchHit {
  LocalSearchBodyHit({
    required super.snapshot,
    required super.chapter,
    required super.contentRevision,
    required super.blockKey,
    required super.blockIndex,
    required super.snippet,
    required this.start,
    required this.end,
  }) {
    if (start < 0 || end <= start) throw ArgumentError('Invalid source range');
  }

  /// Half-open Unicode code-point range in the original semantic block.
  final int start, end;
  @override
  List<Object?> get values => [...super.values, start, end];
}

final class LocalSearchFootnoteHit extends LocalSearchHit {
  LocalSearchFootnoteHit({
    required super.snapshot,
    required super.chapter,
    required super.contentRevision,
    required super.blockKey,
    required super.blockIndex,
    required super.snippet,
    required this.reference,
    required this.noteStart,
    required this.noteEnd,
  }) {
    if (reference.footnoteText == null ||
        reference.sourceOffset == null ||
        reference.source != chapter ||
        reference.sourceBlockKey != blockKey ||
        noteStart < 0 ||
        noteEnd <= noteStart) {
      throw ArgumentError('Invalid footnote hit');
    }
  }

  /// Source marker and note text; note offsets are never body offsets.
  final LocalContentLink reference;
  final int noteStart, noteEnd;
  @override
  List<Object?> get values => [
    ...super.values,
    reference.sourceOffset,
    reference.label,
    reference.footnoteText,
    noteStart,
    noteEnd,
  ];
}

final class LocalSearchPage {
  LocalSearchPage({
    required Iterable<LocalSearchHit> hits,
    required this.snapshot,
    required this.nextCursor,
    required this.matchesSoFar,
    required this.totalMatches,
  }) : hits = List.unmodifiable(hits);
  final List<LocalSearchHit> hits;
  final LocalSearchSnapshotId snapshot;

  /// Non-null means unscanned text remains, not that another hit is guaranteed.
  final LocalSearchCursor? nextCursor;
  final int matchesSoFar;

  /// Known only after the entire book has been scanned.
  final int? totalMatches;
}

/// Optional capability; never delegates non-local identities to online search.
abstract interface class LocalBookSearchRepository {
  Future<Result<LocalSearchSession>> openLocalSearch(
    NovelKey book, {
    required CancellationToken cancellation,
  });
}

/// Caller owns the session. Closing releases its snapshot, worker and cursor.
abstract interface class LocalSearchSession {
  LocalSearchSnapshotId get snapshot;
  bool get isValid;

  /// Trimmed literal substring, 1..256 UTF-16 units, ASCII case insensitive.
  /// A new search cancels the old query. Each page holds at most 64 hits.
  Future<Result<LocalSearchPage>> search(
    String query, {
    required CancellationToken cancellation,
  });
  Future<Result<LocalSearchPage>> nextPage(
    LocalSearchCursor cursor, {
    required CancellationToken cancellation,
  });

  /// Recheck publication and file metadata before using a result for navigation.
  Future<Result<void>> validate(
    LocalSearchSnapshotId snapshot, {
    required CancellationToken cancellation,
  });
  Future<void> cancel();
  Future<void> close();
}
