import 'dart:async';
import 'dart:math' as math;
import '../../domain/bookmark_position.dart';
import '../../shared/widgets/user_bookmark_scope.dart';
import 'reader_bookmarks.dart';
import 'reader_return_history.dart';
import '../../shared/widgets/shiori_sheet.dart';
import '../../app/window_caption.dart';
import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/local_navigation_title.dart';
import '../../shared/widgets/state_views.dart';
import '../novel_detail/catalog_controller.dart';
import 'reader_controller.dart';
import 'reader_preferences.dart';
import 'reader_loading_page.dart';
import 'reader_location_transition.dart';
import 'reader_theme.dart';
import 'position/position_resolver.dart';
import 'reader_screen.dart';
import 'viewport/page_turn.dart';
import '../cache/prefetch_sheet.dart';
import 'reader_cache_screen.dart';
import '../../shared/source_image.dart';
import '../../shared/widgets/shiori_feedback.dart';
import 'reader_notes.dart';
import 'viewport/paged_reader_viewport.dart';
import 'reader_chrome.dart';
import 'reader_contents.dart';
import 'reader_contents_session.dart';
import 'reader_panel.dart';
import '../../domain/local_chapter_progress.dart';
import 'reader_logical_progress.dart';
import 'reader_search_controller.dart';
import 'reader_linked_text.dart';

part 'book_reader_search.dart';
part 'book_reader_returns.dart';
part 'book_reader_bookmarks.dart';

/// Owns one chapter session at a time; repositories outlive the route.
class BookReaderScreen extends StatefulWidget {
  factory BookReaderScreen.offline({
    required ChapterKey chapter,
    required NovelRepository repository,
    ImageRepository? images,
    LibraryRepository? library,
    SettingsStore? settings,
    ReaderPreferences? preferences,
    CacheManagement? cache,
    VoidCallback? onReturnToShelf,
  }) => BookReaderScreen(
    chapter: chapter,
    repository: repository,
    images: images,
    library: library,
    settings: settings,
    preferences: preferences,
    cache: cache,
    onReturnToShelf: onReturnToShelf,
    offline: true,
  );

  const BookReaderScreen({
    super.key,
    required this.chapter,
    required this.repository,
    this.images,
    this.library,
    this.bookmarks,
    this.settings,
    this.preferences,
    this.chapterFallback = false,
    this.onDetails,
    this.cache,
    this.offline = false,
    this.initialBlockKey,
    this.initialPosition,
    this.initialBlockOffset,
    this.startAtBeginning = false,
    this.linkDepth = 0,
    this.onReturnToShelf,
    this.contentLinkObserver,
    this.onAuxiliaryReady,
    this.search,
    this.searchNavigation,
    this.searchHit,
    this.searchAccepts,
    this.onSearchRejected,
  });
  final ChapterKey chapter;
  final NovelRepository repository;
  final ImageRepository? images;
  final LibraryRepository? library;
  final UserBookmarkRepository? bookmarks;
  final SettingsStore? settings;
  final ReaderPreferences? preferences;
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

  /// Optional read-only diagnostic of accepted content-link activation.
  /// It does not select a target or change navigation behavior.
  final ValueChanged<LocalContentLink>? contentLinkObserver;

  /// A validated auxiliary route acknowledges its first displayed position.
  final ValueChanged<bool>? onAuxiliaryReady;
  final ReaderSearchController? search;
  final Future<ReaderSearchDestination> Function(
    LocalSearchHit,
    bool Function(),
    ReaderReturnPoint,
  )?
  searchNavigation;
  final ReaderPosition? initialPosition;
  final LocalSearchHit? searchHit;
  final bool Function()? searchAccepts;
  final VoidCallback? onSearchRejected;
  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  LocalBookUse? _routeUse;
  int _locationRevision = 0;
  ReaderSearchController? _search;
  late final _ReaderReturnSession _returns;
  late final Object _returnScope;
  _SearchNavigation? _searchNavigation;
  StreamSubscription<NovelKey>? _searchChanges;
  void _searchState(VoidCallback change) {
    if (mounted) setState(change);
  }

  final _disposed = Completer<void>();
  Future<void>? _routeOpening;
  Future<void> _openBook() async {
    try {
      if (widget.repository case LocalBookUsage usage) {
        _routeUse = await usage.acquireBookUse(
          widget.chapter.novelKey,
          cancellation: _titleRequest.token,
        );
      }
      if (!mounted || _titleRequest.token.isCancelled) return;
      _catalog.onStart();
      await Future.wait([_loadBookTitle(), _loadOrder(), _loadNavigation()]);
    } catch (_) {
      // The chapter controller supplies the ordinary load failure/retry UI.
    } finally {
      if (!mounted) {
        await _routeUse?.release();
        _routeUse = null;
      }
    }
  }

  late ReaderController _reader;
  final _viewports = <ReaderController, PagedReaderController>{};
  StreamSubscription<NovelKey>? _invalidation;
  StreamSubscription<NovelKey>? _removal;
  bool _onlineRemoved = false;
  bool _invalidated = false;
  final _contentsSession = ReaderContentsSession();

  void _syncContentsContext() {
    final content = _reader.content, index = _logicalIndex;
    final section =
        content != null &&
            index?.documents[_reader.chapter]?.matches(content) == true &&
            (_catalog.loaded == null ||
                _catalog.loaded!.value.revision == index!.metrics.revision)
        ? index!.sectionAt(_reader.chapter, _reader.currentPosition)
        : null;
    _contentsSession.readingContext(section?.entry ?? _reader.chapter);
  }

