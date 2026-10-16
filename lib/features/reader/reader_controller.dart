import '../../domain/bookmark_position.dart';
import 'dart:async';
import '../../domain/catalog_observation.dart';
import 'position/progress_tracker.dart';
import 'position/position_resolver.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/controllers/scoped_controller.dart';

enum ReaderStatus { loading, ready, error, cancelled }

enum ReaderRestoreStatus { loading, positioning, ready, readFailed }

enum ReaderProgressStatus { normal, unsaved, paused }

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
    this.initialBlockOffset,
    this.navigationPosition,
    this.bookmark,
    this.startAtBeginning = false,
    this.startAtEnd = false,
    bool deferProgress = false,
  }) : _progressActive = !deferProgress;
  bool _progressActive;
  bool _bookRemoved = false;
  void activateProgress() {
    if (isClosed || _bookRemoved || _progressActive) return;
    _progressActive = true;
    if (_sample case final sample?) onPosition?.call(sample.$1.blockIndex);
    unawaited(_openProgress());
  }

  final NovelRepository repository;
  final ChapterKey chapter;
  final LibraryRepository? library;
  final CacheManagement? cache;
  ReadMode readMode;
  final String? initialBlockKey;
  final int? initialBlockOffset;
  final ReaderPosition? navigationPosition;
  final UserBookmark? bookmark;
  BookmarkResolution? bookmarkResolution;
  final bool startAtBeginning;
  final bool startAtEnd;
  final void Function(int)? onPosition;
  void Function()? _unpin;
  ProgressTracker? progress;
  BookProgressMetrics? bookMetrics;
  NovelStatus novelStatus = NovelStatus.unknown;
  ReadingProgress? _savedProgress;
  BookTerminalState? _pendingTerminal;
  LoadResult<Catalog>? _catalogObservation;
  BookProgressSnapshot? bookProgressAt(double chapterFraction) =>
      bookMetrics?.at(chapter, chapterFraction);
  void updateCatalog(LoadResult<Catalog> observation) {
    if (chapter.novelKey.sourceId == LocalBookIdentity.sourceId ||
        observation.value.novelKey != chapter.novelKey ||
        !acceptsCatalogObservation(observation, _catalogObservation)) {
      return;
    }
    _catalogObservation = observation;
    bookMetrics = BookProgressMetrics.online(observation.value);
    progress?.updateMetrics(
      bookMetrics!,
      catalogOrdinal: _catalogOrdinal,
      catalog: observation,
    );
  }

  int? get _catalogOrdinal => _catalogObservation?.value.flatChapters
      .where((entry) => entry.key == chapter)
      .firstOrNull
      ?.ordinal;

  void enterBookEnd(BookTerminalState state) {
    _pendingTerminal = state;
    progress?.enterBookEnd(state);
  }

  AppFailure? progressFailure;
  AppFailure? restoreFailure;
  bool _recoveringRestore = false;
  ReaderProgressStatus _reportedProgressStatus = ReaderProgressStatus.normal;
  ReaderProgressStatus get progressStatus {
    if (!_progressActive || _bookRemoved || library == null) {
      return ReaderProgressStatus.normal;
    }
    if (restoreFailure != null) return ReaderProgressStatus.paused;
    if (progress?.progressSaved == true) return ReaderProgressStatus.normal;
    if (progressFailure != null || progress?.unsaved == true) {
      return ReaderProgressStatus.unsaved;
    }
    return _recoveringRestore
        ? ReaderProgressStatus.paused
        : ReaderProgressStatus.normal;
  }

  bool get canRetryProgress =>
      !isClosed &&
      !_bookRemoved &&
      _progressActive &&
      status == ReaderStatus.ready &&
      progressStatus != ReaderProgressStatus.normal &&
      (progress?.canRetry ?? true);

  /// A read-only/removed session has nothing to submit; an accepted stable
  /// sample requires a real acknowledgement, including after a restore failure.
  bool get hasUnsavedProgress =>
      !_bookRemoved &&
      _progressActive &&
      library != null &&
      _sample != null &&
      (progressStatus != ReaderProgressStatus.normal ||
          progress?.progressSaved != true);

  void _progressChanged() {
    if (isClosed) return;
    final recovered =
        progress?.progressSaved == true &&
        (progressFailure != null || _recoveringRestore);
    if (progress?.progressSaved == true) {
      progressFailure = null;
      _recoveringRestore = false;
    }
    final current = progressStatus;
    if (!recovered && current == _reportedProgressStatus) return;
    _reportedProgressStatus = current;
    update();
  }

  ReaderPosition? initialPosition;
  String? pagePresentation;
  List<LocalContentLink> contentLinks = const [];
  int restoreAttempt = 0;
  bool usedFallback = false;
  ReaderRestoreStatus restoreStatus = ReaderRestoreStatus.loading;
  (ReaderPosition, bool)? _sample;
  ReaderPosition? get currentPosition => _sample?.$1;
  bool _restoring = false;
  bool _openingProgress = false;

  void restoringProgress() {
    if (restoreStatus != ReaderRestoreStatus.readFailed) {
      restoreStatus = ReaderRestoreStatus.positioning;
    }
    _restoring = true;
    progress?.restoring(true);
  }

  bool hasPendingNavigation = false;
  void beginPositionNavigation() {
    hasPendingNavigation = true;
    _savedProgress = null;
    _pendingTerminal = null;
    progress?.leaveBookEnd();
  }

  /// Layout completion must be acknowledged even when its hidden position is ignored.
  void finishRestoringProgress() {
    if (isClosed) return;
    if (restoreStatus != ReaderRestoreStatus.readFailed) {
      restoreStatus = ReaderRestoreStatus.ready;
    }
    _restoring = false;
    progress?.restoring(false);
  }

  void sampleProgress(ReaderPosition position, bool completed) {
    if (isClosed) return;
    finishRestoringProgress();
    hasPendingNavigation = false;
    _sample = (position, completed);
    if (_progressActive) onPosition?.call(position.blockIndex);
    progress?.sample(position, completed: completed);
  }

  Future<void> flushProgress() async {
    await _progressOpening;
    await progress?.flush();
  }

  Future<bool> saveForExit() async {
    if (_bookRemoved || !_progressActive) return true;
    await _progressOpening;
    // Reflow may be pending; the queued sample is still the last stable anchor.
    progress?.restoring(false);
    await flushProgress();
    return !hasUnsavedProgress;
  }

  Future<void> retryProgress() async {
    if (isClosed || _bookRemoved || progress?.canRetry == false) return;
    if (restoreFailure != null) {
      // Explicit retry opens a fresh restore attempt. Never apply a late DB
      // result to a reader that the user has already been moving through.
      _recoveringRestore = true;
      await load();
    } else if (progress != null) {
      await progress!.retry();
    } else {
      await _openProgress();
    }
  }

  Future<void>? _progressOpening;
  Future<void> _openProgress() => _progressOpening ??= _doOpenProgress()
      .whenComplete(() => _progressOpening = null);
  Future<void> _doOpenProgress() async {
    if (_bookRemoved ||
        !_progressActive ||
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
    if (detail is Success<LoadResult<NovelDetail>>) {
      novelStatus = detail.value.value.status;
    }
    if (catalog is Success<LoadResult<Catalog>>) {
      if (chapter.novelKey.sourceId == LocalBookIdentity.sourceId) {
        if (repository case LocalBookProgressRepository local) {
          final metrics = await local.loadProgressMetrics(
            chapter.novelKey,
            cancellation: request.token,
          );
          if (isClosed || request != _request || request.token.isCancelled) {
            return;
          }
          if (metrics case Success<BookProgressMetrics>(:final value)) {
            bookMetrics = value;
          }
        }
      } else {
        updateCatalog(catalog.value);
      }
    }
    if (detail is Success<LoadResult<NovelDetail>> &&
        catalog is Success<LoadResult<Catalog>>) {
      final chapters = catalog.value.value.flatChapters.where(
        (c) => c.key == chapter,
      );
      if (detail.value.value.summary.key == chapter.novelKey &&
          chapters.isNotEmpty) {
        final tracker = progress = ProgressTracker(
          library: library!,
          content: content!,
          snapshot: detail.value.value.summary,
          ordinal: _catalogOrdinal ?? chapters.first.ordinal,
          catalogRevision:
              bookMetrics?.revision ?? catalog.value.value.revision,
          metrics: bookMetrics,
          catalog: _catalogObservation,
          previous: startAtBeginning || initialBlockKey != null
              ? null
              : _savedProgress,
          onStatus: _progressChanged,
        );
        unawaited(tracker.start());
        tracker.restoring(_restoring);
        if (_sample case final sample?) {
          tracker.sample(sample.$1, completed: sample.$2);
        }
        if (_pendingTerminal case final state?) tracker.enterBookEnd(state);
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
        ordinal: _catalogOrdinal ?? previous.chapterOrdinalSnapshot,
        catalogRevision: bookMetrics?.revision ?? previous.catalogRevision,
        metrics: bookMetrics,
        catalog: _catalogObservation,
        previous: startAtBeginning || initialBlockKey != null ? null : previous,
        onStatus: _progressChanged,
      );
      unawaited(tracker.start());
      tracker.restoring(_restoring);
      if (_sample case final sample?) {
        tracker.sample(sample.$1, completed: sample.$2);
      }
      if (_pendingTerminal case final state?) tracker.enterBookEnd(state);
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
    if (library case LibraryBookRemoval lifecycle) {
      listenTo(lifecycle.removedBooks, (key) {
        if (key != chapter.novelKey) return;
        _bookRemoved = true;
        _request?.cancel();
        progress?.discardRemovedBook();
        status = ReaderStatus.cancelled;
        content = null;
        update();
      });
    }
    if (library != null) {
      listenTo(repository.catalogUpdates(chapter.novelKey), (result) {
        if (result case Success<LoadResult<Catalog>>(:final value)) {
          updateCatalog(value);
          update();
        }
      });
    }
    _unpin = cache?.pinChapter(chapter);
    unawaited(load());
  }

  LocalBookUse? _bookUse;
  Future<void>? _useOpening;
  Future<void>? _closingReader;
  final _loads = <Future<void>>{};
  Future<void> _acquireUse() => _useOpening ??= () async {
    if (repository case LocalBookUsage usage) {
      _bookUse = await usage.acquireBookUse(
        chapter.novelKey,
        cancellation: cancellation,
      );
    }
  }();

  Future<void> load() {
    final future = _load();
    _loads.add(future);
    unawaited(
      future.then<void>(
        (_) => _loads.remove(future),
        onError: (Object _) => _loads.remove(future),
      ),
    );
    return future;
  }

  Future<void> _load() async {
    if (isClosed || _bookRemoved) return;
    try {
      if (chapter.novelKey.sourceId == LocalBookIdentity.sourceId &&
          repository is LocalBookUsage) {
        await _acquireUse();
      }
    } catch (_) {
      if (!isClosed) {
        failure = AppFailure(
          kind: FailureKind.database,
          operation: Operation.chapter,
        );
        status = ReaderStatus.error;
        update();
      }
      return;
    }
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
          if (saved case Success<ReadingProgress?>(:final value)) {
            _savedProgress = value;
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
              final fraction = found < 0
                  ? 0.0
                  : readerTargetFraction(
                      content!.blocks[index],
                      initialBlockOffset,
                    );
              initialPosition = ReaderPosition(
                contentRevision: content!.contentRevision,
                blockKey: content!.blocks[index].blockKey,
                blockIndex: index,
                blockFraction: fraction,
                chapterFraction: ReaderPosition.fractionFor(
                  blockIndex: index,
                  blockFraction: fraction,
                  blockCount: content!.blocks.length,
                ),
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
            if (navigationPosition case final requested?) {
              final resolved = resolveReaderPosition(content!, requested);
              initialPosition = resolved.position;
              usedFallback = resolved.usedFallback;
            }
            if (bookmark case final b?) {
              bookmarkResolution = pagePresentation != null
                  ? const BookmarkResolution(BookmarkLocation.unavailable)
                  : BookmarkPositionIndex([
                      content!,
                    ]).resolve(b.chapter, b.anchor);
              initialPosition = bookmarkResolution!.anchor?.position;
              usedFallback = !bookmarkResolution!.located;
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
    if (content == null &&
        (status == ReaderStatus.error || status == ReaderStatus.cancelled)) {
      await _bookUse?.release();
      _bookUse = null;
      _useOpening = null;
    }
    update();
  }

  @override
  void onClose() {
    _unpin?.call();
    _request?.cancel();
    super.onClose();
    unawaited(closeReader());
  }

  /// Widget disposal starts this barrier; the lease outlives disposal and all
  /// in-flight reads until the final progress write actually finishes.
  Future<void> closeReader() => _closingReader ??= _finishReader();
  Future<void> _finishReader() async {
    bool? saved;
    try {
      await Future.wait(_loads.toList());
      await _useOpening;
      await _progressOpening;
      await progress?.close();
      if (_progressActive) {
        saved = progress?.progressSaved;
        if (saved == null && _sample != null && library != null) saved = false;
      }
    } catch (_) {
      if (_progressActive) saved = false;
    } finally {
      await _bookUse?.release(progressSaved: saved);
      _bookUse = null;
    }
  }
}
