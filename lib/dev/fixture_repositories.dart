import 'dart:async';
import 'dart:typed_data';

import '../domain/contracts/contracts.dart';
import '../domain/models/models.dart';
import 'fixture_controls.dart';
import 'fixture_scenarios.dart';
import 'fixture_source.dart';

/// Memory-only dev repository. Explicit stale controls replace TTL/disk policy.
final class FixtureNovelRepository implements NovelRepository {
  FixtureNovelRepository(this.source) {
    _details = _FixtureCache(Operation.novelDetail, source.getNovelDetail);
    _catalogs = _FixtureCache(Operation.catalog, source.getCatalog);
    _chapters = _FixtureCache(Operation.chapter, source.getChapter);
  }
  final FixtureNovelSource source;
  late final _FixtureCache<NovelKey, NovelDetail> _details;
  late final _FixtureCache<NovelKey, Catalog> _catalogs;
  late final _FixtureCache<ChapterKey, ChapterContent> _chapters;
  bool _closed = false;
  void _check() {
    if (_closed) throw StateError('Repository closed');
  }

  void markStale() {
    _check();
    _details.markStale();
    _catalogs.markStale();
    _chapters.markStale();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await Future.wait([_details.close(), _catalogs.close(), _chapters.close()]);
  }

  @override
  Future<Result<List<DiscoverSection>>> discover(
    SourceId sourceId, {
    required CancellationToken cancellation,
  }) {
    _check();
    return cancellation.isCancelled
        ? Future.value(fixtureCancelled(Operation.discover))
        : sourceId == fixtureSourceId
        ? source.discover(cancellation: cancellation)
        : Future.value(
            fixtureFailure(Operation.discover, FailureKind.unsupported),
          );
  }

  @override
  Future<Result<SearchPage>> search(
    SourceId sourceId,
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) {
    _check();
    return cancellation.isCancelled
        ? Future.value(fixtureCancelled(Operation.search))
        : sourceId == fixtureSourceId
        ? source.search(query, cursor: cursor, cancellation: cancellation)
        : Future.value(
            fixtureFailure(Operation.search, FailureKind.unsupported),
          );
  }

  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => _details.load(key, mode, cancellation);
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => _catalogs.load(key, mode, cancellation);
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => _chapters.load(key, mode, cancellation);
  @override
  Stream<Result<LoadResult<NovelDetail>>> detailUpdates(NovelKey key) =>
      _details.updates(key);
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      _catalogs.updates(key);
  @override
  Stream<Result<LoadResult<ChapterContent>>> chapterUpdates(ChapterKey key) =>
      _chapters.updates(key);
}

typedef _Fetch<K, T> =
    Future<Result<T>> Function(
      K key, {
      required CancellationToken cancellation,
    });

final class _FixtureCache<K, T> {
  _FixtureCache(this.operation, this.fetch);
  final Operation operation;
  final _Fetch<K, T> fetch;
  final _values = <K, LoadResult<T>>{};
  final _streams = <K, StreamController<Result<LoadResult<T>>>>{};
  final _pending = <K, Future<Result<LoadResult<T>>>>{};
  final _lifetime = CancellationSource();
  int _tick = 0;
  void _check() {
    if (_lifetime.token.isCancelled) throw StateError('Repository closed');
  }

  Stream<Result<LoadResult<T>>> updates(K key) {
    _check();
    return (_streams[key] ??=
            StreamController<Result<LoadResult<T>>>.broadcast())
        .stream;
  }

  void markStale() {
    _check();
    for (final entry in _values.entries.toList()) {
      final old = entry.value;
      _values[entry.key] = LoadResult(
        value: old.value,
        origin: LoadOrigin.memory,
        fetchedAt: old.fetchedAt,
        isStale: true,
        refreshFailure: old.refreshFailure,
      );
    }
  }

  Future<Result<LoadResult<T>>> load(
    K key,
    ReadMode mode,
    CancellationToken token,
  ) async {
    _check();
    if (token.isCancelled) return fixtureCancelled(operation);
    final old = _values[key];
    if (mode == ReadMode.cacheOnly) {
      return old == null
          ? fixtureFailure(
              operation,
              FailureKind.cache,
              context: FailureContext.cacheMiss,
            )
          : Success(old);
    }
    if (mode == ReadMode.cacheFirst && old != null) {
      if (old.isStale) unawaited(_refresh(key));
      return Success(old);
    }
    return fixtureForCaller(_refresh(key), token, operation);
  }

