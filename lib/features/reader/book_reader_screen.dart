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
  final _titleRequest = CancellationSource();
  String? _bookTitle;
  NovelStatus _bookStatus = NovelStatus.unknown;
  List<ChapterKey>? _readingOrder;
  final _navigation = <ChapterKey, List<(LocalNavigationEntry, int)>>{};
  Object _navigationRevision = Object();
  final _navigationTree = ValueNotifier<Result<List<LocalNavigationEntry>>?>(
    null,
  );
  Future<void> _loadNavigation() async {
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
    if (!_needsOrder) return;
    final result = await (widget.repository as LocalContentLinkRepository)
        .loadReadingOrder(
          widget.chapter.novelKey,
          cancellation: _titleRequest.token,
        );
    if (!mounted || _invalidated || _titleRequest.token.isCancelled) return;
    if (result case Success<List<ChapterKey>>(:final value)) {
      setState(() => _readingOrder = value);
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
    _displayImages = widget.offline && widget.images != null
        ? _OfflineImages(widget.images!)
        : widget.images;
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
        _chapterTurn.stop();
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
    bool fromStart = false,
    bool fromEnd = false,
    bool deferProgress = false,
  }) =>
      ReaderController(
          repository: widget.repository,
          chapter: key,
          initialBlockKey: blockKey,
          initialBlockOffset: blockOffset,
          startAtBeginning: fromStart,
          startAtEnd: fromEnd,
          deferProgress: deferProgress,
          library: widget.linkDepth > 0 ? null : widget.library,
          cache: _cache,
          readMode: widget.offline ? ReadMode.cacheOnly : ReadMode.cacheFirst,
          onPosition: widget.offline ? null : _cache?.prefetch?.position,
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
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _rejectPending(pending),
      );
    }
    if (!widget.offline && _reader.content != null) {
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
    _chapterTurn.dispose();
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
    _chrome.dispose();
    super.dispose();
  }

  // The active ReaderContentView flushes its own session on lifecycle changes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.offline) {
      _cache?.prefetch?.active(state == AppLifecycleState.resumed);
    }
  }

  Future<bool> _save() async {
    await _reader.flushProgress();
    if (!mounted) return false;
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
      return _reader.progress == null;
    }
    return true;
  }

  Future<void> _switch(
    ChapterKey chapter, {
    String? blockKey,
    int? blockOffset,
    bool fromStart = false,
    bool fromEnd = false,
  }) async {
    if (_changing ||
        chapter == _reader.chapter &&
            blockKey == null &&
            !fromStart &&
            _completion == null ||
        chapter.novelKey != widget.chapter.novelKey) {
      return;
    }
    _animateChapter = fromStart || fromEnd;
    _turnDirection = fromEnd ? -1 : 1;
    setState(() => _changing = true);
    if (!await _save()) {
      if (mounted) setState(() => _changing = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _pending = _create(
        chapter,
        deferProgress: true,
        blockKey: blockKey,
        blockOffset: blockOffset,
        fromStart: fromStart,
        fromEnd: fromEnd,
      );
    });
  }

  Future<void> _commitPending(ReaderController reader) async {
    if (!mounted || _pending != reader || _committing) return;
    _committing = true;
    if (_animateChapter &&
        _turnStyle != PageTurnStyle.none &&
        !MediaQuery.disableAnimationsOf(context)) {
      try {
        await PaperTurnMotion.settle(_chapterTurn, curve: _chapterFrame.curve);
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || _pending != reader) return;
    final previous = _reader;
    setState(() {
      _reader = reader;
      _completion = null;
      _pending = null;
      _committing = false;
      _chapterTurn.value = 0;
      _changing = false;
    });
    _close(previous);
    reader.activateProgress();
  }

  void _rejectPending(ReaderController reader) {
    if (!mounted || _pending != reader) return;
    _chapterTurn.stop(canceled: true);
    _chapterTurn.value = 0;
    _committing = false;
    final target = reader.chapter;
    final blockKey = reader.initialBlockKey;
    final blockOffset = reader.initialBlockOffset;
    final fromStart = reader.startAtBeginning, fromEnd = reader.startAtEnd;
    setState(() {
      _pending = null;
      _changing = false;
    });
    _close(reader);
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.readerChapterLoadFailed),
        action: SnackBarAction(
          label: l.retryAction,
          onPressed: () => _switch(
            target,
            blockKey: blockKey,
            blockOffset: blockOffset,
            fromStart: fromStart,
            fromEnd: fromEnd,
          ),
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
    if (chromeVisible) return false;
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
        current: _reader.chapter,
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
    final (order, positions) = _readingSequence();
    final index = positions[reader.chapter] ?? -1;
    final previous = index > 0 && widget.linkDepth == 0
        ? order[index - 1]
        : null;
    final next = index >= 0 && index + 1 < order.length && widget.linkDepth == 0
        ? order[index + 1]
        : null;

    void bookEnd() {
      if (_completion != null || reader != _reader) return;
      final state = bookEndState(
        local: _local,
        status: reader.novelStatus == NovelStatus.unknown
            ? _bookStatus
            : reader.novelStatus,
      );
      setState(() => _completion = state);
      reader.enterBookEnd(state);
      unawaited(reader.flushProgress());
    }

    final actions = ReaderActions(
      completionPrevious: () => setState(() => _completion = null),
      exitToShelf: () => _exit(toShelf: true),
      restart: order.isEmpty
          ? null
          : () => _switch(order.first, fromStart: true),
      bookEnd:
          !_changing &&
              widget.linkDepth == 0 &&
              index >= 0 &&
              index == order.length - 1
          ? bookEnd
          : null,
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
      completion: reader == _reader ? _completion : null,
      actions: actions,
      onReady: () => _commitPending(reader),
      onPageAppearance: (paper, turn) {
        if (reader == _reader) {
          _paper = paper;
          _turnStyle = turn;
        }
      },
      onLoadFailure: () => _rejectPending(reader),
      runningTitle: _runningTitle(reader),
      chapterTitle: _chapterTitle(reader),
      images: _displayImages,
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
  );

  Widget _pageLayer(ReaderController reader, {required bool active}) =>
      Positioned.fill(
        key: ValueKey(reader),
        child: IgnorePointer(
          ignoring: !active || _changing,
          child: AnimatedBuilder(
            animation: _chapterTurn,
            child: ExcludeSemantics(
              excluding: !active,
              child: _view(reader, active: active),
            ),
            builder: (context, child) => PageTurnSlot(
              frame: _chapterFrame,
              role: active ? PageTurnRole.leaving : PageTurnRole.entering,
              child: child!,
            ),
          ),
        ),
      );

  /// The chapter being turned away from and the one being turned to, in
  /// paint order for the current style.
  List<Widget> _chapterLayers() {
    final pending = _pending;
    final ready = pending != null && pending.status == ReaderStatus.ready;
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

  @override
  Widget build(BuildContext context) =>
      WindowCaptionScope.appDefault(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
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
              _beginLeaving();
              unawaited(_flushAfterPop());
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

class _OfflineImages implements ImageRepository {
  _OfflineImages(this.inner);
  final ImageRepository inner;
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => inner.load(ref, mode: ReadMode.cacheOnly, cancellation: cancellation);
}
