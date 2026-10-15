import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/controllers/scoped_controller.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import '../novel_detail/catalog_view.dart';
import 'book_reader_screen.dart';
import 'reader_loading_page.dart';
import 'reader_preferences.dart';
import 'reader_theme.dart';

class ContinueController extends ScopedController {
  ContinueController({
    required this.novel,
    required this.repository,
    required this.library,
  });
  final NovelKey novel;
  final NovelRepository repository;
  final LibraryRepository library;
  LocalBookUse? _bookUse;
  Future<void>? _openingUse;
  Future<void> _acquireUse() => _openingUse ??= () async {
    if (repository case LocalBookUsage usage) {
      _bookUse = await usage.acquireBookUse(novel, cancellation: cancellation);
    }
  }();
  @override
  void onClose() {
    super.onClose();
    unawaited(() async {
      try {
        await _openingUse;
      } catch (_) {
        /* Cancelled initialization. */
      }
      await _bookUse?.release();
    }());
  }

  ChapterKey? chapter;
  AppFailure? failure;
  bool loading = false, usedFallback = false;
  @override
  void onInit() {
    super.onInit();
    unawaited(load());
  }

  Future<void> load() async {
    if (isClosed || loading) return;
    loading = true;
    failure = null;
    update();
    try {
      await _acquireUse();
      if (isClosed) return;
      final progress = await library.getProgress(
        novel,
        cancellation: cancellation,
      );
      if (isClosed) return;
      if (progress case Failure(:final failure)) {
        this.failure = failure;
        return;
      }
      final saved = (progress as Success<ReadingProgress?>).value;
      if (saved != null) {
        final cached = await repository.loadChapter(
          saved.chapterKey,
          mode: ReadMode.cacheOnly,
          cancellation: cancellation,
        );
        if (isClosed) return;
        if (cached is Success<LoadResult<ChapterContent>> &&
            cached.value.value.key == saved.chapterKey) {
          chapter = saved.chapterKey;
          return;
        }
      }
      var catalog = await repository.loadCatalog(
        novel,
        mode: ReadMode.cacheOnly,
        cancellation: cancellation,
      );
      if (isClosed) return;
      if (catalog is Failure<LoadResult<Catalog>>) {
        catalog = await repository.loadCatalog(
          novel,
          mode: ReadMode.cacheFirst,
          cancellation: cancellation,
        );
      }
      if (isClosed) return;
      if (catalog case Failure(:final failure)) {
        this.failure = failure;
        return;
      }
      final value = (catalog as Success<LoadResult<Catalog>>).value.value;
      if (value.novelKey != novel) {
        failure = AppFailure(
          kind: FailureKind.parse,
          operation: Operation.catalog,
        );
        return;
      }
      final chapters = value.flatChapters.toList();
      if (chapters.isEmpty) return;
      final index = saved == null
          ? -1
          : chapters.indexWhere((c) => c.key == saved.chapterKey);
      usedFallback = saved != null && index < 0;
      chapter = index >= 0
          ? chapters[index].key
          : chapters[(saved?.chapterOrdinalSnapshot ?? 0).clamp(
                  0,
                  chapters.length - 1,
                )]
                .key;
    } catch (_) {
      failure = AppFailure(
        kind: FailureKind.sourceUnavailable,
        operation: Operation.chapter,
        retryPolicy: RetryPolicy.manual,
      );
    } finally {
      if (chapter == null) {
        await _bookUse?.release();
        _bookUse = null;
        _openingUse = null;
      }
      if (!isClosed) {
        loading = false;
        update();
      }
    }
  }
}

class ContinueReadingScreen extends StatefulWidget {
  const ContinueReadingScreen({
    super.key,
    required this.novel,
    required this.repository,
    required this.library,
    this.images,
    this.settings,
    this.preferences,
    this.onDetails,
    this.cache,
    this.onReturnToShelf,
  });
  final NovelKey novel;
  final NovelRepository repository;
  final LibraryRepository library;
  final ImageRepository? images;
  final SettingsStore? settings;
  final ReaderPreferences? preferences;
  final Future<void> Function(BuildContext readerContext, NovelKey key)?
  onDetails;
  final CacheManagement? cache;
  final VoidCallback? onReturnToShelf;

  @override
  State<ContinueReadingScreen> createState() => _ContinueReadingScreenState();
}

class _ContinueReadingScreenState extends State<ContinueReadingScreen> {
  late final _preferences =
      widget.preferences ?? ReaderPreferences(widget.settings);

  @override
  void initState() {
    super.initState();
    unawaited(_preferences.ready);
  }

  @override
  void dispose() {
    if (widget.preferences == null) _preferences.dispose();
    super.dispose();
  }

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
    child: ControllerScope<ContinueController>(
      key: ValueKey((widget.novel, widget.repository, widget.library)),
      create: () => ContinueController(
        novel: widget.novel,
        repository: widget.repository,
        library: widget.library,
      ),
      builder: (context, controller) {
        if (controller.chapter != null) {
          return BookReaderScreen(
            chapter: controller.chapter!,
            repository: widget.repository,
            library: widget.library,
            images: widget.images,
            settings: widget.settings,
            preferences: _preferences,
            chapterFallback: controller.usedFallback,
            onDetails: widget.onDetails,
            cache: widget.cache,
            onReturnToShelf: widget.onReturnToShelf,
          );
        }
        if (controller.loading) return const ReaderLoadingPage();
        final strings = AppLocalizations.of(context);
        return Scaffold(
          appBar: AppBar(title: Text(strings.detailContinue)),
          body: SafeArea(
            child: controller.failure != null
                ? FailureView(
                    failure: controller.failure!,
                    onRetry: controller.load,
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(strings.catalogEmpty),
                        TextButton(
                          onPressed: () async {
                            final key = await openCatalog(
                              context,
                              novel: widget.novel,
                              repository: widget.repository,
                            );
                            if (context.mounted && key != null) {
                              controller.chapter = key;
                              controller.update();
                            }
                          },
                          child: Text(strings.catalogTitle),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    ),
  );
}