  Future<Result<LoadResult<T>>> _refresh(K key) =>
      _pending[key] ??= _fetch(key).whenComplete(() {
        _pending.remove(key);
      });
  Future<Result<LoadResult<T>>> _fetch(K key) async {
    final response = await fetch(key, cancellation: _lifetime.token);
    if (_lifetime.token.isCancelled) return fixtureCancelled(operation);
    final Result<LoadResult<T>> result;
    switch (response) {
      case Success(:final value):
        final fetchedAt = fixtureEpoch.add(Duration(milliseconds: _tick++));
        _values[key] = LoadResult(
          value: value,
          origin: LoadOrigin.memory,
          fetchedAt: fetchedAt,
        );
        result = Success(
          LoadResult(
            value: value,
            origin: LoadOrigin.remote,
            fetchedAt: fetchedAt,
          ),
        );
      case Failure(:final failure):
        if (failure.isCancellation) return Failure(failure);
        final old = _values[key];
        if (old == null) {
          result = Failure(failure);
        } else {
          final stale = LoadResult(
            value: old.value,
            origin: LoadOrigin.memory,
            fetchedAt: old.fetchedAt,
            isStale: true,
            refreshFailure: failure,
          );
          _values[key] = stale;
          result = Success(stale);
        }
    }
    _streams[key]?.add(result);
    return result;
  }

  Future<void> close() async {
    if (_lifetime.token.isCancelled) return;
    _lifetime.cancel();
    await Future.wait(_pending.values.toList());
    _values.clear();
    await Future.wait(_streams.values.map((stream) => stream.close()));
  }
}

final class FixtureImageRepository implements ImageRepository {
  FixtureImageRepository(this.source, {this.maxBytes = 1024 * 1024}) {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  }
  final FixtureNovelSource source;
  final int maxBytes;
  final _cache = <MediaRef, LoadResult<MemoryMedia>>{};
  final _lifetime = CancellationSource();
  final _active = <CancellationSource>{};
  final _background = <MediaRef>{};
  int _tick = 0;
  void close() {
    _lifetime.cancel();
    for (final request in _active) {
      request.cancel();
    }
    _cache.clear();
  }

  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    if (_lifetime.token.isCancelled) throw StateError('Repository closed');
    if (cancellation.isCancelled) return fixtureCancelled(Operation.media);
    final old = _cache[ref];
    if (mode != ReadMode.refresh && old != null) {
      if (mode == ReadMode.cacheFirst && old.isStale && _background.add(ref)) {
        // Media has no update stream: retain the caller's old independent lease;
        // a later load observes the refreshed bytes. Close the background lease.
        unawaited(
          load(ref, mode: ReadMode.refresh, cancellation: _lifetime.token)
              .then((result) async {
                if (result case Success(:final value)) {
                  await value.value.close();
                }
              })
              .whenComplete(() {
                _background.remove(ref);
              }),
        );
      }
      return Success(_lease(old));
    }
    if (mode == ReadMode.cacheOnly) {
      return fixtureFailure(
        Operation.media,
        FailureKind.cache,
        context: FailureContext.cacheMiss,
      );
    }
    final request = CancellationSource();
    _active.add(request);
    unawaited(cancellation.whenCancelled.then((_) => request.cancel()));
    SourceMediaBody? body;
    try {
      final opened = await source.openMedia(
        ref,
        maxBytes: maxBytes,
        cancellation: request.token,
      );
      if (opened case Failure(:final failure)) {
        return _failed(ref, old, failure);
      }
      body = (opened as Success<SourceMediaBody>).value;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.chunks) {
        if (_lifetime.token.isCancelled || cancellation.isCancelled) {
          return fixtureCancelled(Operation.media);
        }
        switch (chunk) {
          case Success(:final value):
            bytes.add(value);
          case Failure(:final failure):
            return _failed(ref, old, failure);
        }
      }
      if (_lifetime.token.isCancelled || cancellation.isCancelled) {
        return fixtureCancelled(Operation.media);
      }
      final result = LoadResult(
        value: MemoryMedia(bytes: bytes.takeBytes(), info: body.info),
        origin: LoadOrigin.memory,
        fetchedAt: fixtureEpoch.add(Duration(milliseconds: _tick++)),
      );
      _cache[ref] = result;
      return Success(_lease(result, origin: LoadOrigin.remote));
    } finally {
      await body?.close();
      request.cancel();
      _active.remove(request);
    }
  }

  Result<LoadResult<MediaLease>> _failed(
    MediaRef ref,
    LoadResult<MemoryMedia>? old,
    AppFailure failure,
  ) {
    if (old == null || failure.isCancellation) return Failure(failure);
    final stale = LoadResult(
      value: old.value,
      origin: LoadOrigin.memory,
      fetchedAt: old.fetchedAt,
      isStale: true,
      refreshFailure: failure,
    );
    _cache[ref] = stale;
    return Success(_lease(stale));
  }

  LoadResult<MediaLease> _lease(
    LoadResult<MemoryMedia> value, {
    LoadOrigin origin = LoadOrigin.memory,
  }) => LoadResult(
    value: FixtureMediaLease(value.value),
    origin: origin,
    fetchedAt: value.fetchedAt,
    isStale: value.isStale,
    refreshFailure: value.refreshFailure,
  );
}

final class FixtureMediaLease implements MediaLease {
  FixtureMediaLease(MemoryMedia data) : _data = data;
  MemoryMedia? _data;
  @override
  MediaData get data => _data ?? (throw StateError('Lease closed'));
  @override
  MediaPersistence get persistence => MediaPersistence.memoryOnly;
  @override
  AppFailure? get persistenceFailure => null;
  @override
  bool get isClosed => _data == null;
  @override
  Future<void> close() async {
    _data = null;
  }
}
