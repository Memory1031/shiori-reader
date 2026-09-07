import 'dart:async';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/controllers/scoped_controller.dart';

/// One opaque novel identity per scope. Repository and update stream are borrowed.
class DetailController extends ScopedController {
  DetailController({required this.repository, required this.novel});
  final NovelRepository repository;
  final NovelKey novel;
  LoadResult<NovelDetail>? loaded;
  AppFailure? failure;
  bool loading = false;
  CancellationSource? _request;
  int _updates = 0;

  bool get canLoad =>
      !isClosed &&
      !loading &&
      (failure == null ||
          failure!.retryPolicy != RetryPolicy.never &&
              (failure!.kind != FailureKind.rateLimited ||
                  failure!.retryNotBefore != null &&
                      !DateTime.now().isBefore(failure!.retryNotBefore!)));

  @override
  void onInit() {
    super.onInit();
    listenTo(repository.detailUpdates(novel), (result) {
      if (result case Failure(:final failure) when failure.isCancellation) {
        return;
      }
      _updates++;
      _accept(result);
      update();
    });
    unawaited(load());
  }

  Future<void> load({ReadMode mode = ReadMode.cacheFirst}) async {
    if (!canLoad) return;
    final request = _request = CancellationSource();
    final updates = _updates;
    loading = true;
    failure = null;
    update();
    Result<LoadResult<NovelDetail>> result;
    try {
      result = await repository.loadDetail(
        novel,
        mode: mode,
        cancellation: request.token,
      );
    } catch (_) {
      result = Failure(
        AppFailure(
          kind: FailureKind.sourceUnavailable,
          operation: Operation.novelDetail,
          retryPolicy: RetryPolicy.manual,
        ),
      );
    }
    if (isClosed || request.token.isCancelled || _request != request) return;
    _request = null;
    loading = false;
    // A current repository notification wins over an earlier cache snapshot.
    if (_updates == updates) {
      _accept(result);
    } else if (loaded == null && result is Success<LoadResult<NovelDetail>>) {
      // A failure notification can precede the initial cached value. Keep both.
      final latestFailure = failure;
      _accept(result);
      failure = latestFailure ?? failure;
    }
    update();
  }

  Future<void> refreshDetail() => load(mode: ReadMode.refresh);

  void _accept(Result<LoadResult<NovelDetail>> result) {
    switch (result) {
      case Success(:final value):
        if (value.value.summary.key != novel) {
          failure = AppFailure(
            kind: FailureKind.parse,
            operation: Operation.novelDetail,
            context: FailureContext.invalidContent,
          );
          return;
        }
        loaded = value;
        failure = value.refreshFailure;
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
