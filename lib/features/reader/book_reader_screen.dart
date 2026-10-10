import 'dart:async';
import '../../app/window_caption.dart';
import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/state_views.dart';
import '../novel_detail/catalog_controller.dart';
import 'reader_controller.dart';
import 'reader_preferences.dart';
import 'reader_theme.dart';
import 'position/position_resolver.dart';
import 'reader_screen.dart';
import 'viewport/page_turn.dart';
import '../cache/prefetch_sheet.dart';
import '../../shared/source_image.dart';
import 'reader_notes.dart';
import 'viewport/paged_reader_viewport.dart';
import 'reader_chrome.dart';
import 'reader_contents.dart';
import 'reader_panel.dart';
import '../../domain/local_chapter_progress.dart';
import 'reader_logical_progress.dart';

/// Owns one chapter session at a time; repositories outlive the route.
class BookReaderScreen extends StatefulWidget {
  const BookReaderScreen({
    super.key,
    required this.chapter,
    required this.repository,
    this.images,
    this.library,
    this.settings,
    this.chapterFallback = false,
    this.onDetails,
    this.cache,
    this.offline = false,
    this.initialBlockKey,
    this.initialBlockOffset,
    this.startAtBeginning = false,
    this.linkDepth = 0,
    this.onReturnToShelf,
  });
  final ChapterKey chapter;
  final NovelRepository repository;
  final ImageRepository? images;
  final LibraryRepository? library;
  final SettingsStore? settings;
  final bool chapterFallback;

  /// Opens the book's details over the reader and completes when they
  /// close; receives the reader's context to place them.
  final Future<void> Function(BuildContext readerContext, NovelKey key)?
  onDetails;
  final CacheManagement? cache;
  final bool offline;
  final String? initialBlockKey;
  final int? initialBlockOffset;
  final bool startAtBeginning;
  final int linkDepth;

  /// Closes the reader and whatever sits beneath it back to the shelf. The
  /// home decides what that means, e.g. also selecting the desktop shelf;
  /// without it the reader pops to the first route.
  final VoidCallback? onReturnToShelf;
  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late ReaderController _reader;
  final _viewports = <ReaderController, PagedReaderController>{};
  StreamSubscription<NovelKey>? _invalidation;
  bool _invalidated = false;
  ReaderController? _pending;
  _ChapterOperation? _operation;
  late final ReaderPreferences _preferences;
  Future<void>? _preferencesLoading;
  Future<void> get _preferencesReady =>
      _preferencesLoading ??= _preferences.load();
  ReaderPanelHandle<Object?>? _activePanel;
  bool _closingPanelForSwitch = false;
  late final ImageRepository? _candidateImages;
  ModalRoute<dynamic>? _route;
  double _turnGrip = pageTurnCentreGrip;
  ReaderController? _edgeSource;
  bool _edgeFirst = false, _edgeLast = false;
  int _lastDirection = 1;
  Object? _warmAttempt;
  bool _warmScheduled = false;
  (ChapterKey, AppFailure)? _preparationFailure;
  AppFailure? _rateLimit;

  bool _canPrepare(ChapterKey chapter) {
    final failed = _preparationFailure;
    if (failed == null) return true;
    final (key, failure) = failed;
    return failure.kind == FailureKind.rateLimited ||
        key != chapter ||
        failure.retryPolicy != RetryPolicy.never;
  }

  // Source cooldown restricts network work, never access to cached chapters.
  bool get _allowRemote {
    if (widget.offline) return false;
    final failure = _rateLimit;
    return failure == null ||
        failure.retryNotBefore != null &&
            !DateTime.now().isBefore(failure.retryNotBefore!);
  }

