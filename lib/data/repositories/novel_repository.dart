import 'dart:async';
import '../network/background_work.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/app_logger.dart';
import '../local/novel_record_store.dart';
import '../local/database/cache_database.dart';
import '../cache/cache_policy.dart';
import '../sources/source_registry.dart';

/// Explicit composition for an already-owned cache database and Source registry.
DefaultNovelRepository createNovelRepository({
  required SourceRegistry sources,
  required CacheDatabase cache,
  DateTime Function()? now,
  AppLogger? logger,
  CacheCoordinator? coordinator,
}) => DefaultNovelRepository(
  sources: sources,
  records: NovelRecordStore(cache, coordinator: coordinator),
  now: now,
  coordinator: coordinator,
  logger: logger,
);

/// Borrows records and sources. Close before closing the database/transport.
/// No process-wide cache or production Source registration is implicit.
final class DefaultNovelRepository implements NovelRepository {
  DefaultNovelRepository({
    required this.sources,
    required NovelRecordStore records,
    DateTime Function()? now,
    AppLogger? logger,
    CacheCoordinator? coordinator,
  }) : _logger = logger ?? AppLogger() {
    final clock = now ?? DateTime.now;
    _details = _Records(
      operation: Operation.novelDetail,
      now: clock,
      coordinator: coordinator,
      logger: _logger,
      read: (key, token) => records.readDetail(key, cancellation: token),
      fetch: (key, token) => _source(
        key.sourceId,
        Operation.novelDetail,
        token,
        (source) => source.getNovelDetail(key, cancellation: token),
        (value) => value.summary.key == key,
      ),
      write: (value, time, token) => records.writeDetail(
        value,
        fetchedAt: time,
        expiresAt: time.add(
          (coordinator?.policy ?? const CachePolicy()).detailTtl,
        ),
        parserVersion: 1,
        cancellation: token,
      ),
    );
    _catalogs = _Records(
      operation: Operation.catalog,
      now: clock,
      coordinator: coordinator,
      logger: _logger,
      read: (key, token) => records.readCatalog(key, cancellation: token),
      fetch: (key, token) => _source(
        key.sourceId,
        Operation.catalog,
        token,
        (source) => source.getCatalog(key, cancellation: token),
        (value) => value.novelKey == key,
      ),
      write: (value, time, token) => records.writeCatalog(
        value,
        fetchedAt: time,
        expiresAt: time.add(
          (coordinator?.policy ?? const CachePolicy()).catalogTtl,
        ),
        parserVersion: 1,
        cancellation: token,
      ),
    );
    _chapters = _Records(
      operation: Operation.chapter,
      now: clock,
      coordinator: coordinator,
      logger: _logger,
      read: (key, token) => records.readChapter(key, cancellation: token),
      fetch: (key, token) => _source(
        key.novelKey.sourceId,
        Operation.chapter,
        token,
        (source) => source.getChapter(key, cancellation: token),
        (value) => value.key == key,
      ),
      write: (value, time, token) => records.writeChapter(
        value,
        fetchedAt: time,
        parserVersion: 2,
        cancellation: token,
      ),
    );
  }
  final SourceRegistry sources;
  final AppLogger _logger;
  final _lifetime = CancellationSource();
  late final _Records<NovelKey, NovelDetail> _details;
  late final _Records<NovelKey, Catalog> _catalogs;
  late final _Records<ChapterKey, ChapterContent> _chapters;
  Future<void>? _closing;
  final _pending = <Future<void>>{};
  Future<Result<T>> _track<T>(Future<Result<T>> work) {
    final done = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _pending.add(done);
    unawaited(done.whenComplete(() => _pending.remove(done)));
    return work;
  }

  Future<Result<T>> _source<T>(
    SourceId id,
    Operation operation,
    CancellationToken token,
    Future<Result<T>> Function(NovelSource) call,
    bool Function(T) belongs,
  ) async {
    if (token.isCancelled || _lifetime.token.isCancelled) {
      return Failure(AppFailure.cancelled(operation));
    }
    final source = sources[id];
    if (source == null) {
      return Failure(
        AppFailure(
          kind: FailureKind.sourceUnavailable,
          operation: operation,
          context: FailureContext.sourceMissing,
        ),
      );
    }
    try {
      final result = await call(source);
      if (token.isCancelled || _lifetime.token.isCancelled) {
        return Failure(AppFailure.cancelled(operation));
      }
      if (result case Success<T>(:final value)) {
        if (!belongs(value)) {
          return Failure(
            AppFailure(
              kind: FailureKind.parse,
              operation: operation,
              context: FailureContext.invalidContent,
            ),
          );
        }
      }
      return result;
    } catch (_) {
      return Failure(
        AppFailure(kind: FailureKind.sourceUnavailable, operation: operation),
      );
    }
  }

