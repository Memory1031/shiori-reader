import 'dart:async';
import 'position/progress_tracker.dart';
import 'position/position_resolver.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/controllers/scoped_controller.dart';

enum ReaderStatus { loading, ready, error, cancelled }

enum ReaderRestoreStatus { loading, positioning, ready, readFailed }

/// One chapter session. Repositories are borrowed; requests belong to this scope.
/// Ready content stays pinned until the reader explicitly opens another session.
class ReaderController extends ScopedController {
  ReaderController({
    required this.repository,
    required this.chapter,
    this.library,
    this.cache,
    this.readMode = ReadMode.cacheFirst,
    this.onPosition,
    this.initialBlockKey,
    this.startAtBeginning = false,
    this.startAtEnd = false,
    bool deferProgress = false,
  }) : _progressActive = !deferProgress;
  bool _progressActive;
  void activateProgress() {
    if (isClosed || _progressActive) return;
    _progressActive = true;
    unawaited(_openProgress());
  }

  final NovelRepository repository;
  final ChapterKey chapter;
  final LibraryRepository? library;
  final CacheManagement? cache;
  final ReadMode readMode;
  final String? initialBlockKey;
  final bool startAtBeginning;
  final bool startAtEnd;
  final void Function(int)? onPosition;
  void Function()? _unpin;
  ProgressTracker? progress;
  AppFailure? progressFailure;
  AppFailure? restoreFailure;
  ReaderPosition? initialPosition;
  String? pagePresentation;
  List<LocalContentLink> contentLinks = const [];
  int restoreAttempt = 0;
  bool usedFallback = false;
  ReaderRestoreStatus restoreStatus = ReaderRestoreStatus.loading;
  (ReaderPosition, bool)? _sample;
  bool _restoring = false;
  bool _openingProgress = false;

  void restoringProgress() {
    if (restoreStatus != ReaderRestoreStatus.readFailed) {
      restoreStatus = ReaderRestoreStatus.positioning;
    }
    _restoring = true;
    progress?.restoring(true);
  }

  void sampleProgress(ReaderPosition position, bool completed) {
    if (isClosed) return;
    if (restoreStatus != ReaderRestoreStatus.readFailed) {
      restoreStatus = ReaderRestoreStatus.ready;
    }
    _restoring = false;
    _sample = (position, completed);
    onPosition?.call(position.blockIndex);
    progress?.restoring(false);
    progress?.sample(position, completed: completed);
  }

  Future<void> flushProgress() async {
    await progress?.flush();
  }

  Future<void> retryProgress() async {
    if (restoreFailure != null) {
      // Explicit retry opens a fresh restore attempt. Never apply a late DB
      // result to a reader that the user has already been moving through.
      await load();
    } else if (progress != null) {
      await progress!.retry();
    } else {
      await _openProgress();
    }
  }

  Future<void> _openProgress() async {
    if (!_progressActive ||
        library == null ||
        content == null ||
        restoreFailure != null ||
        isClosed ||
        _openingProgress ||
        progress != null) {
      return;
    }
    _openingProgress = true;
    final request = _request!;
    final results = await Future.wait([
      repository.loadDetail(
        chapter.novelKey,
        mode: readMode,
        cancellation: request.token,
      ),
      repository.loadCatalog(
        chapter.novelKey,
        mode: readMode,
        cancellation: request.token,
      ),
    ]);
    _openingProgress = false;
    if (isClosed || request != _request || request.token.isCancelled) return;
    final detail = results[0];
    final catalog = results[1];
    if (detail is Success<LoadResult<NovelDetail>> &&
        catalog is Success<LoadResult<Catalog>>) {
      final chapters = catalog.value.value.flatChapters.where(
        (c) => c.key == chapter,
      );
      if (detail.value.value.summary.key == chapter.novelKey &&
          chapters.isNotEmpty) {
        progressFailure = null;
        final tracker = progress = ProgressTracker(
          library: library!,
          content: content!,
          snapshot: detail.value.value.summary,
          ordinal: chapters.first.ordinal,
          catalogRevision: catalog.value.value.revision,
          onStatus: () {
            if (!isClosed) update();
          },
        );
        unawaited(tracker.start());
        tracker.restoring(_restoring);
        if (_sample case final sample?) {
          tracker.sample(sample.$1, completed: sample.$2);
        }
        update();
        return;
      }
    }
    final saved = await library!.getProgress(
      chapter.novelKey,
      cancellation: request.token,
    );
    if (isClosed || request != _request || request.token.isCancelled) return;
    if (saved case Success(
      value: final previous?,
    ) when previous.chapterKey == chapter) {
      final tracker = progress = ProgressTracker(
        library: library!,
        content: content!,
        snapshot: previous.snapshot,
        ordinal: previous.chapterOrdinalSnapshot,
        catalogRevision: previous.catalogRevision,
        onStatus: () {
          if (!isClosed) update();
        },
      );
      progressFailure = null;
      unawaited(tracker.start());
      tracker.restoring(_restoring);
      if (_sample case final sample?) {
        tracker.sample(sample.$1, completed: sample.$2);
      }
      update();
      return;
    }
    progressFailure = AppFailure(
      kind: FailureKind.database,
      operation: Operation.progressWrite,
    );
    update();
  }

