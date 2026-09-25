import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_list_tile.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import 'catalog_controller.dart';

/// The book's whole catalog as slivers, scrolled with the rest of the
/// details and built lazily. Source group and chapter identities are
/// preserved, including full-volume posts.
///
/// Lay it out [BookListItem.inset] wider than the section on each side:
/// row tints reach past the section edge while row text and everything
/// else stays on it.
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
      return SliverMainAxisGroup(
        slivers: [
          _boxed(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.catalogTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: ShioriSpace.item),
                if (localNavigation == null && controller.loading)
                  const LinearProgressIndicator(),
                if (localNavigation == null &&
                    controller.failure != null &&
                    controller.failure!.context != FailureContext.cacheMiss)
                  Text(
                    failureMessage(l, controller.failure!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (localNavigation != null)
            _LocalNavigationPreview(
              novel: novel,
              repository: localNavigation,
              updateGeneration: controller.updateGeneration,
              onTarget: onTarget,
              onChapter: onChapter,
            )
          else if (catalog == null)
            _boxed(
              TextButton.icon(
                onPressed: controller.canLoad ? controller.load : null,
                icon: const Icon(Icons.auto_stories_outlined),
                label: Text(l.volumesLoad),
              ),
            )
          else if (catalog.flatChapters.isEmpty)
            _boxed(EmptyView(message: l.catalogEmpty))
          else
            _rows(catalog),
        ],
      );
    },
  );

  /// Every volume heading and chapter row, built as they scroll into view.
  Widget _rows(Catalog catalog) {
    final items = <Object>[
      for (final volume in catalog.volumes)
        if (volume.chapters.isNotEmpty) ...[
          if (!volume.isSynthetic) volume,
          ...volume.chapters,
        ],
    ];
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => switch (items[i]) {
        final Volume volume => Padding(
          padding: const EdgeInsetsDirectional.only(
            start: BookListItem.inset,
            end: BookListItem.inset,
            top: 12,
            bottom: 4,
          ),
          child: Semantics(
            header: true,
            child: Text(
              volume.title ?? AppLocalizations.of(context).catalogUnnamedVolume,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        final chapter as Chapter => _PreviewRow(
          key: ValueKey(('preview-chapter', chapter.key)),
          title: chapter.title,
          onTap: onChapter == null ? null : () => onChapter!(chapter.key),
        ),
      },
    );
  }
}

/// [child] as a sliver on the section, inside the rows' bleed.
Widget _boxed(Widget child) => SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: BookListItem.inset),
    child: child,
  ),
);

/// EPUB navigation labels may differ from the spine document titles. Lists
/// the same entries as the full local contents screen, including fragments.
class _LocalNavigationPreview extends StatefulWidget {
  const _LocalNavigationPreview({
    required this.novel,
    required this.repository,
    required this.updateGeneration,
    this.onTarget,
    this.onChapter,
  });
  final NovelKey novel;
  final LocalNavigationRepository repository;
  final int updateGeneration;
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
        oldWidget.repository != widget.repository ||
        oldWidget.updateGeneration != widget.updateGeneration) {
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
      if (!snapshot.hasData) return _boxed(const LinearProgressIndicator());
      final result = snapshot.data!;
      if (result case Failure(:final failure)) {
        final l = AppLocalizations.of(context);
        return _boxed(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(failureMessage(l, failure)),
              TextButton(
                onPressed: () {
                  _request.cancel();
                  _request = CancellationSource();
                  setState(() {
                    _result = _load();
                  });
                },
                child: Text(l.retryAction),
              ),
            ],
          ),
        );
      }
      final rows = <(LocalNavigationEntry, int)>[];
      void collect(List<LocalNavigationEntry> entries, int depth) {
        for (final entry in entries) {
          rows.add((entry, depth));
          collect(entry.children, depth + 1);
        }
      }

      collect((result as Success<List<LocalNavigationEntry>>).value, 0);
      if (rows.isEmpty) {
        return _boxed(
          EmptyView(message: AppLocalizations.of(context).catalogEmpty),
        );
      }
      return SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) => _PreviewRow(
          key: ValueKey(('preview-local', i)),
          title: rows[i].$1.title,
          indent: rows[i].$2.clamp(0, 4) * 12.0,
          onTap: widget.onTarget != null
              ? () => widget.onTarget!(rows[i].$1)
              : widget.onChapter == null
              ? null
              : () => widget.onChapter!(rows[i].$1.chapterKey),
        ),
      );
    },
  );
}

/// A catalog row in the shelf list's style: a rounded accent tint
/// on hover, focus and press instead of an edge-to-edge overlay.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    super.key,
    required this.title,
    this.indent = 0,
    this.onTap,
  });
  final String title;
  final double indent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => BookListItem(
    minHeight: 0,
    onTap: onTap,
    child: Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          // With the row's own padding, keeps the earlier 14 above and below.
          padding: EdgeInsetsDirectional.only(start: indent, top: 2, bottom: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: BookListItem.activeOf(context)
                        ? theme.colorScheme.primary
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: ShioriSpace.medium),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        );
      },
    ),
  );
}