  Future<Result<T>> _query<T>(
    CancellationToken token,
    Operation operation,
    Future<Result<T>> Function(CancellationToken) run,
  ) async {
    final linked = CancellationSource();
    if (token.isCancelled || _lifetime.token.isCancelled) linked.cancel();
    final a = token.whenCancelled.asStream().listen((_) => linked.cancel());
    final b = _lifetime.token.whenCancelled.asStream().listen(
      (_) => linked.cancel(),
    );
    try {
      return await _wait(_track(run(linked.token)), linked.token, operation);
    } finally {
      await a.cancel();
      await b.cancel();
    }
  }

  @override
  Future<Result<List<DiscoverSection>>> discover(
    SourceId sourceId, {
    required CancellationToken cancellation,
  }) => _query(
    cancellation,
    Operation.discover,
    (token) => _source(
      sourceId,
      Operation.discover,
      token,
      (source) => source.descriptor.supportsDiscover
          ? source
                .discover(cancellation: token)
                .then(
                  (result) => result.map(
                    (items) => List<DiscoverSection>.unmodifiable(items),
                  ),
                )
          : Future.value(
              Failure(
                AppFailure(
                  kind: FailureKind.unsupported,
                  operation: Operation.discover,
                ),
              ),
            ),
      (value) => value.every(
        (section) =>
            section.items.every((item) => item.key.sourceId == sourceId),
      ),
    ),
  );
  @override
  Future<Result<SearchPage>> search(
    SourceId sourceId,
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) => _query(cancellation, Operation.search, (token) {
    if (cursor != null && cursor.sourceId != sourceId) {
      return Future.value(
        Failure(
          AppFailure(
            kind: FailureKind.parse,
            operation: Operation.search,
            context: FailureContext.invalidCursor,
          ),
        ),
      );
    }
    return _source(
      sourceId,
      Operation.search,
      token,
      (source) => source.search(query, cursor: cursor, cancellation: token),
      (value) => value.sourceId == sourceId,
    );
  });
  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => _track(_details.load(key, mode, cancellation));
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => _track(_catalogs.load(key, mode, cancellation));
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => _track(_chapters.load(key, mode, cancellation));
  @override
  Stream<Result<LoadResult<NovelDetail>>> detailUpdates(NovelKey key) =>
      _details.updates(key);
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      _catalogs.updates(key);
  @override
  Stream<Result<LoadResult<ChapterContent>>> chapterUpdates(ChapterKey key) =>
      _chapters.updates(key);

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _lifetime.cancel();
    await Future.wait([
      _details.close(),
      _catalogs.close(),
      _chapters.close(),
      ..._pending,
    ]);
  }
}

Future<Result<T>> _wait<T>(
  Future<Result<T>> work,
  CancellationToken token,
  Operation operation,
) async {
  final cancelled = Completer<Result<T>>();
  final subscription = token.whenCancelled.asStream().listen((_) {
    cancelled.complete(Failure(AppFailure.cancelled(operation)));
  });
  try {
    if (token.isCancelled) return Failure(AppFailure.cancelled(operation));
    final result = await Future.any([work, cancelled.future]);
    return token.isCancelled
        ? Failure(AppFailure.cancelled(operation))
        : result;
  } finally {
    await subscription.cancel();
  }
}

final class _Job<T> {
  final scope = BackgroundWork.current;
  final cancellation = CancellationSource();
  late Future<Result<LoadResult<T>>> result;
  int readers = 0;
  bool background = false;
}

/// Only in-flight work is retained. Persistent expiry metadata is honored;
/// selecting TTLs and capacity/eviction belongs to CACHE-001/002.
final class _Records<K, T> {
  _Records({
    this.coordinator,
    required this.operation,
    required this.now,
    required this.logger,
    required this.read,
    required this.fetch,
    required this.write,
  }) {
    _clears = coordinator?.clears.listen((_) {
      for (final job in _jobs.values) {
        job.cancellation.cancel();
      }
    });
  }
  StreamSubscription<void>? _clears;
  final CacheCoordinator? coordinator;
  final Operation operation;
  final DateTime Function() now;
  final AppLogger logger;
  final Future<Result<StoredRecord<T>?>> Function(K, CancellationToken) read;
  final Future<Result<T>> Function(K, CancellationToken) fetch;
  final Future<Result<void>> Function(T, DateTime, CancellationToken) write;
  final _jobs = <K, _Job<T>>{};
  final _events = StreamController<(K, Result<LoadResult<T>>)>.broadcast();
  final _lifetime = CancellationSource();
  Stream<Result<LoadResult<T>>> updates(K key) =>
      _events.stream.where((event) => event.$1 == key).map((event) => event.$2);
  bool _stale(StoredRecord<T> record) {
    final policy = coordinator?.policy ?? const CachePolicy();
    final expiry =
        record.expiresAt ??
        switch (operation) {
          Operation.novelDetail => record.fetchedAt.add(policy.detailTtl),
          Operation.catalog => record.fetchedAt.add(policy.catalogTtl),
          _ => null,
        };
    return record.parserVersion != (operation == Operation.chapter ? 2 : 1) ||
        (expiry != null && !now().toUtc().isBefore(expiry));
  }

