import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/controllers/scoped_controller.dart';

class LibraryController extends ScopedController {
  LibraryController(this.repository, {this.cache, this.localBooks});
  final LocalBookManagement? localBooks;
  bool localCleanupPending = false;
  Map<NovelKey, LocalBookFormat> localFormats = const {};
  final CacheManagement? cache;
  final LibraryRepository repository;
  List<BookshelfEntry> books = const [];
  List<ReadingProgress> recent = const [];
  AppFailure? shelfFailure, historyFailure, writeFailure;
  bool shelfReady = false, historyReady = false, writing = false;
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
          historyFailure = null;
        case Failure(:final failure):
          historyFailure = failure;
      }
      update();
    });
  }

  bool contains(NovelKey key) => books.any((b) => b.snapshot.key == key);
  ReadingProgress? progressFor(NovelKey key) {
    for (final item in recent) {
      if (item.novelKey == key) return item;
    }
    return null;
  }

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
    writing = true;
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
    writing = false;
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
  Future<bool> remove(NovelKey key) {
    if (key.sourceId == LocalBookIdentity.sourceId) {
      return _write<LocalBookDeletion>(() async {
        final management = localBooks;
        if (management == null) {
          return Failure(
            AppFailure(
              kind: FailureKind.unsupported,
              operation: Operation.libraryWrite,
            ),
          );
        }
        return management.deleteBook(key, cancellation: cancellation);
      }, (result) => localCleanupPending = result.cleanupPending);
    }
    return _write(() async {
      // Keep the entry available for retry if cache cleanup fails. These stores
      // cannot share a transaction; a later library failure may leave no cache.
      final management = cache;
      if (management != null) {
        final cleared = await management.clear(novel: key);
        if (cleared case Failure(:final failure)) {
          return Failure<BookshelfEntry?>(failure);
        }
      }
      return repository.removeFromBookshelf(key, cancellation: cancellation);
    }, (_) {});
  }

  Future<bool> clearHistory(NovelKey key) => _write(
    () => repository.clearHistory(key, cancellation: cancellation),
    (_) {},
  );
}
