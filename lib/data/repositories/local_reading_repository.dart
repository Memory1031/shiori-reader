import '../../domain/contracts/contracts.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/models/models.dart';

/// Local identity dispatch happens before all online cache/source decorators.
/// Borrowed dependencies retain their original lifetime owners.
class LocalReadingRepository
    implements
        NovelRepository,
        LocalNavigationRepository,
        LocalBookProgressRepository,
        LocalPagePresentationRepository,
        LocalBookInvalidation,
        LocalContentLinkRepository {
  LocalReadingRepository({
    required this.local,
    required this.online,
    this.resolveOnlineCatalog,
  });
  final Future<Result<LoadResult<Catalog>>> Function(
    NovelKey,
    Result<LoadResult<Catalog>>,
  )?
  resolveOnlineCatalog;
  Future<Result<LoadResult<Catalog>>> _observeCatalog(
    NovelKey key,
    Result<LoadResult<Catalog>> result, {
    CancellationToken? cancellation,
  }) async {
    if (cancellation?.isCancelled == true) {
      return Failure(AppFailure.cancelled(Operation.catalog));
    }
    if (result case Failure(:final failure) when failure.isCancellation) {
      return result;
    }
    final resolve = resolveOnlineCatalog;
    if (resolve == null) return result;
    final resolved = await resolve(key, result);
    if (cancellation?.isCancelled == true) {
      return Failure(AppFailure.cancelled(Operation.catalog));
    }
    if (resolved case Failure(
      :final failure,
    ) when failure.kind == FailureKind.database) {
      // A transient reconciliation/read failure must leave refresh available.
      return Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.catalog,
          retryPolicy: RetryPolicy.manual,
        ),
      );
    }
    return resolved;
  }

  final LocalBookStore local;
  @override
  Stream<NovelKey> get invalidations => local is LocalBookInvalidation
      ? (local as LocalBookInvalidation).invalidations
      : const Stream.empty();

  @override
  Stream<NovelKey> get changes => local is LocalBookInvalidation
      ? (local as LocalBookInvalidation).changes
      : const Stream.empty();
  final NovelRepository online;
  @override
  Future<Result<String?>> loadPagePresentation(
    ChapterKey chapter, {
    required CancellationToken cancellation,
  }) async {
    if (!_local(chapter.novelKey) ||
        local is! LocalPagePresentationRepository) {
      return const Success(null);
    }
    return (local as LocalPagePresentationRepository).loadPagePresentation(
      chapter,
      cancellation: cancellation,
    );
  }

  bool _local(NovelKey key) => key.sourceId == LocalBookIdentity.sourceId;
  Future<Result<LoadResult<T>>> _read<T>(
    NovelKey key,
    Operation op,
    CancellationToken token,
    T? Function(LocalBookRecord) select,
  ) async {
    final result = await local.read(key, cancellation: token);
    if (result case Failure(:final failure)) return Failure(failure);
    final record = (result as Success<LocalBookRecord?>).value;
    final value = record == null ? null : select(record);
    if (value == null) {
      return Failure(AppFailure(kind: FailureKind.notFound, operation: op));
    }
    return Success(
      LoadResult(
        value: value,
        origin: LoadOrigin.local,
        fetchedAt: record!.importedAt,
      ),
    );
  }

  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => _local(key)
      ? _read(key, Operation.novelDetail, cancellation, (r) => r.content.detail)
      : online.loadDetail(key, mode: mode, cancellation: cancellation);
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => _local(key)
      ? _read(key, Operation.catalog, cancellation, (r) => r.content.catalog)
      : online
            .loadCatalog(key, mode: mode, cancellation: cancellation)
            .then(
              (result) =>
                  _observeCatalog(key, result, cancellation: cancellation),
            );
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => _local(key.novelKey)
      ? _read(
          key.novelKey,
          Operation.chapter,
          cancellation,
          (r) => [
            ...r.content.chapters,
            ...r.content.auxiliaryChapters,
          ].where((c) => c.key == key).firstOrNull,
        )
      : online.loadChapter(key, mode: mode, cancellation: cancellation);
  @override
  Future<Result<BookProgressMetrics>> loadProgressMetrics(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    final result = await _read(
      key,
      Operation.catalog,
      cancellation,
      (r) => r.content.progressMetrics,
    );
    return switch (result) {
      Success(:final value) => Success(value.value),
      Failure(:final failure) => Failure(failure),
    };
  }

  @override
  Future<Result<List<LocalContentLink>>> loadContentLinks(
    ChapterKey source, {
    required CancellationToken cancellation,
  }) async {
    if (_local(source.novelKey) && local is LocalBookLinkStore) {
      return (local as LocalBookLinkStore).loadContentLinks(
        source,
        cancellation: cancellation,
      );
    }
    final result = await _read(
      source.novelKey,
      Operation.chapter,
      cancellation,
      (r) => r.content.links.where((l) => l.source == source).toList(),
    );
    return switch (result) {
      Success(:final value) => Success(value.value),
      Failure(:final failure) => Failure(failure),
    };
  }

  @override
  Future<Result<List<ChapterKey>>> loadReadingOrder(
    NovelKey book, {
    required CancellationToken cancellation,
  }) async {
    final result = await _read(
      book,
      Operation.catalog,
      cancellation,
      (r) =>
          r.content.readingOrder ??
          r.content.catalog.flatChapters.map((c) => c.key).toList(),
    );
    return switch (result) {
      Success(:final value) => Success(value.value),
      Failure(:final failure) => Failure(failure),
    };
  }

  @override
  Future<Result<List<LocalNavigationEntry>>> loadNavigation(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    final result = await _read(
      key,
      Operation.catalog,
      cancellation,
      (r) => r.content.navigation.isNotEmpty
          ? r.content.navigation
          : [
              for (final c in r.content.chapters)
                LocalNavigationEntry(title: c.title, chapterKey: c.key),
            ],
    );
    return switch (result) {
      Success(:final value) => Success(value.value),
      Failure(:final failure) => Failure(failure),
    };
  }

  @override
  Stream<Result<LoadResult<NovelDetail>>> detailUpdates(NovelKey key) =>
      _local(key)
      ? changes
            .where((k) => k == key)
            .asyncMap(
              (_) => loadDetail(
                key,
                mode: ReadMode.cacheOnly,
                cancellation: CancellationSource().token,
              ),
            )
      : online.detailUpdates(key);
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      _local(key)
      ? changes
            .where((k) => k == key)
            .asyncMap(
              (_) => loadCatalog(
                key,
                mode: ReadMode.cacheOnly,
                cancellation: CancellationSource().token,
              ),
            )
      : online
            .catalogUpdates(key)
            .asyncMap((result) => _observeCatalog(key, result));
  @override
  Stream<Result<LoadResult<ChapterContent>>> chapterUpdates(ChapterKey key) =>
      _local(key.novelKey)
      ? changes
            .where((k) => k == key.novelKey)
            .asyncMap(
              (_) => loadChapter(
                key,
                mode: ReadMode.cacheOnly,
                cancellation: CancellationSource().token,
              ),
            )
      : online.chapterUpdates(key);
  @override
  Future<Result<List<DiscoverSection>>> discover(
    SourceId id, {
    required CancellationToken cancellation,
  }) => online.discover(id, cancellation: cancellation);
  @override
  Future<Result<SearchPage>> search(
    SourceId id,
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) => online.search(id, query, cursor: cursor, cancellation: cancellation);
}
