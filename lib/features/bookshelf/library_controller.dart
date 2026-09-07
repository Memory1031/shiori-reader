import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/controllers/scoped_controller.dart';

class LibraryController extends ScopedController {
  LibraryController(this.repository);
  final LibraryRepository repository;
  List<BookshelfEntry> books = const [];
  List<ReadingProgress> recent = const [];
  AppFailure? shelfFailure, historyFailure, writeFailure;
  bool shelfReady = false, historyReady = false, writing = false;
  BookshelfEntry? removed;
  @override
  void onInit() {
    super.onInit();
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
  Future<bool> remove(NovelKey key) => _write(
    () => repository.removeFromBookshelf(key, cancellation: cancellation),
    (value) => removed = value,
  );
  Future<bool> undo() async {
    final entry = removed;
    if (entry == null) return false;
    return _write(
      () => repository.putBookshelf(entry, cancellation: cancellation),
      (_) => removed = null,
    );
  }

  Future<bool> clearHistory(NovelKey key) => _write(
    () => repository.clearHistory(key, cancellation: cancellation),
    (_) {},
  );
}
