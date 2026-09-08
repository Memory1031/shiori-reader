import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/source_image.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import 'detail_controller.dart';

import 'volume_preview.dart';

class DetailScreen extends StatelessWidget {
  const DetailScreen({
    super.key,
    required this.novel,
    required this.repository,
    this.images,
    this.onRead,
    this.onShelf,
    this.onChapter,
    this.onTarget,
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
  final ValueChanged<LocalNavigationEntry>? onTarget;
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
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 32),
                      VolumePreview(
                        novel: novel,
                        repository: repository,
                        onChapter: onChapter,
                        onTarget: onTarget,
                      ),
                      const SizedBox(height: 24),
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
        width: 120,
        height: 120 / ShioriShape.coverRatio,
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
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (book.authors.isNotEmpty) ...[
          const SizedBox(height: ShioriSpace.medium),
          Text(book.authors.join(', ')),
        ],
        const SizedBox(height: ShioriSpace.medium),
        if (detail.status != NovelStatus.unknown)
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      tag,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primary.withValues(alpha: .22),
                colors.surfaceContainerHighest,
                colors.primary.withValues(alpha: .06),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: .18),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: cover,
            ),
          ),
        ),
        const SizedBox(height: 24),
        metadata,
      ],
    );
  }
}
