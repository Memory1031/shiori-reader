import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../l10n/generated/app_localizations.dart';
import 'detail_sections.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import 'desktop_detail.dart';
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
      final canChangeShelf = onShelf != null || onShelfSnapshot != null;
      void changeShelf() {
        if (loaded == null) return;
        if (onShelfSnapshot != null) {
          onShelfSnapshot!(loaded.value.summary);
        } else {
          onShelf?.call(novel);
        }
      }

      final menu = PopupMenuButton<String>(
        key: const ValueKey('detail-more'),
        tooltip: strings.moreActions,
        icon: const Icon(Icons.more_horiz),
        onSelected: (value) {
          if (value == 'refresh') controller.refreshDetail();
          if (value == 'remove') changeShelf();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            key: const ValueKey('detail-refresh'),
            value: 'refresh',
            enabled: controller.canLoad,
            child: Text(strings.detailRefresh),
          ),
          if (isOnShelf && loaded != null)
            PopupMenuItem(
              key: const ValueKey('detail-remove'),
              value: 'remove',
              enabled: canChangeShelf,
              child: Text(strings.detailRemoveShelf),
            ),
        ],
      );
      final desktop = ShioriCapabilities.of(context).pointerFirst;
      if (loaded == null) {
        final placeholder = controller.loading
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
              );
        return desktop
            ? DesktopDetail(menu: menu, placeholder: placeholder)
            : AppScaffold(
                title: strings.novelDetailsTitle,
                actions: [menu],
                body: placeholder,
              );
      }

      final notices = [
        if (controller.loading)
          LinearProgressIndicator(semanticsLabel: strings.loading),
        if (loaded.isStale)
          Padding(
            padding: const EdgeInsets.only(bottom: ShioriSpace.item),
            child: Text(strings.detailStale),
          ),
        if (controller.failure != null)
          FailureView(
            failure: controller.failure!,
            onRetry: controller.refreshDetail,
            retryAvailable: !controller.loading,
          ),
      ];
      Widget read() => FilledButton.icon(
        key: const ValueKey('detail-read'),
        onPressed: onRead == null ? null : () => onRead!(novel),
        icon: const Icon(Icons.auto_stories_outlined, size: 18),
        label: Text(
          continueReading ? strings.detailContinue : strings.detailStart,
          textAlign: TextAlign.center,
        ),
      );
      Widget shelf(BuildContext context) => isOnShelf
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_added_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: ShioriSpace.small),
                  Flexible(
                    child: Text(
                      strings.detailOnShelf,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            )
          : OutlinedButton(
              key: const ValueKey('detail-shelf'),
              onPressed: canChangeShelf ? changeShelf : null,
              child: Text(strings.detailAddShelf, textAlign: TextAlign.center),
            );
      final actionNotes = [
        if (actionFailure != null) FailureView(failure: actionFailure!),
        if (showPendingActions &&
            (onRead == null ||
                (onShelf == null && onShelfSnapshot == null))) ...[
          const SizedBox(height: ShioriSpace.small),
          Text(strings.detailActionsPending),
        ],
      ];
      // A local file without a description has nothing more to fetch, so its
      // synopsis section is left out; an online source says it has none.
      final showSynopsis =
          loaded.value.synopsis.trim().isNotEmpty ||
          novel.sourceId != LocalBookIdentity.sourceId;
      final catalog = VolumePreview(
        novel: novel,
        repository: repository,
        onChapter: onChapter,
        onTarget: onTarget,
      );

      if (desktop) {
        final detail = loaded.value;
        return DesktopDetail(
          menu: menu,
          notices: notices,
          cover: DetailCover(book: detail.summary, images: images),
          info: DetailBookInfo(detail: detail, authorLines: 2),
          tags: detail.tags.isEmpty ? null : DetailTags(tags: detail.tags),
          read: read(),
          shelf: shelf(context),
          actionNotes: actionNotes,
          synopsis: showSynopsis
              ? DetailSynopsis(
                  key: ValueKey(('synopsis', novel)),
                  text: detail.synopsis,
                  lines: 6,
                )
              : null,
          catalog: catalog,
        );
      }

      return AppScaffold(
        title: strings.novelDetailsTitle,
        actions: [menu],
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ShioriLayout.page),
            child: ListView(
              padding: const EdgeInsets.all(ShioriSpace.page),
              children: [
                ...notices,
                DetailBookHeader(
                  key: ValueKey(novel),
                  detail: loaded.value,
                  images: images,
                ),
                const SizedBox(height: ShioriSpace.section),
                LayoutBuilder(
                  builder: (context, bounds) {
                    if (bounds.maxWidth < 340 ||
                        MediaQuery.textScalerOf(context).scale(14) > 20) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          read(),
                          const SizedBox(height: ShioriSpace.small),
                          shelf(context),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 3, child: read()),
                        const SizedBox(width: ShioriSpace.medium),
                        Expanded(flex: 2, child: shelf(context)),
                      ],
                    );
                  },
                ),
                ...actionNotes,
                if (showSynopsis) ...[
                  const SizedBox(height: ShioriSpace.section),
                  Text(
                    strings.detailSynopsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: ShioriSpace.medium),
                  DetailSynopsis(
                    key: ValueKey(('synopsis', novel)),
                    text: loaded.value.synopsis,
                  ),
                ],
                const SizedBox(height: ShioriSpace.section),
                catalog,
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
    },
  );
}
