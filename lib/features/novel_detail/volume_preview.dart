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
          Row(
            children: [
              Expanded(
                child: Text(
                  l.catalogTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
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
                child: Text('${l.allChapters} ›'),
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
            SizedBox(
              height: 340,
              child: CatalogView(
                catalog: catalog,
                onSelect: (chapter) => onChapter?.call(chapter),
              ),
            ),
        ],
      );
    },
  );
}
