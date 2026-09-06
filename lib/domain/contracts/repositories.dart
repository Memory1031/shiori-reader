import '../models/models.dart';
import '../models/value_model.dart';
import 'cancellation.dart';
import 'loading.dart';
import 'novel_source.dart';
import 'result.dart';

abstract interface class NovelRepository {
  Future<Result<List<DiscoverSection>>> discover(
    SourceId sourceId, {
    required CancellationToken cancellation,
  });
  Future<Result<SearchPage>> search(
    SourceId sourceId,
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  });
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  });
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  });
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  });

  /// Broadcast, no initial event and no I/O on subscribe. Subscribe BEFORE load
  /// to observe deduplicated background refresh completion, including failures.
  /// Cancel a subscription on dispose. It does not cancel other subscribers.
  /// Only accepted/current results are published, never superseded generations.
  Stream<Result<LoadResult<NovelDetail>>> detailUpdates(NovelKey key);
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key);
  Stream<Result<LoadResult<ChapterContent>>> chapterUpdates(ChapterKey key);
}

final class ProgressWriteStamp extends ValueModel {
  ProgressWriteStamp({required int generation, required int sequence})
    : generation = nonNegative(generation, 'generation'),
      sequence = nonNegative(sequence, 'sequence');

  /// Issued by LibraryRepository.beginProgressSession, never wall clock time.
  final int generation;

  /// Monotonically increasing within that session, per novel.
  final int sequence;
  @override
  List<Object?> get values => [generation, sequence];
}

abstract interface class LibraryRepository {
  /// Local initial snapshot, then immutable ordered snapshots; typed failures
  /// are stream DATA, not raw stream errors. Subscription owns its DB listener.
  Stream<Result<List<BookshelfEntry>>> watchBookshelf();
  Stream<Result<List<ReadingProgress>>> watchRecentReading();

  /// Idempotent by NovelKey; an existing entry keeps its original addedAt.
  Future<Result<BookshelfEntry>> putBookshelf(
    BookshelfEntry entry, {
    required CancellationToken cancellation,
  });

  /// Returns removed entry for undo; NEVER deletes progress/content/cache.
  Future<Result<BookshelfEntry?>> removeFromBookshelf(
    NovelKey key, {
    required CancellationToken cancellation,
  });
  Future<Result<ReadingProgress?>> getProgress(
    NovelKey key, {
    required CancellationToken cancellation,
  });

  /// Mint a new per-novel monotonically increasing generation. Old session
  /// writes are rejected even after process restart (DB-002 implements storage).
  Future<Result<int>> beginProgressSession(
    NovelKey key, {
    required CancellationToken cancellation,
  });

  /// true = committed, false = obsolete/duplicate stamp ignored. Cancellation
  /// before commit is Failure(cancelled); after commit return actual success.
  Future<Result<bool>> saveProgress(
    ReadingProgress progress, {
    required ProgressWriteStamp stamp,
    required CancellationToken cancellation,
  });

  /// Also invalidate outstanding session generations so late writes cannot
  /// resurrect deleted history; bookshelf/cache remain intact.
  Future<Result<void>> clearHistory(
    NovelKey key, {
    required CancellationToken cancellation,
  });
}

abstract interface class SettingsStore {
  Future<Result<ReaderSettings>> load({
    required CancellationToken cancellation,
  });

  /// ReaderSettings already validates values; expected persistence errors are
  /// failures. Bad stored codec/version may fall back to defaults with private
  /// diagnostics in DB-002; do not destructively reset unrelated user data.
  Future<Result<void>> save(
    ReaderSettings settings, {
    required CancellationToken cancellation,
  });
}
