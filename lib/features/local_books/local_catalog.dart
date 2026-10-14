import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/local_navigation_title.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/catalog_browsing.dart';

Future<LocalNavigationEntry?> openLocalCatalog(
  BuildContext context, {
  required NovelKey novel,
  required LocalNavigationRepository repository,
  ChapterKey? current,
}) {
  Widget builder(BuildContext context) => LocalCatalogScreen(
    novel: novel,
    repository: repository,
    current: current,
  );
  const settings = RouteSettings(name: '/local-catalog');
  return Navigator.of(context).push<LocalNavigationEntry>(
    platformPageRoute(context, builder: builder, settings: settings),
  );
}

class LocalCatalogScreen extends StatefulWidget {
  const LocalCatalogScreen({
    super.key,
    required this.novel,
    required this.repository,
    this.current,
  });
  final NovelKey novel;
  final LocalNavigationRepository repository;
  final ChapterKey? current;
  @override
  State<LocalCatalogScreen> createState() => _LocalCatalogScreenState();
}

class _LocalCatalogScreenState extends State<LocalCatalogScreen> {
  final _request = CancellationSource();
  late Future<Result<List<LocalNavigationEntry>>> _result = _load();
  Future<Result<List<LocalNavigationEntry>>> _load() => widget.repository
      .loadNavigation(widget.novel, cancellation: _request.token);
  @override
  void dispose() {
    _request.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).localBookContents)),
    body: SafeArea(
      child: FutureBuilder(
        future: _result,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const LoadingView();
          final result = snapshot.data!;
          if (result case Failure(:final failure)) {
            return FailureView(
              failure: failure,
              onRetry: () => setState(() => _result = _load()),
            );
          }
          return LocalNavigationView(
            entries: (result as Success<List<LocalNavigationEntry>>).value,
            current: widget.current,
            onSelect: (target) => Navigator.pop(context, target),
          );
        },
      ),
    ),
  );
}

class LocalNavigationView extends StatefulWidget {
  const LocalNavigationView({
    super.key,
    required this.entries,
    required this.onSelect,
    this.current,
    this.readingOrder = const [],
    this.selectedEntry,
    this.browsing,
  });
  final List<LocalNavigationEntry> entries;
  final ValueChanged<LocalNavigationEntry> onSelect;
  final ChapterKey? current;
  final List<ChapterKey> readingOrder;
  final LocalNavigationEntry? selectedEntry;
  final CatalogBrowsingState? browsing;
  @override
  State<LocalNavigationView> createState() => _LocalNavigationViewState();
}

