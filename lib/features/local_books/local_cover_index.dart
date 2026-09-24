import 'dart:async';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';

/// Cover references of imported books, resolved once per app run. Reading a
/// cover reference means decoding the book's manifest, so the index outlives
/// any one visit to the local files page. It listens for reparse and
/// deletion events itself, so entries stay correct while no page is open.
/// The owner must [close] it.
class LocalCoverIndex {
  LocalCoverIndex(this.store) {
    if (store case LocalBookInvalidation changes) {
      _changes = changes.changes.listen(_invalidate);
    }
  }

  final LocalBookStore store;
  final _covers = <NovelKey, MediaRef?>{};
  final _pending = <NovelKey, Future<MediaRef?>>{};
  final _revisions = <NovelKey, int>{};
  final _invalidated = StreamController<NovelKey>.broadcast();
  StreamSubscription<NovelKey>? _changes;
  bool _closed = false;

  /// Emits a key after its cover may have changed.
  Stream<NovelKey> get invalidations => _invalidated.stream;

  /// Whether [key] is resolved (possibly to no cover).
  bool contains(NovelKey key) => _covers.containsKey(key);
  MediaRef? operator [](NovelKey key) => _covers[key];

  /// Resolves [key]'s cover, sharing one read between concurrent callers.
  /// Failures are not remembered, so a later call retries.
  Future<MediaRef?> resolve(NovelKey key) {
    if (_covers.containsKey(key)) return Future.value(_covers[key]);
    if (_pending[key] case final pending?) return pending;
    late final Future<MediaRef?> read;
    read = _read(key).whenComplete(() {
      if (identical(_pending[key], read)) _pending.remove(key);
    });
    return _pending[key] = read;
  }

  Future<MediaRef?> _read(NovelKey key) async {
    final revision = _revisions[key] ?? 0;
    // The index owns this read; rows that stop listening do not cancel it.
    final result = await store.read(
      key,
      cancellation: CancellationSource().token,
    );
    final cover = switch (result) {
      Success(value: final book?) => book.content.detail.summary.cover,
      _ => null,
    };
    // A reparse during the read makes its answer stale; do not keep it.
    if (!_closed && result is Success && revision == (_revisions[key] ?? 0)) {
      _covers[key] = cover;
    }
    return cover;
  }

  void _invalidate(NovelKey key) {
    _covers.remove(key);
    _pending.remove(key);
    _revisions[key] = (_revisions[key] ?? 0) + 1;
    if (!_closed) _invalidated.add(key);
  }

  Future<void> close() async {
    _closed = true;
    await _changes?.cancel();
    await _invalidated.close();
  }
}