  final _quickReturn = ValueNotifier(false);
  Timer? _returnTimer;
  int _navigationGeneration = 0;
  UserBookmarkRepository? _bookmarkRepository;
  StreamSubscription<Result<BookmarkSnapshot>>? _bookmarkSubscription;
  BookmarkSnapshot? _bookmarkSnapshot;
  final _bookmarkCancellation = CancellationSource();
  ModalBottomSheetRoute<void>? _bookmarkSheet;
  bool _bookmarkWorking = false;
  void _receiveBookmarks(BookmarkSnapshot value) {
    if (mounted) setState(() => _bookmarkSnapshot = value);
  }

  void _dismissBookmarks() {
    final sheet = _bookmarkSheet, navigator = _bookmarkSheet?.navigator;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator?.mounted == true && sheet?.isActive == true) {
        navigator!.removeRoute(sheet!);
      }
    });
  }

  int _chapterFeedbackAttempt = 0;
  bool _routeWasCurrent = true, _auxiliaryReady = false;

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _canNavigate =>
      mounted &&
      !_invalidated &&
      !_changing &&
      !_openingLink &&
      _leavingInsets == null &&
      _completionTurn == null &&
      _foreground &&
      _route?.isCurrent != false &&
      !_reader.isClosed &&
      _reader.status == ReaderStatus.ready &&
      _reader.currentPosition != null &&
      _viewports[_reader]?.isRestoring != true &&
      _viewports[_reader]?.isTurning != true;

  _ReturnAnchor? _captureAnchor() {
    if (_reader.content == null || _viewports[_reader]?.isRestoring == true) {
      return null;
    }
    final position = _viewports[_reader]?.capture() ?? _reader.currentPosition;
    if (position == null) return null;
    final normalized = BookmarkPositionIndex([
      _reader.content!,
    ]).normalize(_reader.chapter, position);
    return normalized == null
        ? null
        : _ReturnAnchor(_reader.chapter, normalized, scope: _returnScope);
  }

  void _hideQuickReturn() {
    _returnTimer?.cancel();
    _returnTimer = null;
    _quickReturn.value = false;
  }

  void _showQuickReturn() {
    _hideQuickReturn();
    if (_returns.history.top == null) {
      return;
    }
    _quickReturn.value = true;
    _returnTimer = Timer(const Duration(seconds: 8), _hideQuickReturn);
  }

  void _chromeChanged() {
    if (_chrome.value) _hideQuickReturn();
  }

  void _commitLocation(
    _LocationIntent intent,
    _ReturnAnchor? origin, [
    ReaderReturnEntry? returning,
    int? ticket,
  ]) {
    _syncContentsContext();
    final destination = _captureAnchor();
    _commitReturnLocation(
      intent,
      origin,
      destination,
      returning,
      ticket ?? _returns.history.version,
    );
  }

  bool _validAnchor(_ReturnAnchor anchor, ChapterContent content) =>
      anchor.position.contentRevision == content.contentRevision &&
      anchor.position.blockIndex < content.blocks.length &&
      content.blocks[anchor.position.blockIndex].blockKey ==
          anchor.position.blockKey;

  void _discardReturn(ReaderReturnEntry entry) {
    if (_returns.history.consume(entry, _returns.history.version)) {
      _returns.changed();
    }
    if (_returns.history.top == null) _hideQuickReturn();
    _linkUnavailable();
  }

  void _linkUnavailable() {
    ShioriFeedback.show(
      context,
      message: AppLocalizations.of(context).readerLinkUnavailable,
      kind: ShioriFeedbackKind.error,
    );
  }

  Future<bool> _restorePosition(
    ReaderPosition position, {
    _LocationIntent intent = _LocationIntent.explicit,
    ReaderReturnEntry? returning,
    bool Function()? accepts,
    _ReturnAnchor? origin,
    int? returnTicket,
  }) async {
    if (!mounted ||
        intent == _LocationIntent.explicit &&
            (_returns.returning || _search?.navigating == true) ||
        _openingLink ||
        _changing ||
        _invalidated ||
        !_foreground ||
        _leavingInsets != null ||
        !(accepts?.call() ?? (_route?.isCurrent != false))) {
      return false;
    }
    final source = _reader, viewport = _viewports[_reader];
    origin ??= _captureAnchor();
    final ticket = returnTicket ?? _returns.history.version;
    if (origin == null ||
        viewport == null ||
        viewport.isRestoring ||
        viewport.isTurning ||
        source.pagePresentation != null) {
      return false;
    }
    final generation = ++_navigationGeneration;
    final content = source.content;
    bool live() =>
        mounted &&
        !_invalidated &&
        _foreground &&
        source == _reader &&
        !source.isClosed &&
        identical(source.content, content) &&
        generation == _navigationGeneration &&
        _leavingInsets == null &&
        (accepts?.call() ?? (_route?.isCurrent != false)) &&
        (returning == null ||
            identical(_returns.history.top, returning) &&
                ticket == _returns.history.version);
    _cancelChapter(immediate: true);
    source.beginPositionNavigation();
    final previousCompletion = _completion;
    setState(() {
      _changing = true;
      _restoringLocation = true;
      _completion = null;
    });
    final previousPage = viewport.inspectDisplayedPage()?.page;
    final restored = await viewport.restoreConfirmed(position, isCurrent: live);
    if (!mounted || source != _reader) return false;
    var confirmed = false, reveal = false;
    setState(() {
      _changing = false;
      _restoringLocation = false;
      if (!restored || !live()) _completion = previousCompletion;
      if (restored && live()) {
        confirmed = true;
        _commitLocation(intent, origin, returning, ticket);
        final page = viewport.inspectDisplayedPage()?.page;
        if (previousPage != null &&
            page != null &&
            (page.start != previousPage.start ||
                page.end != previousPage.end)) {
          reveal = true;
        }
      }
    });
    if (reveal) {
      unawaited(
        _revealRestoredLocation(
          source,
          generation,
          intent == _LocationIntent.bookmark ? _bookmarkSheet : null,
        ),
      );
    }
    return confirmed;
  }

  Future<void> _revealRestoredLocation(
    ReaderController source,
    int generation,
    ModalBottomSheetRoute<void>? sheet,
  ) async {
    // The confirmed bookmark closes its sheet before revealing the target.
    if (sheet != null) await sheet.completed;
    if (mounted &&
        !_invalidated &&
        !_changing &&
        _foreground &&
        _reader == source &&
        !source.isClosed &&
        generation == _navigationGeneration &&
        _leavingInsets == null &&
        _route?.isCurrent == true) {
      setState(() => _locationRevision++);
    }
  }

  ReaderController? _pending;
  _ChapterOperation? _operation;
  late final ReaderPreferences _preferences;
  Future<void> get _preferencesReady => _preferences.ready;
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
    ShioriFeedback.show(
      context,
      message: AppLocalizations.of(context).readerChapterLoadFailed,
      kind: ShioriFeedbackKind.error,
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
      (operation.search?.accepts() ?? true) &&
      (operation.returning == null ||
          identical(_returns.history.top, operation.returning) &&
              _returns.history.version == operation.returnTicket) &&
      _leavingInsets == null &&
      (operation.owner?.call() ?? (_route?.isCurrent != false)) &&
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
  // A same-chapter seek locks navigation without retiring the page's panels.
  bool _restoringLocation = false;
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
      _navigationGeneration++;
      _hideQuickReturn();
      final padding = MediaQuery.paddingOf(context);
      setState(() => _leavingInsets = padding);
    }
    _searchNavigation?.complete(ReaderSearchDestination.failed);
    if (identical(_returns.owner, this)) {
      _clearReturnHistory();
      unawaited(_search?.close());
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
    _syncContentsContext();
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
          String locale,
          LocalNavigationEntry? entry,
          String? chapter,
          String? running,
        })
      >();
  (String?, String?, LocalNavigationEntry?) _titlesFor(
    ReaderController reader,
  ) {
    final catalog = _catalog.loaded?.value;
    final content = reader.content;
    final locale = AppLocalizations.of(context).localeName;
    final cached = _titles[reader];
    if (cached != null &&
        identical(cached.catalog, catalog) &&
        identical(cached.navigation, _navigationRevision) &&
        identical(cached.order, _readingOrder) &&
        cached.book == _bookTitle &&
        cached.locale == locale &&
        identical(cached.content, content)) {
      return (cached.chapter, cached.running, cached.entry);
    }
    final entry = _scanChapterNavigation(reader);
    final chapter = _scanChapterTitle(reader, entry);
    final running = _scanRunningTitle(reader);
    _titles[reader] = (
      catalog: catalog,
      navigation: _navigationRevision,
      order: _readingOrder,
      book: _bookTitle,
      content: content,
      locale: locale,
      entry: entry,
      chapter: chapter,
      running: running,
    );
    return (chapter, running, entry);
  }

  String? _chapterTitle(ReaderController reader) => _titlesFor(reader).$1;
  String? _runningTitle(ReaderController reader) => _titlesFor(reader).$2;

  LocalNavigationEntry? _scanChapterNavigation(ReaderController reader) {
    LocalNavigationEntry? selected;
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
        selected = entry;
        earliest = index;
        deepest = depth;
      }
    }
    return selected;
  }

  String? _scanChapterTitle(
    ReaderController reader,
    LocalNavigationEntry? entry,
  ) {
    return (entry == null
            ? null
            : localNavigationTitle(entry, AppLocalizations.of(context))) ??
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
        if (entry.title.trim().isNotEmpty) {
          return localNavigationTitle(entry, AppLocalizations.of(context));
        }
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
    _chrome.addListener(_chromeChanged);
    _initReturns();
    _initSearch();
    _chapterTurn = AnimationController(
      vsync: this,
      duration: PaperTurnMotion.duration,
    );
    _preferences = widget.preferences ?? ReaderPreferences(widget.settings);
    unawaited(_preferencesReady);
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
          ..addListener(_changed)
          ..addListener(_catalogChanged);
    _reader = _create(
      widget.chapter,
      blockKey: widget.initialBlockKey,
      blockOffset: widget.initialBlockOffset,
      navigationPosition: widget.initialPosition,
      fromStart: widget.startAtBeginning,
    );
    _routeOpening = _openBook();
    if (widget.repository case LocalBookInvalidation changes) {
      _invalidation = changes.invalidations.listen(
        (key) => _invalidateBook(key),
      );
    }
    if (widget.library case LibraryBookRemoval lifecycle) {
      _removal = lifecycle.removedBooks.listen(
        (key) => _invalidateBook(key, removed: true),
      );
    }
    if (widget.chapterFallback) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ShioriFeedback.show(
            context,
            message: AppLocalizations.of(context).chapterFallback,
          );
        }
      });
    }
  }

  void _invalidateBook(NovelKey key, {bool removed = false}) {
    if (!mounted || key != widget.chapter.novelKey || _invalidated) return;
    _navigationGeneration++;
    _clearReturnHistory();
    unawaited(_search?.invalidate());
    _contentsSession.dispose();
    _dismissBookmarks();
    _hideQuickReturn();
    _completionTurn?.invalidate();
    _cancelChapter(immediate: true);
    _reader.onDelete();
    _pending?.onDelete();
    _contentsPanel?.dismiss();
    _contentsPanel = null;
    if (removed) {
      _catalog.onDelete();
    }
    setState(() {
      _invalidated = true;
      _onlineRemoved = removed;
    });
  }

  ReaderController _create(
    ChapterKey key, {
    String? blockKey,
    int? blockOffset,
    ReaderPosition? navigationPosition,
    UserBookmark? bookmark,
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
          bookmark: bookmark,
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
    if (_reader.status != ReaderStatus.ready && _operation != null) {
      unawaited(_cancelChapter(immediate: true));
    }
    if (_reader.content == null && _reader.status == ReaderStatus.error) {
      unawaited(_releaseRouteUse());
    }
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
    _bindBookmarks();
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
    _disposeReturns();
    _bookmarkSubscription?.cancel();
    _bookmarkCancellation.cancel();
    _dismissBookmarks();
    if (_operation?.confirmation?.isCompleted == false) {
      _operation!.confirmation!.complete((
        committed: false,
        reader: _operation!.target,
      ));
    }
    _disposed.complete();
    _searchNavigation?.complete(ReaderSearchDestination.failed);
    _searchChanges?.cancel();
    _search?.removeListener(_searchWorkChanged);
    _activePanel?.dismiss();
    _search?.canReturn.removeListener(_searchReturnChanged);
    if (widget.search == null) _search?.dispose();
    _contentsSession.dispose();
    _contentsPanel?.dismiss();
    _contentsPanel = null;
    _navigationGeneration++;
    _returnTimer?.cancel();
    _quickReturn.dispose();
    _chrome.removeListener(_chromeChanged);
    _restoreSystemUi();
    _invalidation?.cancel();
    _removal?.cancel();
    _operation?.deadline?.cancel();
    _chapterTurn.dispose();
    if (widget.preferences == null) {
      _preferences.dispose();
    } else {
      unawaited(_preferences.flush());
    }
    _titleRequest.cancel();
    if (!widget.offline) _cache?.prefetch?.leave();
    WidgetsBinding.instance.removeObserver(this);
    if (_pending case final pending?) _close(pending);
    _close(_reader);
    unawaited(_releaseRouteUse());
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

  Future<void> _releaseRouteUse() async {
    await _routeOpening;
    await _catalog.resourcesReleased;
    if (widget.search == null) await _search?.close();
    await _routeUse?.release();
    _routeUse = null;
  }

  // The active ReaderContentView flushes its own session on lifecycle changes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_search?.suspend());
      _searchNavigation?.complete(ReaderSearchDestination.failed);
      _navigationGeneration++;
      _hideQuickReturn();
      _cancelChapter(immediate: true);
    }
    if (!widget.offline) {
      _cache?.prefetch?.active(state == AppLifecycleState.resumed);
    }
  }

  Future<bool> _save(
    _ChapterOperation? operation, {
    bool Function()? accepts,
  }) async {
    final reader = _reader;
    if (operation != null &&
        reader.content != null &&
        (reader.status != ReaderStatus.ready ||
            reader.currentPosition == null)) {
      return false;
    }
    final saved = await reader.saveForExit();
    if (!mounted ||
        reader != _reader ||
        accepts?.call() == false ||
        operation != null && !_valid(operation)) {
      return false;
    }
    if (!saved) {
      // Retired writers can close read-only; the post-pop path reports the
      // failed acknowledgement without offering an ineffective retry.
      if (operation == null &&
          accepts == null &&
          reader.progress?.obsolete == true) {
        return false;
      }
      ShioriFeedback.show(
        context,
        kind: ShioriFeedbackKind.error,
        message: reader.progress?.obsolete == true
            ? '${AppLocalizations.of(context).readerReadingProgress} · '
                  '${AppLocalizations.of(context).readerProgressNotSaved}'
            : reader.progressStatus == ReaderProgressStatus.paused
            ? AppLocalizations.of(context).readerRestoreReadFailed
            : AppLocalizations.of(context).readerProgressUnsaved,
        actionLabel: reader.canRetryProgress
            ? AppLocalizations.of(context).retryAction
            : null,
        onAction: reader.canRetryProgress
            ? () {
                if (mounted &&
                    !_invalidated &&
                    _reader == reader &&
                    reader.canRetryProgress) {
                  unawaited(reader.retryProgress());
                }
              }
            : null,
      );
      return false;
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
    UserBookmark? bookmark,
    bool fromStart = false,
    bool fromEnd = false,
  }) {
    if (!passive) _chapterFeedbackAttempt++;
    final existing = _operation;
    if (existing != null &&
        _valid(existing) &&
        existing.intent == _ChapterIntent.none &&
        existing.target.chapter == chapter &&
        existing.target.initialBlockKey == blockKey &&
        existing.target.initialBlockOffset == blockOffset &&
        existing.target.navigationPosition == navigationPosition &&
        existing.target.bookmark == bookmark &&
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
      bookmark: bookmark,
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
      operation.pageTurn = true;
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
    UserBookmark? bookmark,
    bool fromStart = false,
    bool fromEnd = false,
    bool pageTurn = false,
    _LocationIntent intent = _LocationIntent.explicit,
    _ReturnAnchor? origin,
    ReaderReturnEntry? returning,
    _SearchNavigation? search,
    bool Function()? owner,
    Completer<_ChapterConfirmation>? confirmation,
  }) async {
    if (!mounted ||
        _openingLink ||
        intent == _LocationIntent.explicit &&
            (_returns.returning || _search?.navigating == true) ||
        search?.accepts() == false ||
        !_foreground ||
        _leavingInsets != null ||
        _viewports[_reader]?.isRestoring == true ||
        _viewports[_reader]?.isTurning == true ||
        returning != null && !identical(_returns.history.top, returning)) {
      return;
    }
    _completionTurn?.invalidate();
    if (_closingPanelForSwitch) return;
    if (_route?.isCurrent == false && owner?.call() != true) {
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
      bookmark: bookmark,
      fromStart: fromStart,
      fromEnd: fromEnd,
    );
    operation.returnTicket = _returns.history.version;
    operation.owner = owner;
    operation.confirmation = confirmation;
    operation.search = search;
    operation.locationIntent = intent;
    operation.origin = origin ?? _captureAnchor();
    operation.returning = returning;
    operation.pageTurn = pageTurn;
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
    if (operation == null) {
      if (reader == _reader &&
          widget.linkDepth > 0 &&
          !_auxiliaryReady &&
          mounted &&
          !_invalidated &&
          _route?.isCurrent != false) {
        final hit = widget.searchHit;
        final requested = reader.navigationPosition;
        if (widget.searchAccepts?.call() == false ||
            hit != null &&
                (!_validSearchHit(hit, reader.content!) ||
                    reader.usedFallback) ||
            requested != null &&
                reader.pagePresentation == null &&
                (requested.contentRevision != reader.content?.contentRevision ||
                    reader.usedFallback ||
                    reader.currentPosition != requested)) {
          widget.onSearchRejected?.call();
          return;
        }
        _auxiliaryReady = true;
        widget.onAuxiliaryReady?.call(reader.pagePresentation != null);
        if (widget.searchHit case final LocalSearchFootnoteHit note) {
          unawaited(_openSearchNote(note));
        }
        if (widget.searchHit != null && reader.pagePresentation != null) {
          _searchDocumentNotice();
        }
        _showQuickReturn();
      }
      return;
    }
    if (!_valid(operation) || operation.target != reader) return;
    if (operation.search case final search?
        when search.hit == null &&
            !_validAnchor(search.origin, reader.content!)) {
      _rejectPending(reader);
      return;
    }
    if (operation.search?.hit case final hit?
        when !_validSearchHit(hit, reader.content!) || reader.usedFallback) {
      _rejectPending(reader);
      return;
    }
    if (operation.returning case final anchor?
        when !_validAnchor(anchor.origin, reader.content!)) {
      _rejectPending(reader, invalidLocation: true);
      return;
    }
    if (reader.bookmark != null && reader.bookmarkResolution?.located != true) {
      _rejectPending(reader, invalidLocation: true);
      return;
    }
    if (reader.usedFallback && reader.initialBlockKey != null ||
        reader.navigationPosition != null &&
            (reader.navigationPosition!.contentRevision !=
                    reader.content?.contentRevision ||
                reader.usedFallback ||
                reader.currentPosition != reader.navigationPosition)) {
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
            !TickerMode.of(context) ||
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
    if (operation.pageTurn) _chrome.value = false;
    _close(previous);
    if (_allowRemote && reader.content != null) {
      unawaited(
        _cache?.prefetch?.enter(reader.content!, _catalog.loaded?.value),
      );
    }
    reader.activateProgress();
    if (operation.confirmation?.isCompleted == false) {
      operation.confirmation!.complete((committed: true, reader: reader));
    }
    setState(
      () => _commitLocation(
        operation.locationIntent,
        operation.origin,
        operation.returning,
        operation.returnTicket,
      ),
    );
  }

  Future<void> _cancelChapter({bool immediate = false}) {
    final operation = _operation;
    if (!mounted || operation == null) return Future.value();
    // Repeated input shares the current rebound. Lifecycle cancellation may
    // supersede it; an interrupted animation must never clean up its successor.
    if (!immediate && operation.cancellation != null) {
      return operation.cancellation!;
    }
    if (operation.confirmation?.isCompleted == false) {
      operation.confirmation!.complete((
        committed: false,
        reader: operation.target,
      ));
    }
    operation.search?.complete(ReaderSearchDestination.failed);
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
              !TickerMode.of(context) ||
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

  void _rejectPending(
    ReaderController reader, {
    bool timedOut = false,
    bool invalidLocation = false,
  }) {
    final operation = _operation;
    if (operation == null || !_valid(operation) || operation.target != reader) {
      if (reader == _reader && !_auxiliaryReady) {
        widget.onSearchRejected?.call();
      }
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
    if ((invalidLocation || reader.failure?.kind == FailureKind.notFound) &&
        operation.returning != null) {
      final anchor = operation.returning!;
      unawaited(_cancelChapter());
      _discardReturn(anchor);
      return;
    }
    if (reader.bookmark != null) {
      unawaited(_cancelChapter(immediate: true));
      return;
    }
    final target = reader.chapter;
    final blockKey = reader.initialBlockKey,
        blockOffset = reader.initialBlockOffset;
    final fromStart = reader.startAtBeginning, fromEnd = reader.startAtEnd;
    final pageTurn = operation.pageTurn;
    final intent = operation.locationIntent, returning = operation.returning;
    final navigationPosition = reader.navigationPosition;
    final failure = reader.failure;
    final attempt = _chapterFeedbackAttempt, generation = _navigationGeneration;
    final source = _reader;
    unawaited(_cancelChapter());
    final l = AppLocalizations.of(context);
    ShioriFeedback.show(
      context,
      kind: ShioriFeedbackKind.error,
      message: l.readerChapterLoadFailed,
      actionLabel: failure?.retryPolicy == RetryPolicy.never
          ? null
          : l.retryAction,
      onAction: failure?.retryPolicy == RetryPolicy.never
          ? null
          : () {
              if (!mounted ||
                  !_canNavigate ||
                  _reader != source ||
                  attempt != _chapterFeedbackAttempt ||
                  generation != _navigationGeneration) {
                return;
              }
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
                pageTurn: pageTurn,
                intent: intent,
                returning: returning,
                navigationPosition: navigationPosition,
              );
            },
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
        (_reader.progress?.obsolete == true ||
            !(_reader.hasUnsavedProgress &&
                _reader.progressStatus != ReaderProgressStatus.normal));
  }

  /// After a direct pop, persist the last samples and surface a failed save
  /// on the screen underneath instead of losing it silently.
  Future<void> _flushAfterPop() async {
    final feedback = Navigator.of(context, rootNavigator: true).context;
    final l = AppLocalizations.of(context);
    final reader = _reader;
    if (!await reader.saveForExit() && feedback.mounted) {
      ShioriFeedback.show(
        feedback,
        kind: ShioriFeedbackKind.error,
        message: reader.progressStatus == ReaderProgressStatus.paused
            ? l.readerRestoreReadFailed
            : l.readerProgressUnsaved,
      );
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
    final saved = await _save(null);
    if (!mounted) return;
    final canLeave = saved || _reader.progress?.obsolete == true;
    setState(() {
      _changing = false;
      _canPop = canLeave;
    });
    if (canLeave) {
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
    if (_changing || _invalidated) return;
    final bool? manage;
    if (!panels.desktop) {
      manage = await showPrefetchSheet(
        context,
        cache: cache!,
        catalog: _catalog.loaded?.value,
        current: source.chapter,
      );
    } else {
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
      manage = await panel.closed;
    }
    if (manage != true ||
        !mounted ||
        !panels.live ||
        _invalidated ||
        _changing ||
        source != _reader) {
      return;
    }
    // The cache route owns later selections; only its first successful open
    // needs this reader's save/removal barrier.
    final reader = widget;
    var retired = false;
    Future<bool> Function(bool Function())? retire = _retireForCache;
    _beginLeaving();
    final cacheClosed = Navigator.of(context, rootNavigator: true).push<void>(
      platformPageRoute<void>(
        context,
        settings: const RouteSettings(name: '/cache'),
        builder: (_) => ReaderCacheScreen(
          reader: reader,
          beforeOpen: (accepts) async {
            final original = retire;
            if (original == null) return retired;
            if (!await original(accepts)) return false;
            retired = true;
            retire = null;
            return true;
          },
        ),
      ),
    );
    // The cache route can outlive this State after opening an offline reader.
    await Future.any<void>([cacheClosed, _disposed.future]);
    retire = null;
    if (!mounted || _invalidated || _route?.isCurrent != true) return;
    setState(() => _leavingInsets = null);
    _enterSystemUi();
  }

  Future<bool> _retireForCache(bool Function() accepts) async {
    bool valid() =>
        accepts() &&
        mounted &&
        !_invalidated &&
        !_changing &&
        _route?.isActive == true &&
        !_reader.isClosed;
    if (!valid()) return false;
    final source = _reader;
    final route = _route!;
    final navigator = route.navigator!;
    setState(() => _changing = true);
    final saved = await _save(
      null,
      accepts: () => accepts() && !_invalidated && !source.isClosed,
    );
    if (!mounted) return false;
    setState(() => _changing = false);
    if (!saved || !valid() || source != _reader) return false;
    navigator.removeRoute(route);
    return true;
  }

  Future<void> _followContentLink(LocalContentLink link) async {
    if (!_canNavigate ||
        _returns.returning ||
        _search?.navigating == true ||
        link.source != _reader.chapter ||
        link.isFootnote) {
      return;
    }
    widget.contentLinkObserver?.call(link);
    if (link.target == null) {
      _linkUnavailable();
      return;
    }
    await _followContentTarget(
      link.target!,
      link.targetBlockKey,
      blockOffset: link.targetOffset,
      intent: _LocationIntent.link,
    );
  }

  Future<void> _followContentTarget(
    ChapterKey target,
    String? blockKey, {
    int? blockOffset,
    _LocationIntent intent = _LocationIntent.explicit,
  }) async {
    if (!_canNavigate || target.novelKey != widget.chapter.novelKey) return;
    final origin = _captureAnchor();
    if (origin == null) return;
    if (target == _reader.chapter) {
      final content = _reader.content!;
      final index = blockKey == null
          ? 0
          : content.blocks.indexWhere((b) => b.blockKey == blockKey);
      if (index < 0) {
        _linkUnavailable();
        return;
      }
      final fraction = readerTargetFraction(content.blocks[index], blockOffset);
      await _restorePosition(
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
        intent: intent,
      );
      return;
    }
    final source = _reader, generation = _navigationGeneration;
    _openingLink = true;
    try {
      if (_needsOrder && _readingOrder == null) await _loadOrder();
    } finally {
      _openingLink = false;
    }
    if (!mounted ||
        !_canNavigate ||
        source != _reader ||
        generation != _navigationGeneration) {
      return;
    }
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
        intent: intent,
        origin: origin,
      );
    } else {
      await _openAuxiliary(
        target,
        blockKey,
        blockOffset,
        intent: intent,
        origin: origin,
      );
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
      await _restorePosition(target.position);
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
    int? blockOffset, {
    required _LocationIntent intent,
    _SearchNavigation? search,
    _ReturnAnchor? origin,
    ReaderReturnEntry? returning,
    Object? scope,
    int? returnTicket,
    bool Function()? owner,
  }) async {
    if (widget.linkDepth >= 8) {
      search?.complete(ReaderSearchDestination.failed);
      ShioriFeedback.show(
        context,
        message: AppLocalizations.of(context).readerLinkDepth,
        kind: ShioriFeedbackKind.error,
      );
      return;
    }
    if (_openingLink ||
        _invalidated ||
        target.novelKey != widget.chapter.novelKey) {
      search?.complete(ReaderSearchDestination.failed);
      return;
    }
    origin ??= search?.origin ?? _captureAnchor();
    final ticket = returnTicket ?? _returns.history.version;
    final source = _reader, generation = _navigationGeneration;
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
    if (!mounted ||
        !(_canNavigate || owner?.call() == true) ||
        search?.accepts() == false ||
        source != _reader ||
        generation != _navigationGeneration) {
      search?.complete(ReaderSearchDestination.failed);
      return;
    }
    final restore =
        returning?.origin ?? (search?.hit == null ? search?.origin : null);
    if (value is! Success<LoadResult<ChapterContent>> ||
        block != null &&
            !value.value.value.blocks.any((b) => b.blockKey == block) ||
        restore != null && !_validAnchor(restore, value.value.value)) {
      if (returning != null &&
          (value is Success<LoadResult<ChapterContent>> ||
              value is Failure<LoadResult<ChapterContent>> &&
                  value.failure.kind == FailureKind.notFound)) {
        _discardReturn(returning);
      } else {
        _linkUnavailable();
      }
      search?.complete(ReaderSearchDestination.failed);
      return;
    }
    _cancelChapter(immediate: true);
    _hideQuickReturn();
    final surface = scope ?? Object();
    ReaderReturnEntry? boundary;
    var confirmed = false;
    late final Route<void> auxiliaryRoute;
    auxiliaryRoute = platformPageRoute<void>(
      context,
      settings: const RouteSettings(name: '/local-link'),
      builder: (_) => _ReaderReturnScope(
        session: _returns,
        scope: surface,
        child: BookReaderScreen(
          chapter: target,
          search: _search,
          searchNavigation: widget.searchNavigation ?? _navigateSearchFrom,
          searchHit: search?.hit,
          searchAccepts: search?.accepts,
          onSearchRejected: search == null
              ? null
              : () => search.complete(ReaderSearchDestination.failed),
          repository: widget.repository,
          images: widget.images,
          settings: widget.settings,
          preferences: _preferences,
          initialBlockKey: block,
          initialBlockOffset: blockOffset,
          initialPosition: restore?.position,
          startAtBeginning: true,
          linkDepth: widget.linkDepth + 1,
          onReturnToShelf: widget.onReturnToShelf,
          onAuxiliaryReady: (document) {
            if (!mounted ||
                _invalidated ||
                source != _reader ||
                !auxiliaryRoute.isCurrent ||
                search?.accepts() == false) {
              search?.complete(ReaderSearchDestination.failed);
              return;
            }
            final destinationSurface = _returns.surfaces[surface];
            final destination = destinationSurface?._captureAnchor();
            if (restore != null &&
                destinationSurface?._reader.pagePresentation == null &&
                (destination == null ||
                    !restore.sameLocation(destination) ||
                    destinationSurface!._reader.usedFallback)) {
              search?.complete(ReaderSearchDestination.failed);
              return;
            }
            final previousTop = _returns.history.top;
            _commitReturnLocation(
              intent,
              origin,
              destination,
              returning,
              ticket,
            );
            confirmed = true;
            if (intent != _LocationIntent.returnLocation &&
                !identical(previousTop, _returns.history.top)) {
              boundary = _returns.history.top;
            }
            search?.complete(
              document
                  ? ReaderSearchDestination.document
                  : ReaderSearchDestination.native,
            );
          },
        ),
      ),
    );
    final navigator = Navigator.of(context);
    if (search != null) {
      search.cancelSurface = () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (navigator.mounted && auxiliaryRoute.isActive) {
            navigator.removeRoute(auxiliaryRoute);
          }
        });
      };
    }
    await navigator.push(auxiliaryRoute);
    search?.complete(ReaderSearchDestination.failed);
    final retired = _returns.retired.remove(surface);
    if (confirmed && !retired && mounted && !_invalidated) {
      _returns.history.closeScope(surface, _captureAnchor(), boundary);
      _returns.changed();
    }
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
        browsing: _contentsSession.local,
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
      browsing: _contentsSession.online,
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

  /// The contents panel opened from the failure page on desktop.
  ReaderPanelHandle<VoidCallback>? _contentsPanel;

  Future<void> _contents() async {
    if (!ShioriCapabilities.of(context).pointerFirst) {
      return showReaderContents(
        context,
        layers: [_bookContents(context)],
        session: _contentsSession,
      );
    }
    if (_contentsPanel != null || _invalidated) return;
    final layer = _bookContents(context);
    final panel = ReaderPanelHandle<VoidCallback>.open(
      this,
      placement: ReaderPanelPlacement.start,
      themeChanges: _preferences,
      theme: (context) => readerTheme(
        _preferences.value,
        MediaQuery.platformBrightnessOf(context),
        accent: appAccentOf(context),
      ),
      semanticLabel: layer.label,
      builder: (context, panel) => ReaderContentsPanel(
        layers: [layer],
        session: _contentsSession,
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
    if (!await _save(null)) {
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
      toggleBookmark: _bookmarkRepository == null
          ? null
          : () => unawaited(_toggleBookmark()),
      // Auxiliary readers have no progress owner; return to the main reader first.
      showBookmarks: _bookmarkRepository == null || widget.linkDepth > 0
          ? null
          : _showBookmarks,
      isBookmarked: () => _currentBookmark != null,
      bookmarkSupported:
          reader.pagePresentation == null && widget.linkDepth == 0,
      completionPrevious: () => setState(() => _completion = null),
      exitToShelf: () => _exit(toShelf: true),
      restart: order.isEmpty
          ? null
          : () => _switch(order.first, fromStart: true),
      bookEnd: terminal == null ? null : bookEnd,
      contentLink: _changing
          ? null
          : (link) {
              if (active && reader == _reader) {
                unawaited(_followContentLink(link));
              }
            },
      previousLocationLabel: _returnLabel(context),
      previousLocation: _returns.history.top == null
          ? null
          : () {
              if (active && reader == _reader) unawaited(_returnLocation());
            },
      navigatePosition: (position, accepts) =>
          _restorePosition(position, accepts: accepts),
      pageTurnCommitted: () {
        _search?.clearHighlight();
        _navigationGeneration++;
        _returns.history.invalidateTickets();
        _hideQuickReturn();
      },
      bookContents: _changing || widget.linkDepth > 0 ? null : _bookContents,
      links: _changing || reader.contentLinks.isEmpty ? null : _links,
      leave: () => unawaited(_exit()),
      prefetch: !widget.offline && _cache?.prefetch != null
          ? (panels) => unawaited(_prefetch(panels, reader))
          : null,
      details: widget.onDetails == null || _changing ? null : _details,
      previousChapter: !_changing && previous != null
          ? () => _switch(
              previous,
              fromEnd: true,
              pageTurn: true,
              intent: _LocationIntent.sequential,
            )
          : null,
      nextChapter: !_changing && next != null
          ? () => _switch(
              next,
              fromStart: true,
              pageTurn: true,
              intent: _LocationIntent.sequential,
            )
          : null,
      navigateChapter: (direction) {
        final target = direction < 0 ? previous : next;
        if (!_changing && target != null) {
          _switch(target, fromStart: direction > 0, fromEnd: direction < 0);
        }
      },
    );

    return ReaderContentView(
      key: ValueKey(reader),
      content: reader.content!,
      search: _search,
      searchEnabled:
          active &&
          !_invalidated &&
          !_changing &&
          !_openingLink &&
          _leavingInsets == null,
      searchTitle: _searchTitle,
      onSearchOpen: () {
        _search?.navigate = _navigateSearchHit;
      },
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
      navigationEntry: _titlesFor(reader).$3,
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
      contentsSession: _contentsSession,
      onPosition: (_) {
        if (active && reader == _reader && mounted && !_invalidated) {
          _syncContentsContext();
        }
      },
      returnToOrigin: widget.linkDepth > 0,
      quickReturn: _quickReturn,
      chrome: _chrome,
      active: active && (!_changing || _restoringLocation),
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
              _changing &&
                  !_restoringLocation &&
                  _operation?.intent != _ChapterIntent.dragging,
          child: AnimatedBuilder(
            animation: _chapterTurn,
            child: ExcludeSemantics(
              excluding: !active,
              child: ExcludeFocus(
                excluding: !active,
                child: ReaderLocationTransition(
                  revision: _locationRevision,
                  enabled:
                      active &&
                      !_changing &&
                      _foreground &&
                      !_invalidated &&
                      _leavingInsets == null &&
                      _preferences.value.pageTurn != PageTurnStyle.none &&
                      !MediaQuery.disableAnimationsOf(context),
                  paper: _paper,
                  child: _view(reader, active: active),
                ),
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _preferences,
    builder: (context, child) => Theme(
      data: readerTheme(
        _preferences.value,
        MediaQuery.platformBrightnessOf(context),
        accent: appAccentOf(context),
      ),
      child: child!,
    ),
    child: WindowCaptionScope.appDefault(child: Builder(builder: _buildPage)),
  );

  Widget _buildPage(BuildContext context) {
    _route = ModalRoute.of(context);
    final current = _route?.isCurrent != false;
    if (_routeWasCurrent && !current) {
      _navigationGeneration++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _hideQuickReturn();
      });
    }
    _routeWasCurrent = current;
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
    if (_operation != null &&
        (_operation!.owner != null && _operation!.owner!() == false ||
            _route?.isCurrent == false && _operation!.owner?.call() != true)) {
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
            child: Text(
              _onlineRemoved
                  ? AppLocalizations.of(context).onlineBookRemoved
                  : AppLocalizations.of(context).localReparseReaderClosed,
            ),
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
            : _reader.status == ReaderStatus.loading
            ? const ReaderLoadingPage()
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
                  child: _reader.failure != null
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

enum _LocationIntent {
  link,
  sequential,
  explicit,
  returnLocation,
  search,
  bookmark,
}

typedef _ReturnAnchor = ReaderReturnPoint;

enum _ChapterIntent { none, dragging, confirmed, cancelling, settling }

/// Identity is the operation token; every async continuation checks it.
typedef _ChapterConfirmation = ({bool committed, ReaderController reader});

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
  bool pageTurn = false;
  _SearchNavigation? search;
  bool Function()? owner;
  Completer<_ChapterConfirmation>? confirmation;
  _LocationIntent locationIntent = _LocationIntent.sequential;
  _ReturnAnchor? origin;
  ReaderReturnEntry? returning;
  int returnTicket = 0;
  bool ready = false, saved = false, visible = false;
  double progress = 0;
  _ChapterIntent intent = _ChapterIntent.none;
  Timer? deadline;
  Future<void>? cancellation;
  int cancelPhase = 0;
}
