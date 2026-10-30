import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/catalog_browsing.dart';
import '../local_books/local_catalog.dart';
import '../novel_detail/catalog_controller.dart';
import '../novel_detail/catalog_view.dart';
import 'article_contents.dart';
import 'reader_panel.dart';
import 'reader_contents_session.dart';

/// One navigation level of the reader contents, e.g. headings inside the
/// current article or the book's volume catalog. [build] receives `done`,
/// which closes the host and hands it the selection to apply.
class ReaderContentsLayer {
  const ReaderContentsLayer({
    required this.label,
    required this.build,
    this.action,
    this.kind = ReaderContentsKind.book,
  });
  final String label;
  final ReaderContentsKind kind;
  final Widget Function(BuildContext context, ReaderPanelDone done) build;

  /// Optional header control for this layer, such as refreshing a catalog.
  final Widget? action;
}

/// Placement-agnostic contents surface: a sheet on phones, and suitable for a
/// persistent side panel on wide windows.
class ReaderContentsPanel extends StatefulWidget {
  const ReaderContentsPanel({
    super.key,
    required this.layers,
    required this.onDone,
    this.initialLayer,
    this.session,
    this.closeButton = false,
  });
  final List<ReaderContentsLayer> layers;
  final ReaderPanelDone onDone;
  final int? initialLayer;
  final ReaderContentsSession? session;

  /// Ends the header with a close control calling [onDone], for a host
  /// without a drag handle. The header then keeps its own top spacing.
  final bool closeButton;
  @override
  State<ReaderContentsPanel> createState() => _ReaderContentsPanelState();
}