class _LocalNavigationViewState extends State<LocalNavigationView> {
  final _currentRow = GlobalKey();
  var _followingRows = GlobalKey();
  var _precedingRows = GlobalKey();
  (ChapterKey?, int, Size, TextScaler, Object?, int?)? _positionTarget;
  int _anchor = 0;
  bool _positioning = false;
  late int? _attachment = widget.browsing == null ? null : -1;
  ScrollController? _scroll;
  bool _rememberPending = false;
  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LocalNavigationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.browsing != widget.browsing) {
      _attachment = widget.browsing == null ? null : -1;
      _positionTarget = null;
    }
    if (!identical(oldWidget.entries, widget.entries)) _positionTarget = null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(LocalNavigationEntry, int)>[];
    void flatten(List<LocalNavigationEntry> list, int depth) {
      for (final item in list) {
        rows.add((item, depth));
        flatten(item.children, depth + 1);
      }
    }

    flatten(widget.entries, 0);
    if (rows.isEmpty) {
      return EmptyView(message: AppLocalizations.of(context).catalogEmpty);
    }
    final targets = {for (final (entry, _) in rows) entry.chapterKey};
    final current = widget.current;
    ChapterKey? selectedChapter = current;
    if (current != null && !targets.contains(current)) {
      selectedChapter = null;
      // A title page's TOC target also owns the following body files, up to
      // the next target in the actual spine, independently of TOC row order.
      for (var i = widget.readingOrder.indexOf(current) - 1; i >= 0; i--) {
        if (targets.contains(widget.readingOrder[i])) {
          selectedChapter = widget.readingOrder[i];
          break;
        }
      }
    }
    final match = rows.indexWhere(
      (row) => widget.selectedEntry != null
          ? identical(row.$1, widget.selectedEntry)
          : row.$1.chapterKey == selectedChapter,
    );
    Widget buildRow(BuildContext context, int index) {
      final (entry, depth) = rows[index];
      final tile = ListTile(
        key: ValueKey(('local-toc', index)),
        contentPadding: EdgeInsetsDirectional.only(
          start: 16 + depth.clamp(0, 4) * 16,
          end: 16,
        ),
        selected: widget.selectedEntry != null
            ? index == match
            : entry.chapterKey == selectedChapter,
        leading: Icon(
          (widget.selectedEntry != null
                  ? index == match
                  : entry.chapterKey == selectedChapter)
              ? Icons.bookmark
              : entry.children.isEmpty
              ? Icons.article_outlined
              : Icons.folder_outlined,
        ),
        title: Text(
          localNavigationTitle(entry, AppLocalizations.of(context)),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => widget.onSelect(entry),
      );
      return index == match
          ? KeyedSubtree(key: _currentRow, child: tile)
          : tile;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final browsing = widget.browsing;
        if (ModalRoute.of(context)?.isCurrent != false &&
            browsing != null &&
            _attachment! < 0) {
          _attachment = browsing.attach();
        }
        final changed =
            browsing?.configure(_attachment!, (
              widget.entries,
              widget.readingOrder,
            ), catalogBrowsingLayout(context, constraints.biggest)) ==
            true;
        if (changed) _positionTarget = null;
        final target = (
          current,
          match,
          constraints.biggest,
          MediaQuery.textScalerOf(context),
          browsing,
          browsing?.revision,
        );
        if (_positionTarget != target) {
          _positionTarget = target;
          _followingRows = GlobalKey();
          _precedingRows = GlobalKey();
          final restored = browsing?.owns(_attachment!) == true
              ? browsing!.position
              : null;
          _anchor = restored?.center ?? 0;
          _positioning = restored == null && match > 0;
          _scroll?.dispose();
          final scroll = _scroll = ScrollController(
            initialScrollOffset: restored?.offset ?? 0,
            keepScrollOffset: browsing == null,
          );
          final version = browsing?.revision;
          scroll.addListener(() {
            if (_positioning || browsing == null || _rememberPending) return;
            _rememberPending = true;
            final attachment = _attachment!;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _rememberPending = false;
              if (!mounted || _positioning || !scroll.hasClients) return;
              final row = captureCatalogBrowsing(
                scroll.position,
                center: _anchor,
                before: _precedingRows.currentContext?.findRenderObject(),
                after: _followingRows.currentContext?.findRenderObject(),
                endAnchor: true,
              );
              if (row != null) {
                browsing.remember(attachment, version!, row.center, row.offset);
              }
            });
          });
          if (_positioning) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _positionTarget != target) return;
              final rowContext = _currentRow.currentContext;
              if (rowContext != null) {
                final row = rowContext.findRenderObject()!;
                final viewport = RenderAbstractViewport.of(row);
                final position = Scrollable.of(rowContext).position;
                final start = viewport.getOffsetToReveal(row, 0).offset;
                final end = viewport.getOffsetToReveal(row, 1).offset;
                // Leave fully visible rows alone; otherwise show surrounding
                // chapters, clamped by the list's natural start/end bounds.
                if (position.pixels > start || position.pixels < end) {
                  position.ensureVisible(row, alignment: 1 / 3);
                }
                _positioning = false;
              } else {
                // The target is beyond the lazily built first screen. Anchor
                // directly there without laying out thousands of preceding rows.
                setState(() {
                  _anchor = match;
                  _followingRows = GlobalKey();
                  _precedingRows = GlobalKey();
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _positionTarget != target) return;
                  final row = _currentRow.currentContext?.findRenderObject();
                  final following = _followingRows.currentContext
                      ?.findRenderObject();
                  if (row is! RenderBox || following is! RenderSliver) return;
                  final height = constraints.maxHeight;
                  if (height <= 0) return;
                  final tail = following.geometry!.scrollExtent;
                  // Near the end, move the target down enough to fill the
                  // viewport. A centered sliver must not create trailing space.
                  final top = math.max(
                    math.max(0.0, (height - row.size.height) / 3),
                    height - tail,
                  );
                  Scrollable.of(
                    _currentRow.currentContext!,
                  ).position.jumpTo(height - top);
                  _positioning = false;
                });
              }
            });
          }
        }
        final anchor = _anchor;
        return CustomScrollView(
          controller: _scroll,
          key: ValueKey((target, anchor, browsing?.revision)),
          center: _followingRows,
          // Keep a positive end offset even when opening near the last row:
          // Flutter's scrollbar only registers drag gestures when max > 0.
          // The post-frame jump positions the row without moving this origin.
          anchor: anchor > 0 ? 1 : 0,
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
            SliverList(
              key: _followingRows,
              delegate: SliverChildBuilderDelegate(
                (context, index) => buildRow(context, anchor + index),
                childCount: rows.length - anchor,
                semanticIndexOffset: anchor,
              ),
            ),
          ],
        );
      },
    );
  }
}
