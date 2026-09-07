import 'lightnovel_media.dart';
import 'lightnovel_chapter.dart';
import 'lightnovel_catalog.dart';
import 'lightnovel_detail.dart';
import 'package:dio/dio.dart';
import 'lightnovel_search.dart';
import '../../../domain/contracts/contracts.dart';
import '../../../domain/models/models.dart';
import '../../../shared/app_logger.dart';
import '../../network/request_scheduler.dart';
import 'lightnovel_api.dart';

/// Composition root owns this Source; registry/repository only borrow it.
/// Parsing is implemented in SRC-006..009; unsupported operations do no I/O.
final class LightNovelSource implements NovelSource, SourceMedia {
  LightNovelSource({
    required RequestScheduler scheduler,
    required AppLogger logger,
    HttpClientAdapter? adapter,
    HttpClientAdapter Function()? mediaAdapterFactory,
  }) : _api = LightNovelApi(
         scheduler: scheduler,
         logger: logger,
         adapter: adapter,
       ) {
    _search = LightNovelSearch(_api);
    _detail = LightNovelDetail(_api);
    _catalog = LightNovelCatalog(_api);
    _chapter = LightNovelChapter(_api);
    _media = LightNovelMedia(
      api: _api,
      scheduler: scheduler,
      logger: logger,
      adapterFactory: mediaAdapterFactory,
    );
  }
  final LightNovelApi _api;
  late final LightNovelMedia _media;
  late final LightNovelSearch _search;
  late final LightNovelDetail _detail;
  late final LightNovelCatalog _catalog;
  late final LightNovelChapter _chapter;
  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    sourceId: lightNovelSourceId,
    displayName: 'LightNovel.fun',
    supportsDiscover: false,
    supportsSearchPaging: true,
  );
  Future<Result<T>> _pending<T>(
    Operation operation,
    CancellationToken token,
  ) async {
    final session = _api.ensureSession(operation, token);
    if (session case Failure(:final failure)) return Failure(failure);
    return Failure(
      AppFailure(kind: FailureKind.unsupported, operation: operation),
    );
  }

  @override
  Future<Result<List<DiscoverSection>>> discover({
    required CancellationToken cancellation,
  }) => _pending(Operation.discover, cancellation);
  @override
  Future<Result<SearchPage>> search(
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) => _search.search(query, cursor: cursor, cancellation: cancellation);
  @override
  Future<Result<NovelDetail>> getNovelDetail(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => _detail.load(key, cancellation);
  @override
  Future<Result<Catalog>> getCatalog(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => _catalog.load(key, cancellation);
  @override
  Future<Result<ChapterContent>> getChapter(
    ChapterKey key, {
    required CancellationToken cancellation,
  }) => _chapter.load(key, cancellation);
  @override
  Future<Result<SourceMediaBody>> openMedia(
    MediaRef ref, {
    required int maxBytes,
    required CancellationToken cancellation,
  }) => _media.openMedia(ref, maxBytes: maxBytes, cancellation: cancellation);
  void close() {
    _media.close();
    _search.close();
    _api.close();
  }
}
