import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';
import '../novel_detail/catalog_controller.dart';
import '../novel_detail/catalog_view.dart';
import 'reader_controller.dart';
import 'reader_screen.dart';
import 'viewport/paper_turn.dart';
import '../cache/prefetch_sheet.dart';
import '../../shared/source_image.dart';
import 'reader_footnote_text.dart';
import '../local_books/local_catalog.dart';

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
    this.startAtBeginning = false,
    this.linkDepth = 0,
  });
  final ChapterKey chapter;
  final NovelRepository repository;
  final ImageRepository? images;
  final LibraryRepository? library;
  final SettingsStore? settings;
  final bool chapterFallback;
  final ValueChanged<NovelKey>? onDetails;
  final CacheManagement? cache;
  final bool offline;
  final String? initialBlockKey;
  final bool startAtBeginning;
  final int linkDepth;
  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late ReaderController _reader;
  StreamSubscription<NovelKey>? _invalidation;
  bool _invalidated = false;
  ReaderController? _pending;
  late final AnimationController _chapterTurn;
  int _turnDirection = 1;
  bool _animateChapter = false;
  bool _committing = false;
  Color _paper = const Color(0xfffaf7f2);
  late final ImageRepository? _displayImages;
  late final CatalogController _catalog;
  bool get _local =>
      widget.chapter.novelKey.sourceId == LocalBookIdentity.sourceId;
  CacheManagement? get _cache => _local ? null : widget.cache;
  bool _changing = false, _canPop = false;
  final _titleRequest = CancellationSource();
  String? _bookTitle;
  List<ChapterKey>? _readingOrder;
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
      setState(() => _bookTitle = value.value.summary.title);
    }
  }

  String? _runningTitle(ReaderController reader) {
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
          ..addListener(_changed);
    unawaited(_loadBookTitle());
    unawaited(_loadOrder());
    _reader = _create(
      widget.chapter,
      blockKey: widget.initialBlockKey,
      fromStart: widget.startAtBeginning,
    );
    if (widget.repository case LocalBookInvalidation changes) {
      _invalidation = changes.invalidations.listen((key) {
        if (!mounted || key != widget.chapter.novelKey || _invalidated) return;
        _chapterTurn.stop();
        _reader.onDelete();
        _pending?.onDelete();
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
    bool fromStart = false,
    bool fromEnd = false,
    bool deferProgress = false,
  }) =>
      ReaderController(
          repository: widget.repository,
          chapter: key,
          initialBlockKey: blockKey,
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
    reader.removeListener(_changed);
    reader.onDelete();
    reader.dispose();
  }

  @override
  void dispose() {
    _invalidation?.cancel();
    _chapterTurn.dispose();
    _titleRequest.cancel();
    if (!widget.offline) _cache?.prefetch?.leave();
    WidgetsBinding.instance.removeObserver(this);
    if (_pending case final pending?) _close(pending);
    _close(_reader);
    _catalog.removeListener(_changed);
    _catalog.onDelete();
    _catalog.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.offline) {
      _cache?.prefetch?.active(state == AppLifecycleState.resumed);
    }
    if (state != AppLifecycleState.resumed) unawaited(_reader.flushProgress());
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
    bool fromStart = false,
    bool fromEnd = false,
  }) async {
    if (_changing ||
        chapter == _reader.chapter && blockKey == null && !fromStart ||
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
        fromStart: fromStart,
        fromEnd: fromEnd,
      );
    });
  }

  Future<void> _commitPending(ReaderController reader) async {
    if (!mounted || _pending != reader || _committing) return;
    _committing = true;
    if (_animateChapter && !MediaQuery.disableAnimationsOf(context)) {
      try {
        await PaperTurnMotion.settle(_chapterTurn);
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || _pending != reader) return;
    final previous = _reader;
    setState(() {
      _reader = reader;
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
            fromStart: fromStart,
            fromEnd: fromEnd,
          ),
        ),
      ),
    );
  }

  Future<void> _exit() async {
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
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _links() async {
    if (_changing || _invalidated) return;
    final l = AppLocalizations.of(context);
    final source = _reader;
    final link = await showModalBottomSheet<LocalContentLink>(
      context: context,
      useSafeArea: true,
      builder: (context) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(l.readerLinks),
          ),
          for (final link in source.contentLinks)
            ListTile(
              title: Text(link.label),
              subtitle: link.unavailable == null
                  ? null
                  : Text(l.readerLinkUnavailable),
              trailing: Icon(
                link.unavailable == null ? Icons.chevron_right : Icons.link_off,
              ),
              onTap: () => Navigator.pop(context, link),
            ),
        ],
      ),
    );
    if (!mounted || _invalidated || source != _reader || link == null) return;
    if (link.isFootnote) {
      await showReaderFootnote(context, link);
      return;
    }
    if (link.target == null || widget.linkDepth >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.linkDepth >= 8 ? l.readerLinkDepth : l.readerLinkUnavailable,
          ),
        ),
      );
      return;
    }
    await _openAuxiliary(link.target!, link.targetBlockKey);
  }

  Future<void> _openAuxiliary(ChapterKey target, String? block) async {
    if (_invalidated ||
        target.novelKey != widget.chapter.novelKey ||
        widget.linkDepth >= 8) {
      return;
    }
    // Validate before replacing any surface; failed targets leave origin intact.
    final value = await widget.repository.loadChapter(
      target,
      mode: ReadMode.cacheOnly,
      cancellation: _titleRequest.token,
    );
    if (!mounted || _invalidated) return;
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
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/local-link'),
        builder: (_) => BookReaderScreen(
          chapter: target,
          repository: widget.repository,
          images: widget.images,
          settings: widget.settings,
          initialBlockKey: block,
          startAtBeginning: true,
          linkDepth: widget.linkDepth + 1,
        ),
      ),
    );
  }

  Future<void> _contents() async {
    final repository = widget.repository;
    if (_local && repository is LocalNavigationRepository) {
      final target = await openLocalCatalog(
        context,
        novel: widget.chapter.novelKey,
        repository: repository as LocalNavigationRepository,
        current: _reader.chapter,
      );
      if (mounted && target != null) {
        final main =
            _catalog.loaded?.value.flatChapters.any(
              (c) => c.key == target.chapterKey,
            ) ??
            false;
        if (!main) {
          await _openAuxiliary(target.chapterKey, target.blockKey);
          return;
        }
        await _switch(
          target.chapterKey,
          blockKey: target.blockKey,
          fromStart: true,
        );
      }
      return;
    }
    if (widget.offline) {
      final entries =
          _catalog.loaded?.value.flatChapters.toList() ?? <Chapter>[];
      if (!mounted) return;
      final selected = await showModalBottomSheet<ChapterKey>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            children: [
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(AppLocalizations.of(context).cacheEmpty),
                ),
              for (final item in entries)
                ListTile(
                  title: Text(item.title),
                  onTap: () => Navigator.pop(context, item.key),
                ),
            ],
          ),
        ),
      );
      if (mounted && selected != null) await _switch(selected);
      return;
    }
    final key = await openCatalog(
      context,
      novel: widget.chapter.novelKey,
      repository: widget.repository,
      current: _reader.chapter,
    );
    if (mounted && key != null) await _switch(key);
  }

  Future<void> _details() async {
    if (_changing || widget.onDetails == null) return;
    setState(() => _changing = true);
    if (!await _save()) {
      if (mounted) setState(() => _changing = false);
      return;
    }
    widget.onDetails!(widget.chapter.novelKey);
  }

  Widget _view(ReaderController reader) {
    final chapters =
        _catalog.loaded?.value.flatChapters.toList() ?? <Chapter>[];
    final order = _needsOrder
        ? _readingOrder ?? <ChapterKey>[]
        : chapters.map((c) => c.key).toList();
    final index = chapters.indexWhere((c) => c.key == reader.chapter);
    ChapterKey? previous, next;
    if (index >= 0 && widget.linkDepth == 0) {
      for (var i = index - 1; i >= 0; i--) {
        if (order.contains(chapters[i].key)) {
          previous = chapters[i].key;
          break;
        }
      }
      for (var i = index + 1; i < chapters.length; i++) {
        if (order.contains(chapters[i].key)) {
          next = chapters[i].key;
          break;
        }
      }
    }

    return ReaderContentView(
      key: ValueKey(reader),
      content: reader.content!,
      onReady: () => _commitPending(reader),
      onPageAppearance: (paper) {
        if (reader == _reader) {
          _paper = paper;
        }
      },
      onLoadFailure: () => _rejectPending(reader),
      runningTitle: _runningTitle(reader),
      images: _displayImages,
      settings: widget.settings,
      session: reader,
      initialPosition: reader.initialPosition,
      onCatalog: _changing || widget.linkDepth > 0 ? null : _contents,
      onLinks: _changing || reader.contentLinks.isEmpty ? null : _links,
      returnToOrigin: widget.linkDepth > 0,
      onPrefetch: !widget.offline && _cache?.prefetch != null
          ? () => showPrefetchSheet(
              context,
              cache: _cache!,
              catalog: _catalog.loaded?.value,
              current: reader.chapter,
            )
          : null,
      onDetails: widget.onDetails == null || _changing ? null : _details,
      onPreviousChapter: !_changing && previous != null
          ? () => _switch(previous!, fromEnd: true)
          : null,
      onNextChapter: !_changing && next != null
          ? () => _switch(next!, fromStart: true)
          : null,
    );
  }

  Widget _pageLayer(ReaderController reader, {required bool active}) =>
      Positioned.fill(
        key: ValueKey(reader),
        child: IgnorePointer(
          ignoring: !active || _changing,
          child: AnimatedBuilder(
            animation: _chapterTurn,
            child: ExcludeSemantics(excluding: !active, child: _view(reader)),
            builder: (context, child) => ClipPath(
              clipper: PaperTurnClipper(
                active ? _chapterTurn.value : 0,
                _turnDirection,
              ),
              child: child,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
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

    return SourceImageDecodeScope(
      child: PopScope(
        // Cupertino's interactive back gesture requires canPop before it starts.
        // Periodic/lifecycle commits remain the durable boundary on every platform.
        canPop: _canPop || Theme.of(context).platform == TargetPlatform.iOS,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            unawaited(_exit());
          } else {
            unawaited(_reader.flushProgress());
          }
        },
        child: _reader.status == ReaderStatus.ready
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (_pending case final pending?
                      when pending.status == ReaderStatus.ready)
                    _pageLayer(pending, active: false),
                  _pageLayer(_reader, active: true),
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _chapterTurn,
                      builder: (context, _) => PaperTurnFold(
                        progress: _chapterTurn.value,
                        direction: _turnDirection,
                        paper: _paper,
                      ),
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
