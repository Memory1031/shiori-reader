import '../errors/app_failure.dart';

enum ReadMode { cacheFirst, refresh, cacheOnly }

enum LoadOrigin { memory, local, remote }

/// Immutable observation; a background refresh produces a new result/event.
final class LoadResult<T> {
  LoadResult({
    required this.value,
    required this.origin,
    required DateTime fetchedAt,
    this.isStale = false,
    this.refreshFailure,
  }) : fetchedAt = fetchedAt.toUtc() {
    if (refreshFailure != null &&
        (!isStale ||
            origin == LoadOrigin.remote ||
            refreshFailure!.isCancellation)) {
      throw ArgumentError('Refresh failure needs retained stale cache data');
    }
    if (isStale && origin == LoadOrigin.remote) {
      throw ArgumentError('A new remote result cannot be stale cache');
    }
  }
  final T value;
  final LoadOrigin origin;
  final DateTime fetchedAt;
  final bool isStale;
  final AppFailure? refreshFailure;
}
