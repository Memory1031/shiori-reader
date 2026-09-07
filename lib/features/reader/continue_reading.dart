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

class ContinueController extends ScopedController {
  ContinueController({
    required this.novel,
    required this.repository,
    required this.library,
  });
  final NovelKey novel;
  final NovelRepository repository;
  final LibraryRepository library;
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
      if (!isClosed) {
        loading = false;
        update();
      }
    }
  }
}

class ContinueReadingScreen extends StatelessWidget {
  const ContinueReadingScreen({
    super.key,
    required this.novel,
    required this.repository,
    required this.library,
    this.images,
    this.settings,
    this.onDetails,
  });
  final NovelKey novel;
  final NovelRepository repository;
  final LibraryRepository library;
  final ImageRepository? images;
  final SettingsStore? settings;
  final ValueChanged<NovelKey>? onDetails;
  @override
  Widget build(BuildContext context) => ControllerScope<ContinueController>(
    key: ValueKey((novel, repository, library)),
    create: () => ContinueController(
      novel: novel,
      repository: repository,
      library: library,
    ),
    builder: (context, controller) {
      if (controller.chapter != null) {
        return BookReaderScreen(
          chapter: controller.chapter!,
          repository: repository,
          library: library,
          images: images,
          settings: settings,
          chapterFallback: controller.usedFallback,
          onDetails: onDetails,
        );
      }
      final strings = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(strings.detailContinue)),
        body: SafeArea(
          child: controller.loading
              ? const LoadingView()
              : controller.failure != null
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
                            novel: novel,
                            repository: repository,
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
  );
}
