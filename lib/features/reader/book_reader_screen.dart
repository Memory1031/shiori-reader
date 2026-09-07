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
  });
  final ChapterKey chapter;
  final NovelRepository repository;
  final ImageRepository? images;
  final LibraryRepository? library;
  final SettingsStore? settings;
  final bool chapterFallback;
  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen>
    with WidgetsBindingObserver {
  late ReaderController _reader;
  late final CatalogController _catalog;
  bool _changing = false, _canPop = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _catalog =
        CatalogController(
            repository: widget.repository,
            novel: widget.chapter.novelKey,
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
        )
        ..onStart()
        ..addListener(_changed);
  void _changed() {
    if (mounted) setState(() {});
  }

  void _close(ReaderController reader) {
    reader.removeListener(_changed);
    reader.onDelete();
    reader.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _close(_reader);
    _catalog.removeListener(_changed);
    _catalog.onDelete();
    _catalog.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
      return false;
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
    final key = await openCatalog(
      context,
      novel: widget.chapter.novelKey,
      repository: widget.repository,
      current: _reader.chapter,
    );
    if (mounted && key != null) await _switch(key);
  }

  @override
  Widget build(BuildContext context) {
    final chapters =
        _catalog.loaded?.value.flatChapters.toList() ?? <Chapter>[];
    final index = chapters.indexWhere((c) => c.key == _reader.chapter);
    return PopScope(
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
              images: widget.images,
              settings: widget.settings,
              session: _reader,
              initialPosition: _reader.initialPosition,
              onCatalog: _changing ? null : _contents,
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
    );
  }
}
