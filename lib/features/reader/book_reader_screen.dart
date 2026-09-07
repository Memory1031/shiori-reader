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
import '../cache/prefetch_sheet.dart';
import '../../shared/source_image.dart';

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
  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen>
    with WidgetsBindingObserver {
  late ReaderController _reader;
  late final ImageRepository? _displayImages;
  late final CatalogController _catalog;
  bool _changing = false, _canPop = false;
  @override
  void initState() {
    super.initState();
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
    _reader = _create(widget.chapter);
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

  ReaderController _create(ChapterKey key) =>
      ReaderController(
          repository: widget.repository,
          chapter: key,
          library: widget.library,
          cache: widget.cache,
          readMode: widget.offline ? ReadMode.cacheOnly : ReadMode.cacheFirst,
          onPosition: widget.offline ? null : widget.cache?.prefetch?.position,
        )
        ..onStart()
        ..addListener(_changed);
  void _changed() {
    if (!widget.offline && _reader.content != null) {
      unawaited(
        widget.cache?.prefetch?.enter(_reader.content!, _catalog.loaded?.value),
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
    if (!widget.offline) widget.cache?.prefetch?.leave();
    WidgetsBinding.instance.removeObserver(this);
    _close(_reader);
    _catalog.removeListener(_changed);
    _catalog.onDelete();
    _catalog.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.offline) {
      widget.cache?.prefetch?.active(state == AppLifecycleState.resumed);
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

  Future<void> _switch(ChapterKey chapter) async {
    if (_changing ||
        chapter == _reader.chapter ||
        chapter.novelKey != widget.chapter.novelKey) {
      return;
    }
    setState(() => _changing = true);
    if (!await _save()) {
      if (mounted) setState(() => _changing = false);
      return;
    }
    _close(_reader);
    setState(() {
      _reader = _create(chapter);
      _changing = false;
    });
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

  Future<void> _contents() async {
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

  @override
  Widget build(BuildContext context) {
    final chapters =
        _catalog.loaded?.value.flatChapters.toList() ?? <Chapter>[];
    final index = chapters.indexWhere((c) => c.key == _reader.chapter);
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
            ? ReaderContentView(
                key: ValueKey(_reader),
                content: _reader.content!,
                images: _displayImages,
                settings: widget.settings,
                session: _reader,
                initialPosition: _reader.initialPosition,
                onCatalog: _changing ? null : _contents,
                onPrefetch: !widget.offline && widget.cache?.prefetch != null
                    ? () => showPrefetchSheet(
                        context,
                        cache: widget.cache!,
                        catalog: _catalog.loaded?.value,
                        current: _reader.chapter,
                      )
                    : null,
                onDetails: widget.onDetails == null || _changing
                    ? null
                    : _details,
                onPreviousChapter: !_changing && index > 0
                    ? () => _switch(chapters[index - 1].key)
                    : null,
                onNextChapter:
                    !_changing && index >= 0 && index + 1 < chapters.length
                    ? () => _switch(chapters[index + 1].key)
                    : null,
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
