import 'dart:async';

import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';

import 'fixture_controls.dart';

/// Development-only in-memory library; no durable DB or restart guarantee.
final class FixtureLibraryRepository implements LibraryRepository {
  final _books = <NovelKey, BookshelfEntry>{};
  final _progress = <NovelKey, ReadingProgress>{};
  final _generations = <NovelKey, int>{};
  final _sequences = <NovelKey, int>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  final controls = FixtureControls();
  bool _closed = false;
  void _check() {
    if (_closed) throw StateError('Library closed');
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _changes.close();
  }

  Stream<Result<List<T>>> _watch<T>(List<T> Function() snapshot) =>
      Stream.multi((sink) {
        _check();
        final subscription = _changes.stream.listen(
          (_) => sink.add(Success(List.unmodifiable(snapshot()))),
          onDone: sink.close,
        );
        sink.add(Success(List.unmodifiable(snapshot())));
        sink.onCancel = subscription.cancel;
      });
  int _keyOrder(NovelKey a, NovelKey b) {
    final source = a.sourceId.value.compareTo(b.sourceId.value);
    return source != 0 ? source : a.novelId.compareTo(b.novelId);
  }

  @override
  Stream<Result<List<BookshelfEntry>>> watchBookshelf() => _watch(
    () => _books.values.toList()
      ..sort((a, b) {
        final date = (_progress[b.snapshot.key]?.lastReadAt ?? b.addedAt)
            .compareTo(_progress[a.snapshot.key]?.lastReadAt ?? a.addedAt);
        return date != 0 ? date : _keyOrder(a.snapshot.key, b.snapshot.key);
      }),
  );
  @override
  Stream<Result<List<ReadingProgress>>> watchRecentReading() => _watch(
    () => _progress.values.toList()
      ..sort((a, b) {
        final date = b.lastReadAt.compareTo(a.lastReadAt);
        return date != 0 ? date : _keyOrder(a.novelKey, b.novelKey);
      }),
  );
  @override
  Future<Result<BookshelfEntry>> putBookshelf(
    BookshelfEntry entry, {
    required CancellationToken cancellation,
  }) async {
    _check();
    final failure = await controls.before(Operation.libraryWrite, cancellation);
    _check();
    if (failure != null) return Failure(failure);
    final existing = _books[entry.snapshot.key];
    final saved = BookshelfEntry(
      snapshot: entry.snapshot,
      addedAt: existing?.addedAt ?? entry.addedAt,
    );
    _books[entry.snapshot.key] = saved;
    _changes.add(null);
    return Success(saved);
  }

  @override
  Future<Result<BookshelfEntry?>> removeFromBookshelf(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    _check();
    final failure = await controls.before(Operation.libraryWrite, cancellation);
    _check();
    if (failure != null) return Failure(failure);
    final removed = _books.remove(key);
    _changes.add(null);
    return Success(removed);
  }

  @override
  Future<Result<ReadingProgress?>> getProgress(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    _check();
    final failure = await controls.before(Operation.progressRead, cancellation);
    _check();
    return failure == null ? Success(_progress[key]) : Failure(failure);
  }

  @override
  Future<Result<int>> beginProgressSession(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    _check();
    final failure = await controls.before(
      Operation.progressWrite,
      cancellation,
    );
    _check();
    if (failure != null) return Failure(failure);
    final next = (_generations[key] ?? 0) + 1;
    _generations[key] = next;
    _sequences.remove(key);
    return Success(next);
  }

  @override
  Future<Result<bool>> saveProgress(
    ReadingProgress progress, {
    required ProgressWriteStamp stamp,
    required CancellationToken cancellation,
  }) async {
    _check();
    final failure = await controls.before(
      Operation.progressWrite,
      cancellation,
    );
    _check();
    if (failure != null) return Failure(failure);
    final key = progress.novelKey;
    if (_generations[key] != stamp.generation ||
        stamp.sequence <= (_sequences[key] ?? -1)) {
      return const Success(false);
    }
    _sequences[key] = stamp.sequence;
    _progress[key] = progress;
    _changes.add(null);
    return const Success(true);
  }

  @override
  Future<Result<void>> clearHistory(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    _check();
    final failure = await controls.before(
      Operation.progressWrite,
      cancellation,
    );
    _check();
    if (failure != null) return Failure(failure);
    _progress.remove(key);
    _generations[key] = (_generations[key] ?? 0) + 1;
    _sequences.remove(key);
    _changes.add(null);
    return const Success(null);
  }
}
