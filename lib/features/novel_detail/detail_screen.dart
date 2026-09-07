import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/source_image.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import 'detail_controller.dart';
import 'catalog_view.dart';

class DetailScreen extends StatelessWidget {
  const DetailScreen({
    super.key,
    required this.novel,
    required this.repository,
    this.images,
    this.onRead,
    this.onShelf,
    this.onChapter,
    this.onShelfSnapshot,
    this.actionFailure,
    this.showPendingActions = true,
    this.continueReading = false,
    this.isOnShelf = false,
  });
  final NovelKey novel;
  final NovelRepository repository;
  final ImageRepository? images;
  final ValueChanged<NovelKey>? onRead, onShelf;
  final ValueChanged<ChapterKey>? onChapter;
  final ValueChanged<NovelSummary>? onShelfSnapshot;
  final AppFailure? actionFailure;
  final bool showPendingActions;
  final bool continueReading, isOnShelf;

  @override
  Widget build(BuildContext context) => ControllerScope<DetailController>(
    key: ValueKey((novel, repository)),
    create: () => DetailController(repository: repository, novel: novel),
    builder: (context, controller) {
      final strings = AppLocalizations.of(context);
      final loaded = controller.loaded;
      return AppScaffold(
        title: strings.novelDetailsTitle,
        actions: [
          IconButton(
            key: const ValueKey('detail-refresh'),
            tooltip: strings.detailRefresh,
            onPressed: controller.canLoad ? controller.refreshDetail : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
        body: loaded == null
            ? controller.loading
                  ? const LoadingView()
                  : controller.failure != null
                  ? FailureView(
                      failure: controller.failure!,
                      onRetry: controller.load,
                    )
                  : Center(
                      child: TextButton(
                        onPressed: controller.load,
                        child: Text(strings.retryAction),
                      ),
                    )
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: ListView(
                    padding: const EdgeInsets.all(ShioriSpace.page),
                    children: [
                      if (controller.loading)
                        LinearProgressIndicator(
                          semanticsLabel: strings.loading,
                        ),
                      if (loaded.isStale)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: ShioriSpace.item,
                          ),
                          child: Text(strings.detailStale),
                        ),
                      if (controller.failure != null)
                        FailureView(
                          failure: controller.failure!,
                          onRetry: controller.refreshDetail,
                          retryAvailable: !controller.loading,
                        ),
                      _Header(detail: loaded.value, images: images),
                      const SizedBox(height: ShioriSpace.section),
                      OutlinedButton.icon(
                        key: const ValueKey('detail-catalog'),
                        icon: const Icon(Icons.list),
                        label: Text(strings.catalogTitle),
                        onPressed: () async {
                          final key = await openCatalog(
                            context,
                            novel: novel,
                            repository: repository,
                          );
                          if (context.mounted && key != null) {
                            onChapter?.call(key);
                          }
                        },
                      ),
                      Wrap(
                        spacing: ShioriSpace.medium,
                        runSpacing: ShioriSpace.medium,
                        children: [
                          FilledButton(
                            key: const ValueKey('detail-read'),
                            onPressed: onRead == null
                                ? null
                                : () => onRead!(novel),
                            child: Text(
                              continueReading
                                  ? strings.detailContinue
                                  : strings.detailStart,
                            ),
                          ),
                          OutlinedButton(
                            key: const ValueKey('detail-shelf'),
                            onPressed:
                                onShelf == null && onShelfSnapshot == null
                                ? null
                                : () => onShelfSnapshot != null
                                      ? onShelfSnapshot!(loaded.value.summary)
                                      : onShelf!(novel),
                            child: Text(
                              isOnShelf
                                  ? strings.detailRemoveShelf
                                  : strings.detailAddShelf,
                            ),
                          ),
                        ],
                      ),
                      if (actionFailure != null)
                        FailureView(failure: actionFailure!),
                      if (showPendingActions &&
                          (onRead == null ||
                              (onShelf == null &&
                                  onShelfSnapshot == null))) ...[
                        const SizedBox(height: ShioriSpace.small),
                        Text(strings.detailActionsPending),
                      ],
                      const SizedBox(height: ShioriSpace.section),
                      Text(
                        strings.detailSynopsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: ShioriSpace.medium),
                      Text(
                        loaded.value.synopsis.trim().isEmpty
                            ? strings.detailNoSynopsis
                            : loaded.value.synopsis,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.detail, this.images});
  final NovelDetail detail;
  final ImageRepository? images;
  @override
  Widget build(BuildContext context) {
    final book = detail.summary;
    final strings = AppLocalizations.of(context);
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(ShioriShape.cover),
      child: SizedBox(
        width: 144,
        height: 144 / ShioriShape.coverRatio,
        child: book.cover != null && images != null
            ? SourceImage(
                media: book.cover!,
                repository: images!,
                semanticLabel: strings.detailCover,
              )
            : ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.bookmark_outline, size: 40),
              ),
      ),
    );
    final metadata = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            book.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        if (book.authors.isNotEmpty) ...[
          const SizedBox(height: ShioriSpace.medium),
          Text(book.authors.join(', ')),
        ],
        const SizedBox(height: ShioriSpace.medium),
        Text(switch (detail.status) {
          NovelStatus.unknown => strings.detailStatusUnknown,
          NovelStatus.ongoing => strings.detailStatusOngoing,
          NovelStatus.completed => strings.detailStatusCompleted,
          NovelStatus.hiatus => strings.detailStatusHiatus,
        }),
        if (detail.tags.isNotEmpty) ...[
          const SizedBox(height: ShioriSpace.medium),
          Wrap(
            spacing: ShioriSpace.small,
            runSpacing: ShioriSpace.small,
            children: [
              for (final tag in detail.tags)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(ShioriShape.control),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(ShioriSpace.small),
                    child: Text(tag),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) => bounds.maxWidth >= 600
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cover,
                const SizedBox(width: ShioriSpace.page),
                Expanded(child: metadata),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: cover),
                const SizedBox(height: ShioriSpace.page),
                metadata,
              ],
            ),
    );
  }
}