  ReaderStatus status = ReaderStatus.loading;
  ChapterContent? content;
  AppFailure? failure;
  CancellationSource? _request;

  @override
  void onInit() {
    super.onInit();
    _unpin = cache?.pinChapter(chapter);
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
    restoreAttempt++;
    restoreStatus = ReaderRestoreStatus.loading;
    restoreFailure = null;
    initialPosition = null;
    pagePresentation = null;
    contentLinks = const [];
    usedFallback = false;
    _sample = null;
    _restoring = true;
    failure = null;
    update();
    final result = await repository.loadChapter(
      chapter,
      mode: readMode,
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
          if (repository is LocalPagePresentationRepository) {
            final presentation =
                await (repository as LocalPagePresentationRepository)
                    .loadPagePresentation(chapter, cancellation: request.token);
            if (isClosed || request != _request || request.token.isCancelled) {
              return;
            }
            if (presentation case Success<String?>(:final value)) {
              pagePresentation = value;
            }
          }

          if (repository is LocalContentLinkRepository &&
              chapter.novelKey.sourceId == LocalBookIdentity.sourceId) {
            final links = await (repository as LocalContentLinkRepository)
                .loadContentLinks(chapter, cancellation: request.token);
            if (isClosed || request != _request || request.token.isCancelled) {
              return;
            }
            if (links case Success<List<LocalContentLink>>(:final value)) {
              contentLinks = value;
            }
          }
          final saved = await library?.getProgress(
            chapter.novelKey,
            cancellation: request.token,
          );
          if (isClosed || request != _request || request.token.isCancelled) {
            return;
          }
          if (saved case Failure<ReadingProgress?>(:final failure)) {
            restoreFailure = failure;
            restoreStatus = ReaderRestoreStatus.readFailed;
          } else {
            if (saved case Success<ReadingProgress?>(
              value: final record?,
            ) when record.chapterKey == chapter) {
              final resolved = resolveReaderPosition(content!, record.position);
              initialPosition = resolved.position;
              usedFallback = resolved.usedFallback;
            }
            if (startAtBeginning || initialBlockKey != null) {
              final found = content!.blocks.indexWhere(
                (b) => b.blockKey == initialBlockKey,
              );
              final index = found < 0 ? 0 : found;
              usedFallback = initialBlockKey != null && found < 0;
              initialPosition = ReaderPosition(
                contentRevision: content!.contentRevision,
                blockKey: content!.blocks[index].blockKey,
                blockIndex: index,
                blockFraction: 0,
                chapterFraction: index / content!.blocks.length,
              );
            }
            if (startAtEnd) {
              final index = content!.blocks.length - 1;
              initialPosition = ReaderPosition(
                contentRevision: content!.contentRevision,
                blockKey: content!.blocks[index].blockKey,
                blockIndex: index,
                blockFraction: 1,
                chapterFraction: 1,
              );
              usedFallback = false;
            }
            restoreStatus = ReaderRestoreStatus.positioning;
          }
          status = ReaderStatus.ready;
          unawaited(_openProgress());
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
    _unpin?.call();
    _request?.cancel();
    unawaited(progress?.close());
    super.onClose();
  }
}