  void _preparationBlocked() {
    if (!mounted || _route?.isCurrent == false) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).readerChapterLoadFailed),
      ),
    );
  }

  void _edges(ReaderController reader, bool first, bool last) {
    if (reader != _reader) return;
    _edgeSource = reader;
    _edgeFirst = first;
    _edgeLast = last;
    _scheduleWarm();
  }

  void _scheduleWarm() {
    if (_warmScheduled) return;
    _warmScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmScheduled = false;
      if (!mounted ||
          _changing ||
          _invalidated ||
          _completion != null ||
          _completionTurn != null ||
          _leavingInsets != null ||
          _route?.isCurrent == false ||
          _edgeSource != _reader ||
          _reader.pagePresentation != null ||
          _viewports[_reader]?.isRestoring == true ||
          WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed) {
        return;
      }
      final direction = _edgeFirst && _edgeLast
          ? (_adjacent(_lastDirection) != null
                ? _lastDirection
                : -_lastDirection)
          : (_edgeLast ? 1 : -1);
      final chapter = _edgeFirst || _edgeLast ? _adjacent(direction) : null;
      final stamp = (
        _reader,
        chapter,
        direction,
        _readingSequence().$1,
        _viewports[_reader]?.layoutGeneration,
      );
      if (_warmAttempt == stamp) return;
      _warmAttempt = stamp;
      if (_operation?.intent != null &&
          _operation!.intent != _ChapterIntent.none) {
        return;
      }
      if (chapter == null) {
        _cancelChapter(immediate: true);
        return;
      }
      if (!_canPrepare(chapter)) return;
      setState(() {
        _prepare(
          chapter,
          direction: direction,
          passive: true,
          fromStart: direction > 0,
          fromEnd: direction < 0,
        );
      });
    });
  }

  bool get _visualTurn => _operation?.visible == true;
  bool _valid(_ChapterOperation operation) =>
      mounted &&
      identical(_operation, operation) &&
      identical(_reader, operation.source) &&
      operation.source.content == operation.sourceContent &&
      identical(_pending, operation.target) &&
      operation.intent != _ChapterIntent.cancelling &&
      !_invalidated &&
      _leavingInsets == null &&
      _route?.isCurrent != false &&
      identical(operation.basis, _readingSequence().$1);

  late final AnimationController _chapterTurn;
  int _turnDirection = 1;
  bool _animateChapter = false;
  bool _committing = false;
  Color _paper = ShioriReaderPaper.paper;
  PageTurnStyle _turnStyle = PageTurnStyle.curl;
  late final ImageRepository? _displayImages;
  late final CatalogController _catalog;

  /// Relays catalog changes to sheets, which may outlive [_catalog].
  final _catalogChanges = ValueNotifier(0);
  void _catalogChanged() => _catalogChanges.value++;
  bool get _local =>
      widget.chapter.novelKey.sourceId == LocalBookIdentity.sourceId;
  CacheManagement? get _cache => _local ? null : widget.cache;
  bool _changing = false, _canPop = false;
  bool _immersive = false;

  /// Insets frozen when leaving starts, so restoring the system bars during
  /// the exit transition cannot repaginate (and resample) the page.
  EdgeInsets? _leavingInsets;

  /// Brings the system bars back as soon as the reader starts to close
  /// rather than after the route transition has finished.
  void _restoreSystemUi() {
    if (!_immersive) return;
    _immersive = false;
    ReaderSystemUi.exit();
  }

  void _beginLeaving() {
    if (_leavingInsets == null) {
      final padding = MediaQuery.paddingOf(context);
      setState(() => _leavingInsets = padding);
    }
    _restoreSystemUi();
  }

  BookTerminalState? _completion;
  ({VoidCallback cancel, VoidCallback invalidate})? _completionTurn;
  final _titleRequest = CancellationSource();
  String? _bookTitle;
  NovelStatus _bookStatus = NovelStatus.unknown;
  List<ChapterKey>? _readingOrder;
  final _readingOrderChanges = ValueNotifier(0);
  final _navigation = <ChapterKey, List<(LocalNavigationEntry, int)>>{};
  Object _navigationRevision = Object();
  final _navigationTree = ValueNotifier<Result<List<LocalNavigationEntry>>?>(
    null,
  );
  Future<void> _loadNavigation() async {
    if (_local && widget.repository is LocalLogicalChapterRepository) {
      return _loadLogicalMetadata();
    }
    return _loadPhysicalNavigation();
  }

  LocalChapterProgressIndex? _logicalIndex;
  bool _logicalLoading = true, _logicalApplicable = true;
  Future<void>? _logicalRequest;
  Future<void> _loadLogicalMetadata() => _logicalRequest ??=
      _fetchLogicalMetadata().whenComplete(() => _logicalRequest = null);
  Future<void> _fetchLogicalMetadata() async {
    final result = await (widget.repository as LocalLogicalChapterRepository)
        .loadLogicalChapters(
          widget.chapter.novelKey,
          cancellation: _titleRequest.token,
        );
    if (!mounted || _invalidated || _titleRequest.token.isCancelled) return;
    setState(() {
      _logicalLoading = false;
      _logicalIndex = result is Success<LocalChapterProgressIndex?>
          ? result.value
          : null;
      _logicalApplicable =
          result is! Success<LocalChapterProgressIndex?> ||
          result.value != null;
      if (_logicalIndex case final index?) {
        _readingOrder = index.metrics.order;
        _navigationTree.value = Success(index.navigation);
        _navigation.clear();
        void collect(List<LocalNavigationEntry> entries, int depth) {
          for (final entry in entries) {
            _navigation.putIfAbsent(entry.chapterKey, () => []).add((
              entry,
              depth,
            ));
            collect(entry.children, depth + 1);
          }
        }

        collect(index.navigation, 0);
        _navigationRevision = Object();
      }
    });
    _readingOrderChanges.value++;
    if (_logicalIndex == null) {
      await Future.wait([_loadPhysicalNavigation(), _loadPhysicalOrder()]);
    }
  }

  Future<void> _loadPhysicalNavigation() async {
    final repository = widget.repository;
    if (!_local || repository is! LocalNavigationRepository) return;
    final result = await (repository as LocalNavigationRepository)
        .loadNavigation(
          widget.chapter.novelKey,
          cancellation: _titleRequest.token,
        );
    if (!mounted || _invalidated || _titleRequest.token.isCancelled) return;
    _navigationTree.value = result;
    if (result case Success<List<LocalNavigationEntry>>(:final value)) {
      void collect(List<LocalNavigationEntry> entries, int depth) {
        for (final entry in entries) {
          _navigation.putIfAbsent(entry.chapterKey, () => []).add((
            entry,
            depth,
          ));
          collect(entry.children, depth + 1);
        }
      }

      setState(() {
        _navigation.clear();
        collect(value, 0);
        _navigationRevision = Object();
      });
    }
  }

  // Rebuilds follow every session notification; recompute titles only when
  // an input (catalog snapshot, navigation, book title, chapter content)
  // actually changes.
  final _titles =
      Expando<
        ({
          Object? catalog,
          Object navigation,
          Object? order,
          String? book,
          Object? content,
          String? chapter,
          String? running,
        })
      >();
  (String?, String?) _titlesFor(ReaderController reader) {
    final catalog = _catalog.loaded?.value;
    final content = reader.content;
    final cached = _titles[reader];
    if (cached != null &&
        identical(cached.catalog, catalog) &&
        identical(cached.navigation, _navigationRevision) &&
        identical(cached.order, _readingOrder) &&
        cached.book == _bookTitle &&
        identical(cached.content, content)) {
      return (cached.chapter, cached.running);
    }
    final chapter = _scanChapterTitle(reader);
    final running = _scanRunningTitle(reader);
    _titles[reader] = (
      catalog: catalog,
      navigation: _navigationRevision,
      order: _readingOrder,
      book: _bookTitle,
      content: content,
      chapter: chapter,
      running: running,
    );
    return (chapter, running);
  }

  String? _chapterTitle(ReaderController reader) => _titlesFor(reader).$1;
  String? _runningTitle(ReaderController reader) => _titlesFor(reader).$2;

  String? _scanChapterTitle(ReaderController reader) {
    String? title;
    int? earliest;
    var deepest = -1;
    final blocks = reader.content!.blocks;
    // The EPUB navigation label is independent of the spine catalog's h1.
    // Prefer the chapter's earliest target, then its more specific child label
    // when a volume/group points to exactly the same position.
    for (final (entry, depth)
        in _navigation[reader.chapter] ??
            const <(LocalNavigationEntry, int)>[]) {
      if (entry.title.trim().isEmpty) continue;
      final index = entry.blockKey == null
          ? 0
          : blocks.indexWhere((block) => block.blockKey == entry.blockKey);
      if (index < 0) continue;
      if (earliest == null ||
          index < earliest ||
          index == earliest && depth > deepest) {
        title = entry.title;
        earliest = index;
        deepest = depth;
      }
    }
    return title ??
        _inheritedNavigationTitle(reader.chapter) ??
        _catalog.loaded?.value.flatChapters
            .where(
              (chapter) =>
                  chapter.key == reader.chapter &&
                  chapter.title.trim().isNotEmpty,
            )
            .firstOrNull
            ?.title;
  }

  /// A navigation target marks where a section starts, so a spine item
  /// without one of its own (e.g. the body after a chapter's title page)
  /// belongs to the nearest earlier target in reading order. Its own
  /// document title is often just the book's name.
  String? _inheritedNavigationTitle(ChapterKey chapter) {
    if (_navigation.isEmpty) return null;
    final (order, positions) = _readingSequence();
    final at = positions[chapter];
    if (at == null) return null;
    for (var i = at - 1; i >= 0; i--) {
      // Entries are collected in navigation order, so the last one is the
      // section still running at the end of that item.
      final entries = _navigation[order[i]];
      if (entries == null) continue;
      for (final (entry, _) in entries.reversed) {
        if (entry.title.trim().isNotEmpty) return entry.title;
      }
    }
    return null;
  }

  bool get _needsOrder =>
      _local && widget.repository is LocalContentLinkRepository;
  Future<void> _loadOrder() async {
    if (_local && widget.repository is LocalLogicalChapterRepository) {
      return _loadLogicalMetadata();
    }
    return _loadPhysicalOrder();
  }

  Future<void> _loadPhysicalOrder() async {
    if (!_needsOrder) return;
    final result = await (widget.repository as LocalContentLinkRepository)
        .loadReadingOrder(
          widget.chapter.novelKey,
          cancellation: _titleRequest.token,
        );
    if (!mounted || _invalidated || _titleRequest.token.isCancelled) return;
    if (result case Success<List<ChapterKey>>(:final value)) {
      setState(() => _readingOrder = value);
      _readingOrderChanges.value++;
    }
  }

  Future<void> _loadBookTitle() async {
    final result = await widget.repository.loadDetail(
      widget.chapter.novelKey,
      mode: ReadMode.cacheOnly,
      cancellation: _titleRequest.token,
    );
    if (!mounted || _titleRequest.token.isCancelled) return;
    if (result case Success<LoadResult<NovelDetail>>(:final value)) {
      setState(() {
        _bookTitle = value.value.summary.title;
        _bookStatus = value.value.status;
      });
    }
  }

  String? _scanRunningTitle(ReaderController reader) {
    for (final volume in _catalog.loaded?.value.volumes ?? <Volume>[]) {
      if (!volume.isSynthetic &&
          volume.title != null &&
          volume.chapters.any((c) => c.key == reader.chapter)) {
        return _bookTitle == null
            ? volume.title
            : '$_bookTitle · ${volume.title}';
      }
    }
    return _bookTitle;
  }

  @override
  void initState() {
    super.initState();
    _chapterTurn = AnimationController(
      vsync: this,
      duration: PaperTurnMotion.duration,
    );
    _preferences = ReaderPreferences(widget.settings);
    _candidateImages = widget.images == null
        ? null
        : _ReaderImages(widget.images!, cacheOnly: () => true);
    _displayImages = widget.images == null
        ? null
        : _ReaderImages(widget.images!, cacheOnly: () => !_allowRemote);
    WidgetsBinding.instance.addObserver(this);
    _catalog =
        CatalogController(
            repository: widget.repository,
            novel: widget.chapter.novelKey,
            initialMode: widget.offline
                ? ReadMode.cacheOnly
                : ReadMode.cacheFirst,
          )
          ..onStart()
          ..addListener(_changed)
          ..addListener(_catalogChanged);
    unawaited(_loadBookTitle());
    unawaited(_loadOrder());
    unawaited(_loadNavigation());
    _reader = _create(
      widget.chapter,
      blockKey: widget.initialBlockKey,
      blockOffset: widget.initialBlockOffset,
      fromStart: widget.startAtBeginning,
    );
    if (widget.repository case LocalBookInvalidation changes) {
      _invalidation = changes.invalidations.listen((key) {
        if (!mounted || key != widget.chapter.novelKey || _invalidated) return;
        _completionTurn?.invalidate();
        _cancelChapter(immediate: true);
        _reader.onDelete();
        _pending?.onDelete();
        // The failure page's contents would outlive the page behind it.
        _contentsPanel?.dismiss();
        _contentsPanel = null;
        setState(() => _invalidated = true);
      });
    }
    if (widget.chapterFallback) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).chapterFallback),
            ),
          );
        }
      });
    }
  }

  ReaderController _create(
    ChapterKey key, {
    String? blockKey,
    int? blockOffset,
    ReaderPosition? navigationPosition,
    bool fromStart = false,
    bool fromEnd = false,
    bool deferProgress = false,
    bool passive = false,
  }) =>
      ReaderController(
          repository: widget.repository,
          chapter: key,
          initialBlockKey: blockKey,
          initialBlockOffset: blockOffset,
          navigationPosition: navigationPosition,
          startAtBeginning: fromStart,
          startAtEnd: fromEnd,
          deferProgress: deferProgress,
          library: widget.linkDepth > 0 ? null : widget.library,
          cache: _cache,
          readMode: !_allowRemote || passive
              ? ReadMode.cacheOnly
              : ReadMode.cacheFirst,
          onPosition: widget.offline
              ? null
              : (position) {
                  if (_allowRemote) _cache?.prefetch?.position(position);
                },
        )
        ..onStart()
        ..addListener(_changed);
  void _changed() {
    if (_invalidated) return;
    final latestCatalog = _catalog.loaded?.value;
    if (_completion != null &&
        !_local &&
        latestCatalog != null &&
        latestCatalog.flatChapters.lastOrNull?.key != _reader.chapter) {
      _completion = null;
    }
    final pending = _pending;
    if (pending != null &&
        (pending.status == ReaderStatus.error ||
            pending.status == ReaderStatus.cancelled)) {
      final attempt = pending.restoreAttempt;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (pending.restoreAttempt == attempt) _rejectPending(pending);
      });
    }
    if (_allowRemote && _reader.content != null) {
      unawaited(
        _cache?.prefetch?.enter(_reader.content!, _catalog.loaded?.value),
      );
    }
    if (mounted) setState(() {});
  }

  void _close(ReaderController reader) {
    _viewports.remove(reader);
    reader.removeListener(_changed);
    reader.onDelete();
    reader.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enterSystemUi();
  }

  void _enterSystemUi() {
    if (!_immersive &&
        _leavingInsets == null &&
        ShioriCapabilities.of(context).immersiveSystemUi) {
      _immersive = true;
      ReaderSystemUi.enter();
    }
  }

  @override
  void dispose() {
    _contentsPanel?.dismiss();
    _contentsPanel = null;
    _restoreSystemUi();
    _invalidation?.cancel();
    _operation?.deadline?.cancel();
    _chapterTurn.dispose();
    _preferences.dispose();
    _titleRequest.cancel();
    if (!widget.offline) _cache?.prefetch?.leave();
    WidgetsBinding.instance.removeObserver(this);
    if (_pending case final pending?) _close(pending);
    _close(_reader);
    _catalog.removeListener(_changed);
    _catalog.removeListener(_catalogChanged);
    _catalogChanges.dispose();
    _catalog.onDelete();
    _catalog.dispose();
    _navigationTree.dispose();
    _readingOrderChanges.dispose();
    _chrome.dispose();
    super.dispose();
  }

  // The active ReaderContentView flushes its own session on lifecycle changes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancelChapter(immediate: true);
    if (!widget.offline) {
      _cache?.prefetch?.active(state == AppLifecycleState.resumed);
    }
  }

  Future<bool> _save([_ChapterOperation? operation]) async {
    final reader = _reader;
    await reader.flushProgress();
    if (!mounted ||
        reader != _reader ||
        operation != null && !_valid(operation)) {
      return false;
    }
    if (_reader.progress?.unsaved == true || _reader.progressFailure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).readerProgressUnsaved),
          action: SnackBarAction(
            label: AppLocalizations.of(context).retryAction,
            onPressed: _reader.retryProgress,
          ),
        ),
      );
      // Existing read-only/error exits remain possible without a tracker;
      // a new chapter must never take over through a failed save gate.
      return operation == null && _reader.progress == null;
    }
    return true;
  }

  ChapterKey? _adjacent(int direction) {
    if (widget.linkDepth > 0) return null;
    final (order, positions) = _readingSequence();
    final index = positions[_reader.chapter];
    if (index == null ||
        index + direction < 0 ||
        index + direction >= order.length) {
      return null;
    }
    return order[index + direction];
  }

  _ChapterOperation _prepare(
    ChapterKey chapter, {
    required int direction,
    bool passive = false,
    String? blockKey,
    int? blockOffset,
    ReaderPosition? navigationPosition,
    bool fromStart = false,
    bool fromEnd = false,
  }) {
    final existing = _operation;
    if (existing != null &&
        _valid(existing) &&
        existing.intent == _ChapterIntent.none &&
        existing.target.chapter == chapter &&
        existing.target.initialBlockKey == blockKey &&
        existing.target.initialBlockOffset == blockOffset &&
        existing.target.navigationPosition == navigationPosition &&
        existing.target.startAtBeginning == fromStart &&
        existing.target.startAtEnd == fromEnd) {
      if (!passive && existing.passive) {
        existing.passive = false;
        _armDeadline(existing);
        existing.target.readMode = !_allowRemote
            ? ReadMode.cacheOnly
            : ReadMode.cacheFirst;
        if (existing.target.status != ReaderStatus.ready) {
          existing.ready = false;
          // A passive cache miss is absence of prepared data, not a failed
          // foreground request subject to a non-retryable Source policy.
          if (existing.target.failure?.context == FailureContext.cacheMiss) {
            existing.target.failure = null;
          }
          unawaited(existing.target.load());
        }
      }
      return existing;
    }
    _cancelChapter(immediate: true);
    final target = _create(
      chapter,
      deferProgress: true,
      passive: passive,
      blockKey: blockKey,
      blockOffset: blockOffset,
      navigationPosition: navigationPosition,
      fromStart: fromStart,
      fromEnd: fromEnd,
    );
    final operation = _ChapterOperation(
      _reader,
      target,
      direction,
      passive: passive,
      basis: _readingSequence().$1,
    );
    _operation = operation;
    _pending = target;
    _armDeadline(operation);
    return operation;
  }

  void _armDeadline(_ChapterOperation operation) {
    operation.deadline?.cancel();
    if (operation.ready) return;
    // Also bounds layout preparation, including platform readiness callbacks.
    operation.deadline = Timer(const Duration(seconds: 45), () {
      if (!_valid(operation) || operation.ready) return;
      _rejectPending(operation.target, timedOut: true);
    });
  }

  BoundaryPageDrag? _beginChapterDrag(int direction, double grip) {
    if (_changing ||
        _invalidated ||
        _completion != null ||
        _route?.isCurrent == false) {
      return null;
    }
    final chapter = _adjacent(direction);
    if (chapter == null) return null;
    if (!_canPrepare(chapter)) {
      return BoundaryPageDrag(
        update: (_) {},
        cancel: () {},
        end: (commit) {
          if (commit) _preparationBlocked();
        },
      );
    }
    _lastDirection = direction;
    // Cancelling this explicit attempt must not immediately recreate the same
    // boundary candidate just because the host rebuilt.
    _warmAttempt = (
      _reader,
      chapter,
      direction,
      _readingSequence().$1,
      _viewports[_reader]?.layoutGeneration,
    );
    final operation = _prepare(
      chapter,
      direction: direction,
      fromStart: direction > 0,
      fromEnd: direction < 0,
    );
    setState(() {
      _changing = true;
      _animateChapter = true;
      _turnDirection = direction;
      _turnGrip = grip;
      operation.engaged = true;
      operation.intent = _ChapterIntent.dragging;
      operation.visible = operation.ready && _nativePair(operation);
    });
    return BoundaryPageDrag(
      update: (progress) {
        if (!_valid(operation) || operation.intent != _ChapterIntent.dragging) {
          return;
        }
        operation.progress = progress;
        if (operation.visible) _chapterTurn.value = progress;
      },
      end: (commit) {
        if (!_valid(operation) || operation.intent != _ChapterIntent.dragging) {
          return;
        }
        if (commit) {
          unawaited(_confirmChapter(operation));
        } else {
          unawaited(_cancelChapter());
        }
      },
      cancel: () {
        if (identical(_operation, operation)) unawaited(_cancelChapter());
      },
    );
  }

  bool _nativePair(_ChapterOperation operation) =>
      operation.source.pagePresentation == null &&
      operation.target.pagePresentation == null;

  Future<void> _switch(
    ChapterKey chapter, {
    String? blockKey,
    int? blockOffset,
    ReaderPosition? navigationPosition,
    bool fromStart = false,
    bool fromEnd = false,
  }) async {
    _completionTurn?.invalidate();
    if (_closingPanelForSwitch) return;
    if (_route?.isCurrent == false) {
      final panel = _activePanel;
      if (panel == null || !panel.isValid || !panel.route.isCurrent) return;
      final source = _reader;
      _closingPanelForSwitch = true;
      panel.dismiss();
      WidgetsBinding.instance.scheduleFrame();
      await panel.completed;
      _closingPanelForSwitch = false;
      if (!mounted || _reader != source || _route?.isCurrent == false) return;
    }
    if (_changing ||
        _invalidated ||
        chapter == _reader.chapter &&
            blockKey == null &&
            !fromStart &&
            _completion == null ||
        chapter.novelKey != widget.chapter.novelKey) {
      return;
    }
    if (!_canPrepare(chapter)) {
      _preparationBlocked();
      return;
    }
    final (_, positions) = _readingSequence();
    final currentIndex = positions[_reader.chapter],
        targetIndex = positions[chapter];
    final direction =
        currentIndex != null &&
            targetIndex != null &&
            currentIndex != targetIndex
        ? (targetIndex > currentIndex ? 1 : -1)
        : (fromEnd ? -1 : 1);
    final operation = _prepare(
      chapter,
      direction: direction,
      blockKey: blockKey,
      blockOffset: blockOffset,
      navigationPosition: navigationPosition,
      fromStart: fromStart,
      fromEnd: fromEnd,
    );
    _animateChapter = fromStart || fromEnd;
    _turnDirection = direction;
    _turnGrip = pageTurnCentreGrip;
    await _confirmChapter(operation);
  }

  Future<void> _confirmChapter(_ChapterOperation operation) async {
    if (!_valid(operation) ||
        operation.intent == _ChapterIntent.confirmed ||
        operation.intent == _ChapterIntent.settling) {
      return;
    }
    setState(() {
      operation.engaged = true;
      operation.intent = _ChapterIntent.confirmed;
      _changing = true;
    });
    if (operation.target.status == ReaderStatus.error ||
        operation.target.status == ReaderStatus.cancelled) {
      _rejectPending(operation.target);
      return;
    }
    final saved = await _save(operation);
    if (!_valid(operation)) return;
    if (!saved) {
      await _cancelChapter();
      return;
    }
    operation.saved = true;
    await _commitPending(operation.target);
  }

  void _targetReady(ReaderController reader) {
    final operation = _operation;
    if (operation == null || !_valid(operation) || operation.target != reader) {
      return;
    }
    if (reader.navigationPosition case final position?
        when position.contentRevision != reader.content?.contentRevision) {
      _rejectPending(reader);
      return;
    }
    setState(() {
      operation.ready = true;
      operation.readyContent = reader.content;
      operation.readyLayout = _viewports[reader]?.layoutGeneration;
      operation.deadline?.cancel();
      if (operation.intent == _ChapterIntent.dragging &&
          _nativePair(operation)) {
        operation.visible = true;
        _chapterTurn.value = operation.progress;
      }
    });
    unawaited(_commitPending(reader));
  }

  // Called during layout. Invalidate synchronously; defer mutations of the
  // widget tree until the frame is finished. No old ready can pass the gate.
  void _layoutInvalidated(ReaderController reader) {
    final operation = _operation;
    if (operation == null) return;
    if (reader == operation.target) operation.ready = false;
    if (!operation.visible && reader != operation.source) return;
    // A source geometry change invalidates its boundary/width even while
    // waiting for an unready target. Candidate-only initial layout may proceed.
    operation.intent = _ChapterIntent.cancelling;
    _chapterTurn.stop(canceled: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_operation, operation)) {
        _cancelChapter(immediate: true);
      }
    });
  }

  Future<void> _commitPending(ReaderController reader) async {
    final operation = _operation;
    if (operation == null ||
        !_valid(operation) ||
        operation.target != reader ||
        operation.intent != _ChapterIntent.confirmed ||
        !operation.ready ||
        !operation.saved ||
        operation.readyContent != reader.content ||
        operation.readyLayout != _viewports[reader]?.layoutGeneration ||
        _viewports[reader]?.isRestoring == true ||
        _committing) {
      return;
    }
    setState(() {
      _committing = true;
      operation.intent = _ChapterIntent.settling;
      operation.visible = true;
    });
    try {
      await PaperTurnMotion.settle(
        _chapterTurn,
        curve: _chapterFrame.curve,
        reduced:
            !_animateChapter ||
            _turnStyle == PageTurnStyle.none ||
            MediaQuery.disableAnimationsOf(context),
      );
    } on TickerCanceled {
      if (identical(_operation, operation) &&
          operation.intent != _ChapterIntent.cancelling) {
        await _cancelChapter(immediate: true);
      }
      return;
    }
    if (!_valid(operation) ||
        !operation.ready ||
        operation.readyContent != reader.content ||
        operation.readyLayout != _viewports[reader]?.layoutGeneration ||
        _viewports[reader]?.isRestoring == true) {
      if (identical(_operation, operation) &&
          operation.intent != _ChapterIntent.cancelling) {
        await _cancelChapter(immediate: true);
      }
      return;
    }
    operation.deadline?.cancel();
    final previous = _reader;
    setState(() {
      _reader = reader;
      _completion = null;
      _pending = null;
      _operation = null;
      _committing = false;
      _chapterTurn.value = 0;
      _changing = false;
    });
    _close(previous);
    if (_allowRemote && reader.content != null) {
      unawaited(
        _cache?.prefetch?.enter(reader.content!, _catalog.loaded?.value),
      );
    }
    reader.activateProgress();
  }

  Future<void> _cancelChapter({bool immediate = false}) {
    final operation = _operation;
    if (!mounted || operation == null) return Future.value();
    // Repeated input shares the current rebound. Lifecycle cancellation may
    // supersede it; an interrupted animation must never clean up its successor.
    if (!immediate && operation.cancellation != null) {
      return operation.cancellation!;
    }
    final phase = ++operation.cancelPhase;
    return operation.cancellation = _cancelOperation(
      operation,
      phase,
      immediate,
    );
  }

  Future<void> _cancelOperation(
    _ChapterOperation operation,
    int phase,
    bool immediate,
  ) async {
    setState(() => operation.intent = _ChapterIntent.cancelling);
    operation.deadline?.cancel();
    _chapterTurn.stop(canceled: true);
    if (!immediate && operation.visible && mounted) {
      try {
        await PaperTurnMotion.settle(
          _chapterTurn,
          target: 0,
          curve: _chapterFrame.curve,
          reduced:
              _turnStyle == PageTurnStyle.none ||
              MediaQuery.disableAnimationsOf(context),
        );
      } on TickerCanceled {
        // The newer cancellation owns cleanup below.
      }
    }
    if (!mounted ||
        !identical(_operation, operation) ||
        operation.cancelPhase != phase) {
      return;
    }
    setState(() {
      _operation = null;
      _pending = null;
      if (operation.engaged) _changing = false;
      _committing = false;
      _chapterTurn.value = 0;
    });
    _close(operation.target);
  }

  void _rejectPending(ReaderController reader, {bool timedOut = false}) {
    final operation = _operation;
    if (operation == null || !_valid(operation) || operation.target != reader) {
      return;
    }
    if (reader.failure case final failure?
        when failure.context != FailureContext.cacheMiss &&
            !failure.isCancellation) {
      _preparationFailure = (reader.chapter, failure);
      if (failure.kind == FailureKind.rateLimited) _rateLimit = failure;
    }
    if (operation.intent == _ChapterIntent.none ||
        operation.intent == _ChapterIntent.dragging) {
      operation.ready = false;
      operation.deadline?.cancel();
      if (timedOut) unawaited(_cancelChapter(immediate: true));
      return;
    }
    final target = reader.chapter;
    final blockKey = reader.initialBlockKey,
        blockOffset = reader.initialBlockOffset;
    final fromStart = reader.startAtBeginning, fromEnd = reader.startAtEnd;
    final failure = reader.failure;
    unawaited(_cancelChapter());
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.readerChapterLoadFailed),
        action: failure?.retryPolicy == RetryPolicy.never
            ? null
            : SnackBarAction(
                label: l.retryAction,
                onPressed: () {
                  if (failure?.kind == FailureKind.rateLimited &&
                      (failure?.retryNotBefore == null ||
                          DateTime.now().isBefore(failure!.retryNotBefore!))) {
                    return;
                  }
                  _switch(
                    target,
                    blockKey: blockKey,
                    blockOffset: blockOffset,
                    fromStart: fromStart,
                    fromEnd: fromEnd,
                  );
                },
              ),
      ),
    );
  }

  /// Toolbar visibility shared with the active page so back can close it.
  final _chrome = ValueNotifier(false);

  /// Android back first closes the toolbars; the interactive Cupertino swipe
  /// is always a deliberate exit and must be allowed before it starts.
  bool _backClosesChrome(BuildContext context) =>
      !ShioriCapabilities.of(context).cupertinoNavigation;

  /// Leaving directly keeps system back animations (Android predictive back,
  /// the iOS swipe); it is only held back to close the toolbars or while
  /// progress is known to be unsaved, where [_exit] saves and warns first.
  bool _backLeaves(BuildContext context, bool chromeVisible) {
    if (_canPop || ShioriCapabilities.of(context).cupertinoNavigation) {
      return true;
    }
    if (chromeVisible || _completionTurn != null) return false;
    return !_changing &&
        _reader.progressFailure == null &&
        _reader.progress?.unsaved != true;
  }

  /// After a direct pop, persist the last samples and surface a failed save
  /// on the screen underneath instead of losing it silently.
  Future<void> _flushAfterPop() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l = AppLocalizations.of(context);
    final reader = _reader;
    await reader.flushProgress();
    if (reader.progress?.unsaved == true || reader.progressFailure != null) {
      messenger?.showSnackBar(SnackBar(content: Text(l.readerProgressUnsaved)));
    }
  }

  Future<void> _exit({bool toShelf = false}) async {
    if (_completionTurn case final turn?) {
      turn.cancel();
      return;
    }
    if (_operation case final operation?) {
      final wasInteraction = operation.engaged;
      await _cancelChapter(immediate: true);
      if (wasInteraction) return;
    }
    if (_changing || _canPop) return;
    setState(() => _changing = true);
    final saved = await _save();
    if (!mounted) return;
    setState(() {
      _changing = false;
      _canPop = saved;
    });
    if (saved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _beginLeaving();
          if (toShelf) {
            if (widget.onReturnToShelf case final returnToShelf?) {
              returnToShelf();
            } else {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          } else {
            Navigator.of(context).pop();
          }
        }
      });
    }
  }

  /// The chapter's notes in the page's panel slot: a side panel on desktop,
  /// the sheet elsewhere. The chosen link is followed once the notes have
  /// closed, only if the page still reads [_reader] and takes commands.
  Future<void> _links(ReaderPanels panels) async {
    if (_changing || _invalidated) return;
    final source = _reader;
    // Targets are named from this reader's navigation only while it still
    // reads [source]; the links themselves are the chapter's snapshot.
    String? titleOf(ChapterKey target) =>
        mounted && !_invalidated && source == _reader
        ? _navigation[target]?.first.$1.title
        : null;
    final LocalContentLink? link;
    if (panels.desktop) {
      final panel = panels.open<LocalContentLink>(
        ReaderPanelPlacement.end,
        semanticLabel: AppLocalizations.of(context).readerLinks,
        builder: (context, panel) => ReaderNotesPanel(
          links: source.contentLinks,
          current: source.chapter,
          titleOf: titleOf,
          onFollow: panel.close,
          onClose: () => panel.close(),
        ),
      );
      if (panel == null) return;
      link = await panel.closed;
    } else {
      // Shown from the page's context so the sheet takes its paper theme.
      link = await showReaderNotes(
        panels.context,
        links: source.contentLinks,
        current: source.chapter,
        titleOf: titleOf,
      );
    }
    if (link == null ||
        !mounted ||
        !panels.live ||
        _invalidated ||
        _changing ||
        source != _reader) {
      return;
    }
    if (link.isFootnote) {
      await panels.footnote(link);
      return;
    }
    await _followContentLink(link);
  }

  /// Prefetch settings for [source]: the sheet on phones and tablets, a side
  /// panel on desktop. Closing either leaves downloads running. From the
  /// panel, cache management opens above the reader once the panel has
  /// closed, only if the page still reads [source] and takes commands.
  Future<void> _prefetch(ReaderPanels panels, ReaderController source) async {
    final cache = _cache;
    if (cache?.prefetch == null) return;
    if (!panels.desktop) {
      return showPrefetchSheet(
        context,
        cache: cache!,
        catalog: _catalog.loaded?.value,
        current: source.chapter,
      );
    }
    if (_changing || _invalidated) return;
    final panel = panels.open<bool>(
      ReaderPanelPlacement.end,
      semanticLabel: AppLocalizations.of(context).prefetchTitle,
      builder: (context, panel) => PrefetchPanel(
        cache: cache!,
        catalog: _catalog.loaded?.value,
        current: source.chapter,
        onClose: () => panel.close(),
        onManage: () => panel.close(true),
      ),
    );
    if (panel == null) return;
    final manage = await panel.closed;
    if (manage != true ||
        !mounted ||
        !panels.live ||
        _invalidated ||
        _changing ||
        source != _reader) {
      return;
    }
    await Navigator.of(context).push(cacheManagementRoute(context, cache!));
  }

  Future<void> _followContentLink(LocalContentLink link) async {
    if (_changing || _invalidated) return;
    if (link.target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).readerLinkUnavailable),
        ),
      );
      return;
    }
    await _followContentTarget(
      link.target!,
      link.targetBlockKey,
      link.targetOffset,
    );
  }

  Future<void> _followContentTarget(
    ChapterKey target,
    String? blockKey, [
    int? blockOffset,
  ]) async {
    if (_changing ||
        _invalidated ||
        target.novelKey != widget.chapter.novelKey) {
      return;
    }
    if (target == _reader.chapter) {
      final content = _reader.content!;
      final index = blockKey == null
          ? 0
          : content.blocks.indexWhere((b) => b.blockKey == blockKey);
      if (index < 0) return;
      _reader.beginPositionNavigation();
      setState(() => _completion = null);
      final fraction = readerTargetFraction(content.blocks[index], blockOffset);
      _viewports[_reader]?.restore(
        ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks[index].blockKey,
          blockIndex: index,
          blockFraction: fraction,
          chapterFraction: ReaderPosition.fractionFor(
            blockIndex: index,
            blockFraction: fraction,
            blockCount: content.blocks.length,
          ),
        ),
      );
      return;
    }
    final source = _reader;
    if (_needsOrder && _readingOrder == null) await _loadOrder();
    if (!mounted || _invalidated || _changing || source != _reader) return;
    final main = _needsOrder
        ? _readingOrder?.contains(target) == true
        : _catalog.loaded?.value.flatChapters.any((c) => c.key == target) ==
              true;
    if (main) {
      await _switch(
        target,
        blockKey: blockKey,
        blockOffset: blockOffset,
        fromStart: true,
      );
    } else {
      await _openAuxiliary(target, blockKey, blockOffset);
    }
  }

  Future<void> _navigateLogical(
    ReaderController source,
    LocalChapterProgressIndex? basis,
    LocalChapterSection section,
    LocalChapterTarget target,
  ) async {
    if (!mounted ||
        _invalidated ||
        _changing ||
        source != _reader ||
        source.isClosed ||
        _route?.isCurrent == false ||
        basis == null ||
        !identical(basis, _logicalIndex) ||
        !basis.sections.contains(section) ||
        !section.reliable ||
        basis.documents[source.chapter]?.matches(source.content!) != true ||
        basis.documents[target.chapter]?.revision !=
            target.position.contentRevision) {
      return;
    }
    if (target.chapter == source.chapter) {
      source.beginPositionNavigation();
      setState(() => _completion = null);
      _viewports[source]?.restore(target.position);
    } else {
      await _switch(
        target.chapter,
        navigationPosition: target.position,
        fromStart: true,
      );
    }
  }

  /// Set while a link is being validated for an auxiliary reader, so a
  /// repeated activation opens it once.
  bool _openingLink = false;

  Future<void> _openAuxiliary(
    ChapterKey target,
    String? block,
    int? blockOffset,
  ) async {
    if (_openingLink) return;
    if (widget.linkDepth >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).readerLinkDepth)),
      );
      return;
    }
    if (_invalidated ||
        target.novelKey != widget.chapter.novelKey ||
        widget.linkDepth >= 8) {
      return;
    }
    // Validate before replacing any surface; failed targets leave origin intact.
    _openingLink = true;
    final Result<LoadResult<ChapterContent>> value;
    try {
      value = await widget.repository.loadChapter(
        target,
        mode: ReadMode.cacheOnly,
        cancellation: _titleRequest.token,
      );
    } finally {
      _openingLink = false;
    }
    // A reader covered meanwhile, e.g. by another link's reader, opens none.
    if (!mounted || _invalidated || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (value is! Success<LoadResult<ChapterContent>> ||
        block != null &&
            !value.value.value.blocks.any((b) => b.blockKey == block)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).readerLinkUnavailable),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      platformPageRoute<void>(
        context,
        settings: const RouteSettings(name: '/local-link'),
        builder: (_) => BookReaderScreen(
          chapter: target,
          repository: widget.repository,
          images: widget.images,
          settings: widget.settings,
          initialBlockKey: block,
          initialBlockOffset: blockOffset,
          startAtBeginning: true,
          linkDepth: widget.linkDepth + 1,
          onReturnToShelf: widget.onReturnToShelf,
        ),
      ),
    );
  }

  bool get _localNavigation =>
      _local && widget.repository is LocalNavigationRepository;

  /// Book-level contents, served from the navigation this reader already
  /// loaded: the local EPUB / TXT tree, or the source's volume catalog
  /// (cache-only while offline). Called during build, so it stays pure; a
  /// reparse invalidates this reader rather than relabelling it in place.
  ReaderContentsLayer _bookContents(BuildContext context) {
    if (_localNavigation) {
      return localContentsLayer(
        context,
        navigation: _navigationTree,
        readingOrder: () => _readingSequence().$1,
        readingOrderChanges: Listenable.merge([
          _readingOrderChanges,
          _catalogChanges,
        ]),
        current: _reader.chapter,
        selectedEntry: _logicalIndex
            ?.sectionAt(_reader.chapter, _viewports[_reader]?.capture())
            ?.entry,
        onRetry: _loadNavigation,
        onSelect: (target) {
          if (mounted) _followContentTarget(target.chapterKey, target.blockKey);
        },
      );
    }
    return volumeContentsLayer(
      context,
      catalog: _catalog,
      changes: _catalogChanges,
      current: _reader.chapter,
      onRetry: _retryCatalog,
      onRefresh: widget.offline ? null : _catalog.refreshCatalog,
      onSelect: (key) {
        if (mounted) _switch(key);
      },
    );
  }

  /// Retries keep this reader's read mode: offline never leaves the cache;
  /// online reloads a missing catalog cache-first and refreshes a loaded one.
  void _retryCatalog() {
    if (widget.offline) {
      unawaited(_catalog.load(mode: ReadMode.cacheOnly));
    } else if (_catalog.loaded == null) {
      unawaited(_catalog.load());
    } else {
      unawaited(_catalog.refreshCatalog());
    }
  }

  /// The contents panel opened from the failure page on desktop. It keeps
  /// the app theme, as the page around it does.
  ReaderPanelHandle<VoidCallback>? _contentsPanel;

  Future<void> _contents() async {
    if (!ShioriCapabilities.of(context).pointerFirst) {
      return showReaderContents(context, layers: [_bookContents(context)]);
    }
    if (_contentsPanel != null || _invalidated) return;
    final layer = _bookContents(context);
    final panel = ReaderPanelHandle<VoidCallback>.open(
      this,
      placement: ReaderPanelPlacement.start,
      semanticLabel: layer.label,
      builder: (context, panel) => ReaderContentsPanel(
        layers: [layer],
        closeButton: true,
        onDone: ([then]) {
          if (mounted && panel.isValid && identical(_contentsPanel, panel)) {
            panel.close(then);
          }
        },
      ),
    );
    _contentsPanel = panel;
    // The selection is applied once the panel has closed, unless the book
    // was invalidated, which retires the panel, meanwhile.
    final then = await panel.closed;
    if (identical(_contentsPanel, panel)) _contentsPanel = null;
    if (then != null && mounted && !_invalidated) then();
  }

  Future<void> _details() async {
    if (_changing || widget.onDetails == null) return;
    setState(() => _changing = true);
    if (!await _save()) {
      if (mounted) setState(() => _changing = false);
      return;
    }
    if (!mounted) return;
    // Details cover the reader: bring the system bars back for them now,
    // with the page insets frozen so the covered reader keeps its layout.
    _beginLeaving();
    await widget.onDetails!(context, widget.chapter.novelKey);
    // Back from details returns here; a reader replaced by a new one
    // from details is no longer active and stays as it is.
    if (!mounted || !(ModalRoute.of(context)?.isActive ?? false)) return;
    setState(() {
      _leavingInsets = null;
      _changing = false;
    });
    _enterSystemUi();
  }

  // Rebuilds follow every session notification; derive the reading order
  // and its index only when the catalog or local order actually changes.
  (Object?, List<ChapterKey>, Map<ChapterKey, int>)? _order;
  (List<ChapterKey>, Map<ChapterKey, int>) _readingSequence() {
    final Object? source = _needsOrder ? _readingOrder : _catalog.loaded?.value;
    if (_order case (
      final cached,
      final order,
      final index,
    ) when identical(cached, source)) {
      return (order, index);
    }
    final order = _needsOrder
        ? _readingOrder ?? <ChapterKey>[]
        : [
            for (final c in _catalog.loaded?.value.flatChapters ?? <Chapter>[])
              c.key,
          ];
    // First occurrence wins, matching the previous indexOf lookup.
    final index = <ChapterKey, int>{};
    for (final (i, key) in order.indexed) {
      index.putIfAbsent(key, () => i);
    }
    _order = (source, order, index);
    return (order, index);
  }

  Widget _view(ReaderController reader, {required bool active}) {
    final logicalBasis = _logicalIndex;
    final (order, positions) = _readingSequence();
    final index = positions[reader.chapter] ?? -1;
    final previous = index > 0 && widget.linkDepth == 0
        ? order[index - 1]
        : null;
    final next = index >= 0 && index + 1 < order.length && widget.linkDepth == 0
        ? order[index + 1]
        : null;

    final terminal =
        !_changing &&
            widget.linkDepth == 0 &&
            index >= 0 &&
            index == order.length - 1
        ? bookEndState(
            local: _local,
            status: reader.novelStatus == NovelStatus.unknown
                ? _bookStatus
                : reader.novelStatus,
          )
        : null;
    bool bookEnd() {
      if (!mounted ||
          _invalidated ||
          _changing ||
          _route?.isCurrent == false ||
          _completion != null ||
          reader != _reader ||
          reader.isClosed ||
          terminal == null ||
          !identical(order, _readingSequence().$1) ||
          _viewports[reader]?.isRestoring == true) {
        return false;
      }
      final state = bookEndState(
        local: _local,
        status: reader.novelStatus == NovelStatus.unknown
            ? _bookStatus
            : reader.novelStatus,
      );
      _cancelChapter(immediate: true);
      setState(() => _completion = state);
      reader.enterBookEnd(state);
      unawaited(reader.flushProgress());
      return true;
    }

    final actions = ReaderActions(
      completionPrevious: () => setState(() => _completion = null),
      exitToShelf: () => _exit(toShelf: true),
      restart: order.isEmpty
          ? null
          : () => _switch(order.first, fromStart: true),
      bookEnd: terminal == null ? null : bookEnd,
      contentLink: _changing ? null : _followContentLink,
      bookContents: _changing || widget.linkDepth > 0 ? null : _bookContents,
      links: _changing || reader.contentLinks.isEmpty ? null : _links,
      leave: () => unawaited(_exit()),
      prefetch: !widget.offline && _cache?.prefetch != null
          ? (panels) => unawaited(_prefetch(panels, reader))
          : null,
      details: widget.onDetails == null || _changing ? null : _details,
      previousChapter: !_changing && previous != null
          ? () => _switch(previous, fromEnd: true)
          : null,
      nextChapter: !_changing && next != null
          ? () => _switch(next, fromStart: true)
          : null,
    );

    return ReaderContentView(
      key: ValueKey(reader),
      content: reader.content!,
      logicalProgress:
          _local &&
              widget.repository is LocalLogicalChapterRepository &&
              _logicalApplicable
          ? ReaderLogicalProgress(
              loading: _logicalLoading,
              index:
                  _logicalIndex?.documents[reader.chapter]?.matches(
                            reader.content!,
                          ) ==
                          true &&
                      (_catalog.loaded == null ||
                          _catalog.loaded!.value.revision ==
                              _logicalIndex!.metrics.revision)
                  ? _logicalIndex
                  : null,
              navigate: (section, target) =>
                  _navigateLogical(reader, logicalBasis, section, target),
            )
          : null,
      completion: reader == _reader ? _completion : null,
      completionTarget: terminal,
      completionBasis: (reader, order, terminal),
      bookTitle: _bookTitle ?? reader.progress?.snapshot.title,
      onCompletionTurn: (turn) {
        if (!mounted || reader != _reader) return;
        if (turn != null) _cancelChapter(immediate: true);
        setState(() => _completionTurn = turn);
      },
      actions: actions,
      onReady: () => _targetReady(reader),
      onCancelChapter: active && _changing && _operation != null
          ? () => _cancelChapter()
          : null,
      onPanelChanged: (panel) {
        if (reader == _reader) _activePanel = panel;
      },
      onLayoutInvalidated: () => _layoutInvalidated(reader),
      onBoundaryDrag: active ? _beginChapterDrag : null,
      onEdges: active ? (first, last) => _edges(reader, first, last) : null,
      crossChapterTurning: _visualTurn,
      preferences: _preferences,
      preferencesReady: _preferencesReady,
      onPageAppearance: (paper, turn) {
        if (reader == _reader) {
          _paper = paper;
          _turnStyle = turn;
        }
      },
      onLoadFailure: () => _rejectPending(reader),
      runningTitle: _runningTitle(reader),
      chapterTitle: _chapterTitle(reader),
      images: reader == _pending && _operation?.passive == true
          ? _candidateImages
          : _displayImages,
      audioFactory: widget.images is AudioPlaybackFactory
          ? widget.images as AudioPlaybackFactory
          : null,
      settings: widget.settings,
      session: reader,
      viewportController: _viewports.putIfAbsent(
        reader,
        PagedReaderController.new,
      ),
      initialPosition: reader.initialPosition,
      articleContents: !_local,
      returnToOrigin: widget.linkDepth > 0,
      chrome: _chrome,
      active: active && !_changing,
      appearanceActive: active && identical(reader, _reader),
    );
  }

  PageTurnFrame get _chapterFrame => PageTurnFrame(
    style: _turnStyle,
    progress: _chapterTurn.value,
    direction: _turnDirection,
    grip: _turnGrip,
  );

  Widget _pageLayer(ReaderController reader, {required bool active}) =>
      Positioned.fill(
        key: ValueKey(reader),
        child: IgnorePointer(
          ignoring:
              !active ||
              _changing && _operation?.intent != _ChapterIntent.dragging,
          child: AnimatedBuilder(
            animation: _chapterTurn,
            child: ExcludeSemantics(
              excluding: !active,
              child: ExcludeFocus(
                excluding: !active,
                child: _view(reader, active: active),
              ),
            ),
            builder: (context, child) => Offstage(
              offstage: !active && !_visualTurn,
              child: PageTurnSlot(
                frame: _chapterFrame,
                role: active ? PageTurnRole.leaving : PageTurnRole.entering,
                child: child!,
              ),
            ),
          ),
        ),
      );

  /// The chapter being turned away from and the one being turned to, in
  /// paint order for the current style.
  List<Widget> _chapterLayers() {
    final pending = _pending;
    final ready =
        pending != null &&
        pending.status == ReaderStatus.ready &&
        (pending.pagePresentation == null ||
            _operation?.intent == _ChapterIntent.confirmed ||
            _operation?.intent == _ChapterIntent.settling);
    final leaving = _pageLayer(_reader, active: true);
    if (!ready) return [leaving];
    final entering = _pageLayer(pending, active: false);
    final shade = Positioned.fill(
      child: AnimatedBuilder(
        animation: _chapterTurn,
        builder: (context, _) => PageTurnShade(frame: _chapterFrame),
      ),
    );
    return _chapterFrame.enteringOnTop
        ? [leaving, shade, entering]
        : [entering, shade, leaving];
  }

  Widget _chapterWaitBar() => ListenableBuilder(
    listenable: _preferences,
    builder: (context, _) {
      final theme = readerTheme(
        _preferences.value,
        MediaQuery.platformBrightnessOf(context),
        accent: appAccentOf(context),
      );
      return Theme(
        data: theme,
        child: Material(
          color: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Icon(
                    Icons.hourglass_top,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(AppLocalizations.of(context).loading)),
                TextButton(
                  key: const ValueKey('cancel-chapter-turn'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                  ),
                  onPressed: () => _cancelChapter(),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) =>
      WindowCaptionScope.appDefault(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    _route = ModalRoute.of(context);
    _scheduleWarm();
    if (_operation case final operation?
        when !identical(operation.basis, _readingSequence().$1)) {
      operation.intent = _ChapterIntent.cancelling;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_operation, operation)) {
          _cancelChapter(immediate: true);
        }
      });
    }
    if (_route?.isCurrent == false && _operation != null) {
      final operation = _operation!;
      operation.intent = _ChapterIntent.cancelling;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_operation, operation)) {
          _cancelChapter(immediate: true);
        }
      });
    }
    if (_invalidated) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(AppLocalizations.of(context).localReparseReaderClosed),
          ),
        ),
      );
    }

    final screen = SourceImageDecodeScope(
      child: ValueListenableBuilder<bool>(
        valueListenable: _chrome,
        builder: (context, chromeVisible, child) => PopScope(
          canPop: _backLeaves(context, chromeVisible),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              _completionTurn?.invalidate();
              _cancelChapter(immediate: true);
              _beginLeaving();
              unawaited(_flushAfterPop());
            } else if (_completionTurn case final turn?) {
              turn.cancel();
            } else if (chromeVisible && _backClosesChrome(context)) {
              _chrome.value = false;
            } else {
              unawaited(_exit());
            }
          },
          child: child!,
        ),
        child: _reader.status == ReaderStatus.ready
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ..._chapterLayers(),
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _chapterTurn,
                      builder: (context, _) =>
                          PageTurnOverlay(frame: _chapterFrame, paper: _paper),
                    ),
                  ),
                  if (_operation?.intent == _ChapterIntent.confirmed)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 32,
                      child: SafeArea(child: _chapterWaitBar()),
                    ),
                ],
              )
            : Scaffold(
                appBar: AppBar(
                  title: Text(AppLocalizations.of(context).readerTitle),
                  actions: [
                    if (widget.onDetails != null)
                      IconButton(
                        tooltip: AppLocalizations.of(context).novelDetailsTitle,
                        onPressed: _changing ? null : _details,
                        icon: const Icon(Icons.info_outline),
                      ),
                  ],
                ),
                body: SafeArea(
                  child: _reader.status == ReaderStatus.loading
                      ? const LoadingView()
                      : _reader.failure != null
                      ? FailureView(
                          failure: _reader.failure!,
                          onRetry: _reader.load,
                          onBack: _contents,
                        )
                      : TextButton(
                          onPressed: _reader.load,
                          child: Text(AppLocalizations.of(context).retryAction),
                        ),
                ),
              ),
      ),
    );
    // Always wrapped, so freezing the insets never remounts the pages: a
    // remounted page restarts from where the chapter was opened and saves
    // that over the reading position.
    return _FrozenInsets(insets: _leavingInsets, child: screen);
  }
}