class _ReaderContentsPanelState extends State<ReaderContentsPanel> {
  late int _layer =
      (widget.initialLayer ??
              widget.layers.indexWhere(
                (l) => l.kind == widget.session?.selected,
              ))
          .clamp(0, widget.layers.length - 1);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final layer = widget.layers[_layer];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            ShioriSpace.page,
            widget.closeButton ? ShioriSpace.small : 0,
            ShioriSpace.small,
            ShioriSpace.small,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.layers.length == 1 ? layer.label : l.catalogTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?layer.action,
              if (widget.closeButton)
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => widget.onDone(),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        if (widget.layers.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShioriSpace.page,
              0,
              ShioriSpace.page,
              ShioriSpace.medium,
            ),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final (index, item) in widget.layers.indexed)
                  ButtonSegment(
                    value: index,
                    label: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selected: {_layer},
              onSelectionChanged: (value) {
                if (ModalRoute.of(context)?.isCurrent == false) return;
                setState(() => _layer = value.single);
                if (widget.session?.active == true) {
                  widget.session!.selected = widget.layers[_layer].kind;
                }
              },
            ),
          ),
        // Row fills and splashes paint on the nearest Material; give the list
        // its own clipped one so selected rows never show through the header.
        Expanded(
          child: ClipRect(
            child: Material(
              type: MaterialType.transparency,
              child: KeyedSubtree(
                key: ValueKey(_layer),
                child: layer.build(context, widget.onDone),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showReaderContents(
  BuildContext context, {
  required List<ReaderContentsLayer> layers,
  int? initialLayer,
  ReaderContentsSession? session,
}) => showReaderPanel<void>(
  context,
  size: ShioriSheetSize.tall,
  placement: ReaderPanelPlacement.start,
  builder: (sheet) => ReaderContentsPanel(
    closeButton: !ShioriPanelScope.isSheet(sheet),
    layers: layers,
    initialLayer: initialLayer,
    session: session,
    onDone: readerPanelDone(sheet),
  ),
);

/// Headings recognised inside the current article.
ReaderContentsLayer articleContentsLayer(
  BuildContext context,
  ChapterContent content, {
  required ValueChanged<ReaderPosition> onSelect,
  CatalogBrowsingState? browsing,
  List<({String title, ReaderPosition position})>? entries,
  ValueListenable<ReaderPosition?>? current,
}) {
  final l = AppLocalizations.of(context);
  final headings = entries ?? articleContents(content);
  return ReaderContentsLayer(
    kind: ReaderContentsKind.article,
    label: l.articleContents,
    build: (context, done) => headings.isEmpty
        ? EmptyView(message: l.articleContentsEmpty)
        : _ArticleContentsList(
            content: content,
            browsing: browsing,
            entries: headings,
            current: current,
            onSelect: (position) => done(() => onSelect(position)),
          ),
  );
}

class _ArticleContentsList extends StatefulWidget {
  const _ArticleContentsList({
    required this.content,
    required this.entries,
    required this.onSelect,
    this.browsing,
    this.current,
  });
  final ChapterContent content;
  final List<({String title, ReaderPosition position})> entries;
  final ValueChanged<ReaderPosition> onSelect;
  final CatalogBrowsingState? browsing;
  final ValueListenable<ReaderPosition?>? current;
  @override
  State<_ArticleContentsList> createState() => _ArticleContentsListState();
}

class _ArticleContentsListState extends State<_ArticleContentsList> {
  late int? _attachment = widget.browsing == null ? null : -1;
  ScrollController? _scroll;
  var _followingRows = GlobalKey(), _precedingRows = GlobalKey();
  int _center = 0;
  bool _endAnchor = false;
  bool _rememberPending = false;
  bool _located = false, _positioning = false;
  @override
  void didUpdateWidget(_ArticleContentsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.browsing != widget.browsing ||
        oldWidget.content.key != widget.content.key ||
        oldWidget.content.contentRevision != widget.content.contentRevision) {
      if (oldWidget.browsing != widget.browsing) {
        _attachment = widget.browsing == null ? null : -1;
      }
      _scroll?.dispose();
      _scroll = null;
      _located = false;
    }
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.current ?? const AlwaysStoppedAnimation(null),
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        final state = widget.browsing;
        final route = ModalRoute.of(context);
        final foreground = route?.isCurrent != false;
        final selected = currentArticleSection(
          widget.content,
          widget.entries,
          widget.current?.value,
        );
        if (foreground && state != null && _attachment! < 0) {
          _attachment = state.attach();
        }
        final changed =
            state?.configure(_attachment!, (
              widget.content.key,
              widget.content.contentRevision,
            ), catalogBrowsingLayout(context, bounds.biggest)) ==
            true;
        if (changed) _located = false;
        if (changed ||
            _scroll == null ||
            (!_located && selected != null && foreground)) {
          _followingRows = GlobalKey();
          _precedingRows = GlobalKey();
          _scroll?.dispose();
          final restored = state?.owns(_attachment!) == true
              ? state!.position
              : null;
          _center = restored?.center ?? (foreground ? selected : null) ?? 0;
          _endAnchor = _center > 0;
          _located =
              restored != null ||
              foreground &&
                  widget.current?.value?.contentRevision ==
                      widget.content.contentRevision;
          _positioning = true;
          final scroll = _scroll = ScrollController(
            initialScrollOffset:
                restored?.offset ?? (_endAnchor ? bounds.maxHeight * 2 / 3 : 0),
            keepScrollOffset: state == null,
          );
          final version = state?.revision;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !identical(_scroll, scroll)) return;
            // Stop initial edge correction before accepting manual browsing.
            if (scroll.hasClients) {
              final p = scroll.position;
              if (p.pixels < p.minScrollExtent ||
                  p.pixels > p.maxScrollExtent) {
                scroll.jumpTo(
                  p.pixels.clamp(p.minScrollExtent, p.maxScrollExtent),
                );
              }
            }
            _positioning = false;
          });
          scroll.addListener(() {
            if (_positioning) return;
            _located = true;
            if (state == null || _rememberPending) return;
            _rememberPending = true;
            final attachment = _attachment!;
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
                state.remember(attachment, version!, row.center, row.offset);
              }
            });
          });
        }
        Widget row(BuildContext context, int i) => ListTile(
          key: ValueKey(widget.entries[i].position.blockKey),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShioriShape.control),
          ),
          selected: i == selected,
          minLeadingWidth: ShioriSpace.item,
          horizontalTitleGap: ShioriSpace.medium,
          leading: SizedBox(
            width: ShioriSpace.item,
            child: i == selected
                ? const Icon(Icons.bookmark, size: ShioriSpace.item)
                : null,
          ),
          title: Text(widget.entries[i].title),
          onTap: () {
            if (mounted && route?.isCurrent != false) {
              widget.onSelect(widget.entries[i].position);
            }
          },
        );
        if (state == null && widget.current == null) {
          return ListView.builder(
            controller: _scroll,
            itemCount: widget.entries.length,
            itemBuilder: row,
          );
        }
        final center = _center;
        return CustomScrollView(
          key: ValueKey((state, state?.revision, _scroll)),
          controller: _scroll,
          center: _followingRows,
          anchor: _endAnchor ? 1 : 0,
          semanticChildCount: widget.entries.length,
          slivers: [
            if (center > 0)
              SliverList(
                key: _precedingRows,
                delegate: SliverChildBuilderDelegate(
                  (context, index) => row(context, center - index - 1),
                  childCount: center,
                  semanticIndexCallback: (_, index) => center - index - 1,
                ),
              ),
            SliverList(
              key: _followingRows,
              delegate: SliverChildBuilderDelegate(
                (context, index) => row(context, center + index),
                childCount: widget.entries.length - center,
                semanticIndexOffset: center,
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// The source's volume catalog, read from the reader's own catalog session.
///
/// Loading policy stays with the host: [onRetry] and [onRefresh] decide the
/// read mode (an offline reader must stay cache-only), and a null
/// [onRefresh] hides the refresh control. A failed refresh keeps the loaded
/// catalog usable and shows its reason above it.
///
/// [changes] must notify whenever [catalog] does. It is owned by the host
/// and outlives it safely: a sheet can still be listening while the reader
/// that owns [catalog] is torn down, and a disposed controller may not be
/// unsubscribed from.
ReaderContentsLayer volumeContentsLayer(
  BuildContext context, {
  required CatalogController catalog,
  required Listenable changes,
  required ChapterKey current,
  required ValueChanged<ChapterKey> onSelect,
  required VoidCallback onRetry,
  VoidCallback? onRefresh,
  CatalogBrowsingState? browsing,
}) {
  final l = AppLocalizations.of(context);
  return ReaderContentsLayer(
    label: l.volumesTitle,
    action: onRefresh == null
        ? null
        : ListenableBuilder(
            listenable: changes,
            builder: (context, _) => IconButton(
              onPressed: catalog.canLoad ? onRefresh : null,
              tooltip: l.detailRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
    build: (context, done) => ListenableBuilder(
      listenable: changes,
      builder: (context, _) {
        final loaded = catalog.loaded;
        final failure = catalog.failure;
        if (loaded == null) {
          if (catalog.loading) return const LoadingView();
          if (failure != null) {
            return FailureView(
              failure: failure,
              onRetry: onRetry,
              retryAvailable: catalog.canLoad,
            );
          }
          return EmptyView(message: l.catalogEmpty);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (catalog.loading) const LinearProgressIndicator(),
            if (failure != null && !catalog.loading)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .3,
                ),
                child: FailureView(
                  key: const ValueKey('catalog-refresh-failure'),
                  failure: failure,
                  onRetry: onRetry,
                  retryAvailable: catalog.canLoad,
                ),
              ),
            if (loaded.isStale)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ShioriSpace.page,
                ),
                child: Text(
                  l.catalogStale,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ShioriSpace.medium,
                ),
                child: CatalogView(
                  catalog: loaded.value,
                  current: current,
                  browsing: browsing,
                  onSelect: (key) => done(() => onSelect(key)),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Local EPUB / TXT navigation already loaded by the reader.
ReaderContentsLayer localContentsLayer(
  BuildContext context, {
  required ValueListenable<Result<List<LocalNavigationEntry>>?> navigation,
  required List<ChapterKey> Function() readingOrder,
  required Listenable readingOrderChanges,
  required ChapterKey current,
  LocalNavigationEntry? selectedEntry,
  required VoidCallback onRetry,
  required ValueChanged<LocalNavigationEntry> onSelect,
  CatalogBrowsingState? browsing,
}) => ReaderContentsLayer(
  label: AppLocalizations.of(context).localBookContents,
  build: (context, done) => AnimatedBuilder(
    animation: Listenable.merge([navigation, readingOrderChanges]),
    builder: (context, _) => switch (navigation.value) {
      null => const LoadingView(),
      Failure(:final failure) => FailureView(
        failure: failure,
        onRetry: onRetry,
      ),
      Success(:final value) => LocalNavigationView(
        entries: value,
        current: current,
        selectedEntry: selectedEntry,
        readingOrder: readingOrder(),
        browsing: browsing,
        onSelect: (entry) => done(() => onSelect(entry)),
      ),
    },
  ),
);
