import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/catalog_browsing.dart';
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
    platformPageRoute(context, builder: builder, settings: settings),
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
    this.browsing,
  });
  final Catalog catalog;
  final CatalogBrowsingState? browsing;
  final ChapterKey? current;
  final ValueChanged<ChapterKey> onSelect;
  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  final _collapsed = <String>{};
  ChapterKey? _selected;
  late int? _attachment = widget.browsing == null ? null : -1;
  ScrollController? _scroll;
  int _center = 0;
  bool _endAnchor = false;
  Object? _origin;
  var _followingRows = GlobalKey(), _precedingRows = GlobalKey();
  bool _rememberPending = false;
  Object _identity(Object row) =>
      row is Volume ? row.groupId : (row as Chapter).key;

  void _remember(CatalogBrowsingState state, int version) {
    if (_rememberPending) return;
    _rememberPending = true;
    final attachment = _attachment!, scroll = _scroll!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rememberPending = false;
      if (!mounted || !scroll.hasClients) return;
      final row = captureCatalogBrowsing(
        scroll.position,
        center: _center,
        before: _precedingRows.currentContext?.findRenderObject(),
        after: _followingRows.currentContext?.findRenderObject(),
        endAnchor: _endAnchor,
        restoreEndAnchor: true,
      );
      if (row != null) {
        state.remember(attachment, version, row.center, row.offset);
      }
    });
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CatalogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.browsing != widget.browsing) {
      _attachment = widget.browsing == null ? null : -1;
      _scroll?.dispose();
      _scroll = null;
    }
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
  Widget build(BuildContext context) => LayoutBuilder(builder: _build);

  Widget _build(BuildContext context, BoxConstraints bounds) {
    final browsing = widget.browsing;
    if (ModalRoute.of(context)?.isCurrent != false &&
        browsing != null &&
        _attachment! < 0) {
      _attachment = browsing.attach();
    }
    final changed =
        browsing?.configure(_attachment!, (
          widget.catalog.revision,
          widget.current,
        ), catalogBrowsingLayout(context, bounds.biggest)) ==
        true;
    if (browsing?.owns(_attachment!) == true) {
      _collapsed
        ..clear()
        ..addAll(browsing!.collapsed);
    }
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
    Widget buildRow(BuildContext context, int index) {
      final row = rows[index];
      if (row is Volume) {
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(ShioriShape.cover),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: ShioriSpace.medium,
              ),
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
                if (browsing?.owns(_attachment!) == true) {
                  // Folded rows change the index space before the next layout.
                  browsing!.position = null;
                  browsing.collapsed
                    ..clear()
                    ..addAll(_collapsed);
                  final version = browsing.revision;
                  _remember(browsing, version);
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
    }

    // Open at the current chapter without measuring the unseen prefix; rows
    // before the centre sliver grow upwards and stay lazily built.
    final match = widget.current == null
        ? -1
        : rows.indexWhere((row) => row is Chapter && row.key == widget.current);
    var anchor = match < 0 ? 0 : match;
    var reset = changed || _scroll == null;
    if (!reset && browsing != null) {
      final old = rows.indexWhere((row) => _identity(row) == _origin);
      if (old < 0) {
        reset = true;
        if (browsing.owns(_attachment!)) browsing.position = null;
      } else {
        anchor = old;
      }
    }
    if (reset) {
      _followingRows = GlobalKey();
      _precedingRows = GlobalKey();
      final restored = browsing?.owns(_attachment!) == true
          ? browsing!.position
          : null;
      if (restored != null &&
          restored.center >= 0 &&
          restored.center < rows.length) {
        anchor = restored.center;
      }
      _origin = _identity(rows[anchor]);
      _endAnchor = restored != null && anchor > 0;
      _scroll?.dispose();
      final scroll = _scroll = ScrollController(
        initialScrollOffset: restored?.offset ?? 0,
        keepScrollOffset: browsing == null,
      );
      final version = browsing?.revision;
      scroll.addListener(() {
        if (browsing != null) _remember(browsing, version!);
      });
    }
    _center = anchor;
    return CustomScrollView(
      controller: _scroll,
      key: ValueKey((
        widget.catalog.novelKey,
        widget.current,
        browsing,
        browsing?.revision,
        browsing == null ? null : _origin,
      )),
      center: _followingRows,
      anchor: _endAnchor ? 1 : 0,
      semanticChildCount: rows.length,
      slivers: [
        if (anchor > 0)
          SliverList(
            key: _precedingRows,
            delegate: SliverChildBuilderDelegate(
              (context, index) => buildRow(context, anchor - index - 1),
              childCount: anchor,
              semanticIndexCallback: (_, index) => anchor - index - 1,
            ),
          ),
        SliverPadding(
          key: _followingRows,
          padding: const EdgeInsets.only(bottom: 4),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => buildRow(context, anchor + index),
              childCount: rows.length - anchor,
              semanticIndexOffset: anchor,
            ),
          ),
        ),
      ],
    );
  }
}
