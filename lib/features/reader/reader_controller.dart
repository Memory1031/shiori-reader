import 'dart:async';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/controllers/scoped_controller.dart';

enum ReaderStatus { loading, ready, error, cancelled }

/// One chapter session. Repositories are borrowed; requests belong to this scope.
/// Ready content stays pinned until the reader explicitly opens another session.
class ReaderController extends ScopedController {
  ReaderController({required this.repository, required this.chapter});
  final NovelRepository repository;
  final ChapterKey chapter;
  ReaderStatus status = ReaderStatus.loading;
  ChapterContent? content;
  AppFailure? failure;
  CancellationSource? _request;

  @override
  void onInit() {
    super.onInit();
    unawaited(load());
  }

  Future<void> load() async {
    if (isClosed) return;
    final previousFailure = failure;
    if (previousFailure != null &&
        (previousFailure.retryPolicy == RetryPolicy.never ||
            (previousFailure.kind == FailureKind.rateLimited &&
                (previousFailure.retryNotBefore == null ||
                    DateTime.now().isBefore(
                      previousFailure.retryNotBefore!,
                    ))))) {
      return;
    }
    _request?.cancel();
    final request = _request = CancellationSource();
    status = ReaderStatus.loading;
    failure = null;
    update();
    final result = await repository.loadChapter(
      chapter,
      mode: ReadMode.cacheFirst,
      cancellation: request.token,
    );
    if (isClosed || request != _request || request.token.isCancelled) return;
    switch (result) {
      case Success(:final value):
        if (value.value.key != chapter) {
          failure = AppFailure(
            kind: FailureKind.parse,
            operation: Operation.chapter,
            context: FailureContext.invalidContent,
          );
          status = ReaderStatus.error;
        } else {
          content = value.value;
          status = ReaderStatus.ready;
        }
      case Failure(:final failure):
        this.failure = failure.isCancellation ? null : failure;
        status = failure.isCancellation
            ? ReaderStatus.cancelled
            : ReaderStatus.error;
    }
    update();
  }

  @override
  void onClose() {
    _request?.cancel();
    super.onClose();
  }
}