/// The page insets, frozen to [insets] while the reader closes or is
/// covered by details.
class _FrozenInsets extends StatelessWidget {
  const _FrozenInsets({required this.insets, required this.child});
  final EdgeInsets? insets;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final frozen = insets;
    return MediaQuery(
      data: frozen == null
          ? media
          : media.copyWith(padding: frozen, viewPadding: frozen),
      child: child,
    );
  }
}

class _ReaderImages implements ImageRepository {
  _ReaderImages(this.inner, {required this.cacheOnly});
  final ImageRepository inner;
  final bool Function() cacheOnly;
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => inner.load(
    ref,
    mode: cacheOnly() ? ReadMode.cacheOnly : mode,
    cancellation: cancellation,
  );
}

enum _ChapterIntent { none, dragging, confirmed, cancelling, settling }

/// Identity is the operation token; every async continuation checks it.
class _ChapterOperation {
  _ChapterOperation(
    this.source,
    this.target,
    this.direction, {
    required this.passive,
    required this.basis,
  }) : sourceContent = source.content;
  final ReaderController source, target;
  final ChapterContent? sourceContent;
  ChapterContent? readyContent;
  int? readyLayout;
  final int direction;
  final List<ChapterKey> basis;
  bool passive;
  bool engaged = false;
  bool ready = false, saved = false, visible = false;
  double progress = 0;
  _ChapterIntent intent = _ChapterIntent.none;
  Timer? deadline;
  Future<void>? cancellation;
  int cancelPhase = 0;
}
