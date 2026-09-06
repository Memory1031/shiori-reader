import 'dart:async';
import 'dart:typed_data';

import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';

// Minimal contract examples only: no DEV-001 scenario catalog, network or DB.
final contractSourceId = SourceId('contract-fixture');
final contractNovel = NovelKey(sourceId: contractSourceId, novelId: 'book');
final contractChapter = ChapterKey(
  novelKey: contractNovel,
  chapterId: 'chapter',
);
final contractMedia = MediaRef(sourceId: contractSourceId, mediaId: 'image');
final contractNow = DateTime.utc(2026, 9, 7);
ChapterContent contractContent(String text) => ChapterContent(
  key: contractChapter,
  title: '合成章',
  blocks: [ParagraphBlock(text: text)],
);

Failure<T> unsupported<T>(Operation operation) =>
    Failure(AppFailure(kind: FailureKind.unsupported, operation: operation));
Failure<T> cancelled<T>(Operation operation) =>
    Failure(AppFailure.cancelled(operation));

Future<Result<T>> forCaller<T>(
  Future<Result<T>> work,
  CancellationToken token,
  Operation operation,
) async {
  if (token.isCancelled) return cancelled(operation);
  final result = await Future.any([
    work,
    token.whenCancelled.then((_) => cancelled<T>(operation)),
  ]);
  return token.isCancelled ? cancelled(operation) : result;
}

