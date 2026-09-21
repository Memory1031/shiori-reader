import 'dart:async';

import '../../domain/contracts/contracts.dart';
import '../../domain/catalog_observation.dart';
import '../../domain/models/models.dart';
import '../../shared/controllers/scoped_controller.dart';

/// One opaque novel identity per scope. Repository and update stream are borrowed.
class CatalogController extends ScopedController {
  CatalogController({
    required this.repository,
    required this.novel,
    this.initialMode = ReadMode.cacheFirst,
  });
  final ReadMode initialMode;
  final NovelRepository repository;
  final NovelKey novel;
  LoadResult<Catalog>? loaded;
  AppFailure? failure;
  bool loading = false;
  CancellationSource? _request;
  int _updates = 0;

  bool get canLoad =>
      !isClosed &&
      !loading &&
      (failure == null ||
          failure!.context == FailureContext.cacheMiss ||
          failure!.retryPolicy != RetryPolicy.never &&
              (failure!.kind != FailureKind.rateLimited ||
                  failure!.retryNotBefore != null &&
                      !DateTime.now().isBefore(failure!.retryNotBefore!)));

  @override
  void onInit() {
    super.onInit();
    listenTo(repository.catalogUpdates(novel), (result) {
      if (result case Failure(:final failure) when failure.isCancellation) {
        return;
      }
      _updates++;
      _accept(result);
      update();
    });
    unawaited(load(mode: initialMode));
  }

  Future<void> load({ReadMode mode = ReadMode.cacheFirst}) async {
    if (!canLoad) return;
    final request = _request = CancellationSource();
    final updates = _updates;
    loading = true;
    failure = null;
    update();
    Result<LoadResult<Catalog>> result;
    try {
      result = await repository.loadCatalog(
        novel,
        mode: mode,
        cancellation: request.token,
      );
    } catch (_) {
      result = Failure(
        AppFailure(
          kind: FailureKind.sourceUnavailable,
          operation: Operation.catalog,
          retryPolicy: RetryPolicy.manual,
        ),
      );
    }
    if (isClosed || request.token.isCancelled || _request != request) return;
    _request = null;
    loading = false;
    // Fetch time, not callback arrival, decides which successful value is newer.
    if (result is Success<LoadResult<Catalog>>) {
      final latestFailure = _updates != updates ? failure : null;
      _accept(result);
      failure = latestFailure ?? failure;
    } else if (_updates == updates) {
      _accept(result);
    }
    update();
  }

  Future<void> refreshCatalog() => load(mode: ReadMode.refresh);

  void _accept(Result<LoadResult<Catalog>> result) {
    switch (result) {
      case Success(:final value):
        if (value.value.novelKey != novel) {
          failure = AppFailure(
            kind: FailureKind.parse,
            operation: Operation.catalog,
            context: FailureContext.invalidContent,
          );
          return;
        }
        if (acceptsCatalogObservation(value, loaded)) {
          loaded = value;
          failure = value.refreshFailure;
        } else if (value.refreshFailure != null) {
          failure = value.refreshFailure;
        }
      case Failure(:final failure):
        if (!failure.isCancellation) this.failure = failure;
    }
  }

  @override
  void onClose() {
    _request?.cancel();
    super.onClose();
  }
}
