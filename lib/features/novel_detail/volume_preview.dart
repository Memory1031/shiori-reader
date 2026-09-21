import 'package:flutter/material.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../local_books/local_catalog.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import 'catalog_controller.dart';
import 'catalog_view.dart';

/// Source group and chapter identities are preserved, including full-volume posts.
class VolumePreview extends StatelessWidget {
  const VolumePreview({
    super.key,
    required this.novel,
    required this.repository,
    this.onChapter,
    this.onTarget,
  });
  final NovelKey novel;
  final NovelRepository repository;
  final ValueChanged<ChapterKey>? onChapter;
  final ValueChanged<LocalNavigationEntry>? onTarget;

  @override
  Widget build(BuildContext context) => ControllerScope<CatalogController>(
    key: ValueKey((novel, repository)),
    create: () => CatalogController(
      repository: repository,
      novel: novel,
      initialMode: ReadMode.cacheOnly,
    ),
    builder: (context, controller) {
      final l = AppLocalizations.of(context);
      final catalog = controller.loaded?.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(
                l.catalogTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton(
                key: const ValueKey('detail-catalog'),
                onPressed: () async {
                  final navigation = repository;
                  if (novel.sourceId == LocalBookIdentity.sourceId &&
                      navigation is LocalNavigationRepository &&
                      onTarget != null) {
                    final target = await openLocalCatalog(
                      context,
                      novel: novel,
                      repository: navigation as LocalNavigationRepository,
                    );
                    if (context.mounted && target != null) onTarget!(target);
                    return;
                  }
                  final key = await openCatalog(
                    context,
                    novel: novel,
                    repository: repository,
                  );
                  if (context.mounted && key != null) onChapter?.call(key);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.allChapters),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (controller.loading) const LinearProgressIndicator(),
          if (controller.failure != null &&
              controller.failure!.context != FailureContext.cacheMiss)
            Text(
              failureMessage(l, controller.failure!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (catalog == null)
            TextButton.icon(
              onPressed: controller.canLoad ? controller.load : null,
              icon: const Icon(Icons.auto_stories_outlined),
              label: Text(l.volumesLoad),
            )
          else if (catalog.flatChapters.isEmpty)
            EmptyView(message: l.catalogEmpty)
          else
            ..._preview(context, catalog),
        ],
      );
    },
  );

  List<Widget> _preview(BuildContext context, Catalog catalog) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    var remaining = 5;
    for (final volume in catalog.volumes) {
      if (remaining == 0) break;
      if (volume.chapters.isEmpty) continue;
      if (!volume.isSynthetic) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Semantics(
              header: true,
              child: Text(
                volume.title ??
                    AppLocalizations.of(context).catalogUnnamedVolume,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
        );
      }
      for (final chapter in volume.chapters.take(remaining)) {
        rows.add(
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey(('preview-chapter', chapter.key)),
              onTap: onChapter == null ? null : () => onChapter!(chapter.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: .45,
                      ),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chapter.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        remaining--;
      }
    }
    return rows;
  }
}