  LoadResult<T> _local(StoredRecord<T> record, {AppFailure? failure}) =>
      LoadResult(
        value: record.value,
        origin: LoadOrigin.local,
        fetchedAt: record.fetchedAt,
        isStale: failure != null || _stale(record),
        refreshFailure: failure,
      );

  Future<Result<LoadResult<T>>> load(
    K key,
    ReadMode mode,
    CancellationToken token,
  ) async {
    if (token.isCancelled || _lifetime.token.isCancelled) {
      return Failure(AppFailure.cancelled(operation));
    }
    final generation = coordinator?.generation;
    Result<StoredRecord<T>?> cached;
    try {
      cached = await read(key, token);
    } catch (_) {
      cached = Failure(
        AppFailure(
          kind: FailureKind.cache,
          operation: operation,
          context: FailureContext.invalidContent,
        ),
      );
    }
    if (token.isCancelled ||
        _lifetime.token.isCancelled ||
        coordinator?.generation != generation) {
      return Failure(AppFailure.cancelled(operation));
    }
    final record = switch (cached) {
      Success(:final value) => value,
      _ => null,
    };
    if (cached case Failure(:final failure)) {
      if (failure.isCancellation || mode == ReadMode.cacheOnly) {
        return Failure(failure);
      }
      logger.local(failure);
    }
    if (mode == ReadMode.cacheOnly) {
      return record == null
          ? Failure(
              AppFailure(
                kind: FailureKind.cache,
                operation: operation,
                context: FailureContext.cacheMiss,
              ),
            )
          : Success(_local(record));
    }
    if (mode == ReadMode.cacheFirst && record != null) {
      if (_stale(record)) {
        unawaited(_refresh(key, record, token, background: true));
      }
      return Success(_local(record));
    }
    return _refresh(key, record, token);
  }

  Future<Result<LoadResult<T>>> _refresh(
    K key,
    StoredRecord<T>? record,
    CancellationToken token, {
    bool background = false,
  }) async {
    // A cancelled generation must settle before another can write this key.
    final previous = _jobs[key];
    if (previous != null && previous.cancellation.token.isCancelled) {
      await _wait(previous.result, token, operation);
    }
    if (token.isCancelled || _lifetime.token.isCancelled) {
      return Failure(AppFailure.cancelled(operation));
    }
    var job = _jobs[key];
    if (job == null) {
      job = _Job<T>();
      _jobs[key] = job;
      final current = job;
      job.result = _run(key, record, current).whenComplete(() {
        if (identical(_jobs[key], current)) _jobs.remove(key);
      });
    }
    BackgroundWork.promote(job.scope);
    job.background |= background;
    if (background) return job.result;
    job.readers++;
    try {
      return await _wait(job.result, token, operation);
    } finally {
      job.readers--;
      if (job.readers == 0 && !job.background) job.cancellation.cancel();
    }
  }

  Future<Result<LoadResult<T>>> _run(
    K key,
    StoredRecord<T>? record,
    _Job<T> job,
  ) async {
    final token = job.cancellation.token;
    final generation = coordinator?.generation;
    Result<T> remote;
    try {
      remote = await fetch(key, token);
    } catch (_) {
      remote = Failure(
        AppFailure(kind: FailureKind.sourceUnavailable, operation: operation),
      );
    }
    if (token.isCancelled) return Failure(AppFailure.cancelled(operation));
    if (coordinator?.generation != generation) {
      return Failure(AppFailure.cancelled(operation));
    }
    Result<LoadResult<T>> result;
    switch (remote) {
      case Failure(:final failure):
        result = record != null && !failure.isCancellation
            ? Success(_local(record, failure: failure))
            : Failure(failure);
      case Success(:final value):
        final time = now().toUtc();
        try {
          final saved = await write(value, time, token);
          if (saved case Failure(:final failure)) logger.local(failure);
        } catch (_) {
          logger.local(
            AppFailure(
              kind: FailureKind.cache,
              operation: operation,
              context: FailureContext.cacheWriteFailed,
            ),
          );
        }
        result = Success(
          LoadResult(value: value, origin: LoadOrigin.remote, fetchedAt: time),
        );
    }
    if (token.isCancelled) return Failure(AppFailure.cancelled(operation));
    if (result case Failure(:final failure) when failure.isCancellation) {
      return result;
    }
    if (coordinator?.generation != generation) {
      return Failure(AppFailure.cancelled(operation));
    }
    if (!_events.isClosed) _events.add((key, result));
    return result;
  }

  Future<void> close() async {
    _lifetime.cancel();
    final jobs = _jobs.values.toList();
    for (final job in jobs) {
      job.cancellation.cancel();
    }
    await _clears?.cancel();
    await Future.wait(jobs.map((job) => job.result));
    // Do not wait for paused listeners to resume before the owner can close DB.
    unawaited(_events.close());
  }
}