final class ContractSource implements NovelSource, SourceMedia {
  int chapterCalls = 0;
  int mediaCalls = 0;
  Completer<Result<ChapterContent>>? pendingChapter;
  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    sourceId: contractSourceId,
    displayName: '合成契约源',
    supportsDiscover: false,
    supportsSearchPaging: true,
  );
  @override
  Future<Result<List<DiscoverSection>>> discover({
    required CancellationToken cancellation,
  }) async => cancellation.isCancelled
      ? cancelled(Operation.discover)
      : unsupported(Operation.discover);
  @override
  Future<Result<SearchPage>> search(
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) async {
    if (cancellation.isCancelled) return cancelled(Operation.search);
    final normalized = query
        .trim(); // Source-owned policy, not a UI page counter.
    if (cursor != null &&
        (cursor.sourceId != contractSourceId ||
            cursor.opaqueValue != 'next:$normalized')) {
      return Failure(
        AppFailure(
          kind: FailureKind.parse,
          operation: Operation.search,
          context: FailureContext.invalidCursor,
        ),
      );
    }
    if (normalized.isEmpty || cursor != null) {
      return Success(SearchPage(sourceId: contractSourceId, items: []));
    }
    return Success(
      SearchPage(
        sourceId: contractSourceId,
        items: [NovelSummary(key: contractNovel, title: '合成小说')],
        nextCursor: SearchCursor(
          sourceId: contractSourceId,
          opaqueValue: 'next:$normalized',
        ),
      ),
    );
  }

  @override
  Future<Result<NovelDetail>> getNovelDetail(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async => cancellation.isCancelled
      ? cancelled(Operation.novelDetail)
      : unsupported(Operation.novelDetail);
  @override
  Future<Result<Catalog>> getCatalog(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async => cancellation.isCancelled
      ? cancelled(Operation.catalog)
      : unsupported(Operation.catalog);
  @override
  Future<Result<ChapterContent>> getChapter(
    ChapterKey key, {
    required CancellationToken cancellation,
  }) {
    if (cancellation.isCancelled) {
      return Future.value(cancelled(Operation.chapter));
    }
    if (key != contractChapter) {
      return Future.value(
        Failure(
          AppFailure(kind: FailureKind.notFound, operation: Operation.chapter),
        ),
      );
    }
    chapterCalls++;
    return forCaller(
      pendingChapter?.future ?? Future.value(Success(contractContent('合成正文'))),
      cancellation,
      Operation.chapter,
    );
  }

  @override
  Future<Result<SourceMediaBody>> openMedia(
    MediaRef ref, {
    required int maxBytes,
    required CancellationToken cancellation,
  }) async {
    if (cancellation.isCancelled) return cancelled(Operation.media);
    if (maxBytes < 1) {
      return Failure(
        AppFailure(kind: FailureKind.tooLarge, operation: Operation.media),
      );
    }
    if (ref != contractMedia) {
      return Failure(
        AppFailure(kind: FailureKind.notFound, operation: Operation.media),
      );
    }
    mediaCalls++;
    return Success(ContractBody(maxBytes, cancellation));
  }
}

final class ContractBody implements SourceMediaBody {
  ContractBody(this.maxBytes, this.token);
  final CancellationToken token;
  @override
  final int maxBytes;
  @override
  MediaInfo get info => MediaInfo(format: MediaFormat.unknown, byteLength: 4);
  bool closed = false;
  bool _listened = false;
  int closeCount = 0;
  @override
  Stream<Result<List<int>>> get chunks {
    if (_listened || closed) throw StateError('Body is single-use');
    _listened = true;
    return _read();
  }

  Stream<Result<List<int>>> _read() async* {
    var bytes = 0;
    try {
      for (final chunk in [
        [1, 2],
        [3, 4],
      ]) {
        if (closed || token.isCancelled) {
          yield cancelled(Operation.media);
          return;
        }
        bytes += chunk.length;
        if (bytes > maxBytes) {
          yield Failure(
            AppFailure(kind: FailureKind.tooLarge, operation: Operation.media),
          );
          return;
        }
        yield Success(List.unmodifiable(chunk));
      }
    } finally {
      await close();
    }
  }

  @override
  Future<void> close() async {
    if (!closed) {
      closed = true;
      closeCount++;
    }
  }
}

final class ContractNovelRepository implements NovelRepository {
  ContractNovelRepository(this.source);
  final ContractSource source;
  ChapterContent? cached;
  bool stale = true;
  AppFailure? refreshFailure;
  final _updates =
      StreamController<Result<LoadResult<ChapterContent>>>.broadcast(
        sync: true,
      );
  Future<Result<LoadResult<ChapterContent>>>? _refreshing;
  final _lifetime = CancellationSource();
  Future<void> close() async {
    _lifetime.cancel();
    await _updates.close();
  }

  Result<LoadResult<ChapterContent>> _cached() => cached == null
      ? Failure(
          AppFailure(
            kind: FailureKind.cache,
            operation: Operation.chapter,
            context: FailureContext.cacheMiss,
          ),
        )
      : Success(
          LoadResult(
            value: cached!,
            origin: LoadOrigin.memory,
            fetchedAt: contractNow,
            isStale: stale,
            refreshFailure: refreshFailure,
          ),
        );

  Future<Result<LoadResult<ChapterContent>>> _refresh(ChapterKey key) =>
      _refreshing ??= _fetch(key).whenComplete(() {
        _refreshing = null;
      });
  Future<Result<LoadResult<ChapterContent>>> _fetch(ChapterKey key) async {
    final response = await source.getChapter(
      key,
      cancellation: _lifetime.token,
    );
    if (_lifetime.token.isCancelled) return cancelled(Operation.chapter);
    final Result<LoadResult<ChapterContent>> result;
    switch (response) {
      case Success(:final value):
        cached = value;
        stale = false;
        refreshFailure = null;
        result = Success(
          LoadResult(
            value: value,
            origin: LoadOrigin.remote,
            fetchedAt: contractNow,
          ),
        );
      case Failure(:final failure):
        if (failure.isCancellation) return cancelled(Operation.chapter);
        if (cached == null) {
          result = Failure(failure);
        } else {
          stale = true;
          refreshFailure = failure;
          result = _cached();
        }
    }
    _updates.add(result);
    return result;
  }

  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    if (cancellation.isCancelled) return cancelled(Operation.chapter);
    if (key != contractChapter) {
      return Failure(
        AppFailure(kind: FailureKind.notFound, operation: Operation.chapter),
      );
    }
    if (mode == ReadMode.cacheOnly) {
      return _cached(); // No Source touch, even on miss.
    }
    if (mode == ReadMode.cacheFirst && cached != null) {
      final snapshot = _cached();
      if (stale) unawaited(_refresh(key));
      return snapshot;
    }
    return forCaller(_refresh(key), cancellation, Operation.chapter);
  }

  @override
  Stream<Result<LoadResult<ChapterContent>>> chapterUpdates(ChapterKey key) =>
      key == contractChapter ? _updates.stream : const Stream.empty();
  @override
  Stream<Result<LoadResult<NovelDetail>>> detailUpdates(NovelKey key) =>
      const Stream.empty();
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      const Stream.empty();
  @override
  Future<Result<List<DiscoverSection>>> discover(
    SourceId sourceId, {
    required CancellationToken cancellation,
  }) => sourceId == contractSourceId
      ? source.discover(cancellation: cancellation)
      : Future.value(unsupported(Operation.discover));
  @override
  Future<Result<SearchPage>> search(
    SourceId sourceId,
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) => sourceId == contractSourceId
      ? source.search(query, cursor: cursor, cancellation: cancellation)
      : Future.value(unsupported(Operation.search));
  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async => cancellation.isCancelled
      ? cancelled(Operation.novelDetail)
      : unsupported(Operation.novelDetail);
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async => cancellation.isCancelled
      ? cancelled(Operation.catalog)
      : unsupported(Operation.catalog);
}

