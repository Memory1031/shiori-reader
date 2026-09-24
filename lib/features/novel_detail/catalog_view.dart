import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import 'catalog_controller.dart';

Future<ChapterKey?> openCatalog(
  BuildContext context, {
  required NovelKey novel,
  required NovelRepository repository,
  ChapterKey? current,
}) {
  Widget builder(BuildContext context) =>
      CatalogScreen(novel: novel, repository: repository, current: current);
  const settings = RouteSettings(name: '/catalog');
  return Navigator.of(context).push<ChapterKey>(
    Theme.of(context).platform == TargetPlatform.iOS
        ? CupertinoPageRoute(builder: builder, settings: settings)
        : MaterialPageRoute(builder: builder, settings: settings),
  );
}

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({
    super.key,
    required this.novel,
    required this.repository,
    this.current,
  });
  final NovelKey novel;
  final NovelRepository repository;
  final ChapterKey? current;
  @override
  Widget build(BuildContext context) => ControllerScope<CatalogController>(
    key: ValueKey((novel, repository)),
    create: () => CatalogController(repository: repository, novel: novel),
    builder: (context, controller) => AppScaffold(
      title: AppLocalizations.of(context).catalogTitle,
      actions: [
        IconButton(
          onPressed: controller.canLoad ? controller.refreshCatalog : null,
          tooltip: AppLocalizations.of(context).detailRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: controller.loaded == null
          ? controller.loading
                ? const LoadingView()
                : controller.failure != null
                ? FailureView(
                    failure: controller.failure!,
                    onRetry: controller.load,
                  )
                : TextButton(
                    onPressed: controller.load,
                    child: Text(AppLocalizations.of(context).retryAction),
                  )
          : Column(
              children: [
                if (controller.loading) const LinearProgressIndicator(),
                if (controller.loaded!.isStale)
                  Text(AppLocalizations.of(context).catalogStale),
                if (controller.failure != null)
                  Flexible(
                    child: FailureView(
                      failure: controller.failure!,
                      onRetry: controller.refreshCatalog,
                      retryAvailable: controller.canLoad,
                    ),
                  ),
                Expanded(
                  flex: 3,
                  child: CatalogView(
                    catalog: controller.loaded!.value,
                    current: current,
                    onSelect: (key) => Navigator.of(context).pop(key),
                  ),
                ),
              ],
            ),
    ),
  );
}

/// Only visible rows build widgets. Lightweight row identities preserve source order.
class CatalogView extends StatefulWidget {
  const CatalogView({
    super.key,
    required this.catalog,
    required this.onSelect,
    this.current,
  });
  final Catalog catalog;
  final ChapterKey? current;
  final ValueChanged<ChapterKey> onSelect;
  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  final _collapsed = <String>{};
  ChapterKey? _selected;
  @override
  void didUpdateWidget(CatalogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog.novelKey != widget.catalog.novelKey) {
      _collapsed.clear();
      _selected = null;
    }
    _collapsed.removeWhere(
      (id) => !widget.catalog.volumes.any((v) => v.groupId == id),
    );
    if (_selected != null &&
        !widget.catalog.flatChapters.any((c) => c.key == _selected)) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (widget.catalog.flatChapters.isEmpty) {
      return EmptyView(message: strings.catalogEmpty);
    }
    final rows = <Object>[];
    final ordinals = <ChapterKey, int>{};
    var ordinal = 0;
    for (final chapter in widget.catalog.flatChapters) {
      ordinals[chapter.key] = ++ordinal;
    }
    for (final volume in widget.catalog.volumes) {
      if (!volume.isSynthetic) rows.add(volume);
      if (volume.isSynthetic || !_collapsed.contains(volume.groupId)) {
        rows.addAll(volume.chapters);
      }
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row is Volume) {
          return Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(ShioriShape.cover),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                minTileHeight: 44,
                dense: true,
                leading: Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(ShioriShape.indicator),
                  ),
                ),
                minLeadingWidth: 3,
                horizontalTitleGap: 10,
                titleTextStyle: Theme.of(context).textTheme.titleSmall,
                key: ValueKey(('volume', row.groupId)),
                title: Text(row.title ?? strings.catalogUnnamedVolume),
                trailing: Icon(
                  _collapsed.contains(row.groupId)
                      ? Icons.expand_more
                      : Icons.expand_less,
                ),
                onTap: () => setState(() {
                  if (!_collapsed.add(row.groupId)) {
                    _collapsed.remove(row.groupId);
                  }
                }),
              ),
            ),
          );
        }
        final chapter = row as Chapter;
        final selected = chapter.key == (_selected ?? widget.current);
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 4),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(ShioriShape.control),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ShioriShape.control),
              ),
              key: ValueKey(chapter.key),
              selected: selected,
              minLeadingWidth: 28,
              horizontalTitleGap: 12,
              leading: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(ShioriShape.cover),
                ),
                child: selected
                    ? Icon(
                        Icons.bookmark,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : Text(
                        '${ordinals[chapter.key]}'.padLeft(2, '0'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
              title: Tooltip(
                message: chapter.title,
                child: Text(
                  chapter.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 16),
              onTap: () {
                setState(() => _selected = chapter.key);
                widget.onSelect(chapter.key);
              },
            ),
          ),
        );
      },
    );
  }
}
