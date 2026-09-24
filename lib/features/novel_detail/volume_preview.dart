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
      final localNavigation =
          novel.sourceId == LocalBookIdentity.sourceId &&
              repository is LocalNavigationRepository
          ? repository as LocalNavigationRepository
          : null;
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
                  if (localNavigation != null) {
                    final target = await openLocalCatalog(
                      context,
                      novel: novel,
                      repository: localNavigation,
                    );
                    if (context.mounted && target != null) {
                      if (onTarget != null) {
                        onTarget!(target);
                      } else {
                        onChapter?.call(target.chapterKey);
                      }
                    }
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
          if (localNavigation == null && controller.loading)
            const LinearProgressIndicator(),
          if (localNavigation == null &&
              controller.failure != null &&
              controller.failure!.context != FailureContext.cacheMiss)
            Text(
              failureMessage(l, controller.failure!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (localNavigation != null)
            _LocalNavigationPreview(
              novel: novel,
              repository: localNavigation,
              onTarget: onTarget,
              onChapter: onChapter,
            )
          else if (catalog == null)
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

/// EPUB navigation labels may differ from the spine document titles. Preview
/// the same entries as the full local contents screen, including fragments.
class _LocalNavigationPreview extends StatefulWidget {
  const _LocalNavigationPreview({
    required this.novel,
    required this.repository,
    this.onTarget,
    this.onChapter,
  });
  final NovelKey novel;
  final LocalNavigationRepository repository;
  final ValueChanged<LocalNavigationEntry>? onTarget;
  final ValueChanged<ChapterKey>? onChapter;

  @override
  State<_LocalNavigationPreview> createState() =>
      _LocalNavigationPreviewState();
}

class _LocalNavigationPreviewState extends State<_LocalNavigationPreview> {
  CancellationSource _request = CancellationSource();
  late Future<Result<List<LocalNavigationEntry>>> _result = _load();

  Future<Result<List<LocalNavigationEntry>>> _load() async {
    try {
      return await widget.repository.loadNavigation(
        widget.novel,
        cancellation: _request.token,
      );
    } catch (_) {
      return Failure(
        AppFailure(
          kind: FailureKind.sourceUnavailable,
          operation: Operation.catalog,
          retryPolicy: RetryPolicy.manual,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _LocalNavigationPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.novel != widget.novel ||
        oldWidget.repository != widget.repository) {
      _request.cancel();
      _request = CancellationSource();
      _result = _load();
    }
  }

  @override
  void dispose() {
    _request.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _result,
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final result = snapshot.data!;
      if (result case Failure(:final failure)) {
        final l = AppLocalizations.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(failureMessage(l, failure)),
            TextButton(
              onPressed: () {
                _request.cancel();
                _request = CancellationSource();
                setState(() => _result = _load());
              },
              child: Text(l.retryAction),
            ),
          ],
        );
      }
      final rows = <(LocalNavigationEntry, int)>[];
      void collect(List<LocalNavigationEntry> entries, int depth) {
        for (final entry in entries) {
          if (rows.length == 5) return;
          rows.add((entry, depth));
          collect(entry.children, depth + 1);
        }
      }

      collect((result as Success<List<LocalNavigationEntry>>).value, 0);
      if (rows.isEmpty) {
        return EmptyView(message: AppLocalizations.of(context).catalogEmpty);
      }
      final theme = Theme.of(context);
      return Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey(('preview-local', i)),
                onTap: widget.onTarget != null
                    ? () => widget.onTarget!(rows[i].$1)
                    : widget.onChapter == null
                    ? null
                    : () => widget.onChapter!(rows[i].$1.chapterKey),
                child: Container(
                  padding: EdgeInsetsDirectional.only(
                    start: rows[i].$2.clamp(0, 4) * 12.0,
                    top: 14,
                    bottom: 14,
                  ),
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
                          rows[i].$1.title,
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
        ],
      );
    },
  );
}
