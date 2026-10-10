import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/controllers/scoped_controller.dart';

class LibraryController extends ScopedController {
  LibraryController(
    this.repository, {
    this.cache,
    this.localBooks,
    this.canStartBatch,
    this.onBatchLockChanged,
  });
  final bool Function()? canStartBatch;
  final void Function(bool)? onBatchLockChanged;
  final LocalBookManagement? localBooks;
  bool localCleanupPending = false;
  Map<NovelKey, LocalBookFormat> localFormats = const {};
  final CacheManagement? cache;
  final LibraryRepository repository;
  List<BookshelfEntry> books = const [];
  List<ReadingProgress> recent = const [];
  Map<NovelKey, ReadingProgress> _progressByBook = const {};
  AppFailure? shelfFailure, historyFailure, writeFailure;
  bool shelfReady = false, historyReady = false;
  bool _writing = false;
  LibraryWriteLease? _batch;
  bool get writing => _writing || _batch != null;
  bool get batchAvailable =>
      !isClosed && !writing && canStartBatch?.call() != false;

  /// Holds the shared write lane through confirmation, execution and results.
  /// Batch items use the same removal operation without re-entering _write.
  LibraryWriteLease? acquireBatch(CancellationSource request) {
    if (!batchAvailable) return null;
    final lease = _batch = LibraryWriteLease._(this);
    cancellation.whenCancelled.then((_) => request.cancel());
    onBatchLockChanged?.call(true);
    update();
    return lease;
  }

  Future<Result<LocalBookDeletion>> removeInBatch(
    NovelKey key,
    LibraryWriteLease lease, {
    required CancellationToken cancellation,
  }) {
    if (isClosed || _batch != lease || cancellation.isCancelled) {
      return Future.value(
        Failure(AppFailure.cancelled(Operation.libraryWrite)),
      );
    }
    return _remove(key, cancellation);
  }

  @override
  void onInit() {
    super.onInit();
    final management = localBooks;
    if (management != null) {
      listenTo(management.watchBooks(), (result) {
        if (result case Success(:final value)) {
          localFormats = {for (final book in value) book.key: book.format};
          update();
        }
      });
    }
    listenTo(repository.watchBookshelf(), (result) {
      shelfReady = true;
      switch (result) {
        case Success(:final value):
          books = List.unmodifiable(value);
          shelfFailure = null;
        case Failure(:final failure):
          shelfFailure = failure;
      }
      update();
    });
    listenTo(repository.watchRecentReading(), (result) {
      historyReady = true;
      switch (result) {
        case Success(:final value):
          recent = List.unmodifiable(value);
          _progressByBook = {for (final item in value) item.novelKey: item};
          historyFailure = null;
        case Failure(:final failure):
          historyFailure = failure;
      }
      update();
    });
  }

  bool contains(NovelKey key) => books.any((b) => b.snapshot.key == key);
  ReadingProgress? progressFor(NovelKey key) => _progressByBook[key];
  ReadingProgress? get continueReadingProgress =>
      recent.where((progress) => contains(progress.novelKey)).firstOrNull;

  List<BookshelfEntry> get sorted {
    final times = {for (final item in recent) item.novelKey: item.lastReadAt};
    return [...books]..sort((a, b) {
      final date = (times[b.snapshot.key] ?? b.addedAt).compareTo(
        times[a.snapshot.key] ?? a.addedAt,
      );
      if (date != 0) return date;
      final source = a.snapshot.key.sourceId.value.compareTo(
        b.snapshot.key.sourceId.value,
      );
      return source != 0
          ? source
          : a.snapshot.key.novelId.compareTo(b.snapshot.key.novelId);
    });
  }

  Future<bool> _write<T>(
    Future<Result<T>> Function() work,
    void Function(T) accept,
  ) async {
    if (isClosed || writing) return false;
    _writing = true;
    writeFailure = null;
    update();
    Result<T> result;
    try {
      result = await work();
    } catch (_) {
      result = Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.libraryWrite,
          retryPolicy: RetryPolicy.manual,
        ),
      );
    }
    if (isClosed) return false;
    _writing = false;
    if (result case Success(:final value)) {
      accept(value);
      update();
      return true;
    }
    final failure = (result as Failure<T>).failure;
    if (!failure.isCancellation) writeFailure = failure;
    update();
    return false;
  }

  Future<bool> add(NovelSummary summary) => _write(
    () => repository.putBookshelf(
      BookshelfEntry(snapshot: summary, addedAt: DateTime.now()),
      cancellation: cancellation,
    ),
    (_) {},
  );
  Future<bool> remove(NovelKey key) => _write<LocalBookDeletion>(
    () => _remove(key, cancellation),
    (result) => localCleanupPending = result.cleanupPending,
  );

  Future<Result<LocalBookDeletion>> _remove(
    NovelKey key,
    CancellationToken token,
  ) async {
    if (key.sourceId == LocalBookIdentity.sourceId) {
      final management = localBooks;
      if (management == null) {
        return Failure(
          AppFailure(
            kind: FailureKind.unsupported,
            operation: Operation.libraryWrite,
          ),
        );
      }
      return management.deleteBook(key, cancellation: token);
    }
    // Keep the entry available for retry if cache cleanup fails. These stores
    // cannot share a transaction; a later library failure may leave no cache.
    final management = cache;
    if (management != null) {
      final cleared = await management.clear(novel: key);
      if (cleared case Failure(:final failure)) {
        return Failure<LocalBookDeletion>(failure);
      }
    }
    if (token.isCancelled) {
      return Failure(AppFailure.cancelled(Operation.libraryWrite));
    }
    final removed = await repository.removeFromBookshelf(
      key,
      cancellation: token,
    );
    return switch (removed) {
      Success() => const Success(LocalBookDeletion()),
      Failure(:final failure) => Failure(failure),
    };
  }

  Future<bool> clearHistory(NovelKey key) => _write(
    () => repository.clearHistory(key, cancellation: cancellation),
    (_) {},
  );
}

class LibraryWriteLease {
  LibraryWriteLease._(this._owner);
  final LibraryController _owner;
  void release() {
    if (_owner._batch != this) return;
    _owner._batch = null;
    _owner.onBatchLockChanged?.call(false);
    if (!_owner.isClosed) _owner.update();
  }
}