final class ContractLease implements MediaLease {
  ContractLease(this._data, this.persistence, {this.persistenceFailure});
  final MediaData _data;
  @override
  MediaData get data {
    if (isClosed) throw StateError('Lease already closed');
    return _data;
  }

  @override
  final MediaPersistence persistence;
  @override
  final AppFailure? persistenceFailure;
  @override
  bool isClosed = false;
  int closeCount = 0;
  @override
  Future<void> close() async {
    if (!isClosed) {
      isClosed = true;
      closeCount++;
    }
  }
}

final class ContractImageRepository implements ImageRepository {
  ContractImageRepository(this.source);
  final ContractSource source;
  Uint8List? memory;
  String? localPath;
  AppFailure? writeFailure;
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    if (cancellation.isCancelled) return cancelled(Operation.media);
    final info = MediaInfo(format: MediaFormat.unknown, byteLength: 4);
    if (mode != ReadMode.refresh && localPath != null) {
      return Success(
        LoadResult(
          value: ContractLease(
            LocalMedia(path: localPath!, info: info),
            MediaPersistence.persistedLocal,
          ),
          origin: LoadOrigin.local,
          fetchedAt: contractNow,
        ),
      );
    }
    if (mode != ReadMode.refresh && memory != null) {
      return Success(
        LoadResult(
          value: ContractLease(
            MemoryMedia(bytes: memory!, info: info),
            MediaPersistence.memoryOnly,
          ),
          origin: LoadOrigin.memory,
          fetchedAt: contractNow,
        ),
      );
    }
    if (mode == ReadMode.cacheOnly) {
      return Failure(
        AppFailure(
          kind: FailureKind.cache,
          operation: Operation.media,
          context: FailureContext.cacheMiss,
        ),
      );
    }
    final opened = await source.openMedia(
      ref,
      maxBytes: 4,
      cancellation: cancellation,
    );
    if (opened case Failure(:final failure)) return Failure(failure);
    final body = (opened as Success<SourceMediaBody>).value;
    final bytes = <int>[];
    try {
      await for (final part in body.chunks) {
        switch (part) {
          case Success(:final value):
            bytes.addAll(value);
          case Failure(:final failure):
            return Failure(failure);
        }
      }
      if (cancellation.isCancelled) return cancelled(Operation.media);
      memory = Uint8List.fromList(bytes);
      return Success(
        LoadResult(
          value: ContractLease(
            MemoryMedia(bytes: memory!, info: info),
            MediaPersistence.memoryOnly,
            persistenceFailure: writeFailure,
          ),
          origin: LoadOrigin.remote,
          fetchedAt: contractNow,
        ),
      );
    } finally {
      await body.close();
    }
  }
}

final class ContractSettings implements SettingsStore {
  ReaderSettings settings = ReaderSettings();
  @override
  Future<Result<ReaderSettings>> load({
    required CancellationToken cancellation,
  }) async => cancellation.isCancelled
      ? cancelled(Operation.settingsRead)
      : Success(settings);
  @override
  Future<Result<void>> save(
    ReaderSettings value, {
    required CancellationToken cancellation,
  }) async {
    if (cancellation.isCancelled) return cancelled(Operation.settingsWrite);
    settings = value;
    return const Success(null);
  }
}
