import 'dart:async';

/// Payload budgets are independent of SQLite allocation and decoded image RAM.
class CachePolicy {
  const CachePolicy({
    this.textBytes = 64 * 1024 * 1024,
    this.imageBytes = 192 * 1024 * 1024,
    this.detailTtl = const Duration(hours: 24),
    this.catalogTtl = const Duration(hours: 1),
    this.backgroundBytes = 64 * 1024 * 1024,
    this.backgroundAttempts = 200,
  });
  final int textBytes, imageBytes, backgroundBytes, backgroundAttempts;
  final Duration detailTtl, catalogTtl;
  int target(int limit) => (limit * .8).floor();
}

/// One owner for cache generations, pins and serialized disk mutations.
/// Clearing advances the generation synchronously, before waiting for disk IO.
class CacheCoordinator {
  CacheCoordinator({
    this.policy = const CachePolicy(),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final CachePolicy policy;
  final DateTime Function() now;
  int generation = 0;
  final _pins = <String, int>{};
  final _clears = StreamController<void>.broadcast(sync: true);
  Stream<void> get clears => _clears.stream;
  Future<void> _tail = Future.value();
  bool isPinned(String id) => (_pins[id] ?? 0) > 0;
  void Function() pin(String id) {
    _pins[id] = (_pins[id] ?? 0) + 1;
    var closed = false;
    return () {
      if (closed) return;
      closed = true;
      final count = (_pins[id] ?? 1) - 1;
      if (count == 0) {
        _pins.remove(id);
      } else {
        _pins[id] = count;
      }
    };
  }

  int invalidate() {
    generation++;
    _clears.add(null);
    return generation;
  }

  Future<T> exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> close() async {
    await _tail;
    await _clears.close();
  }
}
