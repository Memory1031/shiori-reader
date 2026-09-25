import 'package:flutter/material.dart';
import '../../shared/widgets/shiori_sheet.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_cover.dart';
import '../../shared/widgets/book_list_tile.dart';
import '../../shared/widgets/state_views.dart';
import 'library_controller.dart';
import '../reader/book_progress_label.dart';
import 'remove_shelf_book.dart';

class BookshelfView extends StatefulWidget {
  const BookshelfView({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onSearch,
    this.onDetails,
    this.onImport,
    this.images,
    this.header,
  });
  final LibraryController controller;

  /// Scrolls above the shelf title, e.g. the continue-reading card.
  final Widget? header;
  final ValueChanged<NovelKey> onOpen;
  final ValueChanged<NovelKey>? onDetails;
  final VoidCallback onSearch;
  final VoidCallback? onImport;
  final ImageRepository? images;
  @override
  State<BookshelfView> createState() => _BookshelfViewState();
}

class _BookshelfViewState extends State<BookshelfView> {
  bool _grid = true;
  NovelKey? _revealed;
  double _drag = 0;

  // Reveal or hide row actions once a swipe commits by distance or speed,
  // not on the first couple of pixels of any horizontal movement.
  // Actions sit at the trailing edge, so a swipe toward the leading edge
  // reveals them: leftwards in left-to-right layouts, rightwards otherwise.
  void _dragEnd(NovelKey key, DragEndDetails details) {
    final sign = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final velocity = (details.primaryVelocity ?? 0) * sign;
    _drag *= sign;
    final open = _revealed == key;
    if (!open && (_drag < -48 || velocity < -300)) {
      setState(() => _revealed = key);
    } else if (open && (_drag > 48 || velocity > 300)) {
      setState(() => _revealed = null);
    }
    _drag = 0;
  }

  Future<void> _actions(NovelSummary book) async {
    final l = AppLocalizations.of(context);
    await showShioriSheet<void>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(ShioriSpace.medium),
                child: Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l.novelDetailsTitle),
                onTap: widget.onDetails == null
                    ? null
                    : () {
                        Navigator.pop(sheet);
                        widget.onDetails!(book.key);
                      },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_remove_outlined),
                title: Text(l.detailRemoveShelf),
                onTap: widget.controller.writing
                    ? null
                    : () {
                        Navigator.pop(sheet);
                        removeShelfBook(context, widget.controller, book);
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = AppLocalizations.of(context);
    final books = controller.sorted;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, bounds) {
        final scale = MediaQuery.textScalerOf(context).scale(15) / 15;
        final titleStyle = theme.textTheme.titleSmall;
        final titleLine =
            MediaQuery.textScalerOf(context).scale(titleStyle?.fontSize ?? 15) *
            (titleStyle?.height ?? 1.5);
        final columns = (bounds.maxWidth / (110 * scale.clamp(1, 1.5)))
            .floor()
            .clamp(2, 6);
        Widget item(int index) {
          final book = books[index].snapshot;
          final format = controller.localFormats[book.key];
          final progressLabel = bookProgressLabel(
            strings,
            controller.progressFor(book.key)?.bookProgress,
            descriptive: true,
          );
          final cover = BookCover(book: book, images: widget.images);
          if (!_grid) {
            final open = _revealed == book.key;
            final sourceLabel = _sourceBadgeLabel(book.key, format);
            final metadata = [?sourceLabel, ?progressLabel].join(' · ');
            // The row's own inset keeps content on the page gutter.
            return Padding(
              key: ValueKey(book.key),
              padding: const EdgeInsets.symmetric(
                horizontal: ShioriSpace.page - BookListItem.inset,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(ShioriShape.control),
                child: Stack(
                  children: [
                    if (open)
                      Positioned.fill(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: 148,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed:
                                          !open || widget.onDetails == null
                                          ? null
                                          : () {
                                              setState(() => _revealed = null);
                                              widget.onDetails!(book.key);
                                            },
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.info_outline),
                                          Text(
                                            strings.shelfDetails,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: TextButton(
                                      onPressed: !open || controller.writing
                                          ? null
                                          : () {
                                              setState(() => _revealed = null);
                                              removeShelfBook(
                                                context,
                                                controller,
                                                book,
                                              );
                                            },
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.bookmark_remove_outlined,
                                          ),
                                          Text(
                                            strings.shelfRemove,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    GestureDetector(
                      onHorizontalDragStart: (_) => _drag = 0,
                      onHorizontalDragUpdate: (d) => _drag += d.delta.dx,
                      onHorizontalDragEnd: (d) => _dragEnd(book.key, d),
                      child: AnimatedContainer(
                        duration: ShioriMotion.of(
                          context,
                          ShioriMotion.feedback,
                        ),
                        transform: Matrix4.translationValues(
                          open
                              ? (Directionality.of(context) == TextDirection.rtl
                                    ? 148
                                    : -148)
                              : 0,
                          0,
                          0,
                        ),
                        child: BookListItem(
                          onLongPress: () => _actions(book),
                          onTap: () {
                            if (open) {
                              setState(() => _revealed = null);
                            } else {
                              widget.onOpen(book.key);
                            }
                          },
                          minHeight: open ? 120 * scale.clamp(1, 2) : 120,
                          child: BookListTile(
                            cover: cover,
                            title: book.title,
                            subtitle: book.authors.isEmpty
                                ? null
                                : book.authors.join(', '),
                            metadata: metadata,
                            trailing: IconButton(
                              key: ValueKey(('shelf-more', book.key)),
                              tooltip: strings.moreActions,
                              onPressed: () => _actions(book),
                              icon: const Icon(Icons.more_horiz, size: 20),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return _ShelfGridCard(
            key: ValueKey(book.key),
            onTap: () => widget.onOpen(book.key),
            onLongPress: () => _actions(book),
            cover: cover,
            title: book.title,
            sourceLabel: _sourceBadgeLabel(book.key, format),
          );
        }

        return CustomScrollView(
          key: PageStorageKey(_grid ? 'shelf-grid' : 'shelf-list'),
          slivers: [
            if (widget.header case final header?)
              SliverToBoxAdapter(child: header),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ShioriSpace.page,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.shelfTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: _grid ? strings.shelfList : strings.shelfGrid,
                      icon: Icon(
                        _grid
                            ? Icons.grid_view_rounded
                            : Icons.view_list_rounded,
                      ),
                      onPressed: () => setState(() {
                        _grid = !_grid;
                        _revealed = null;
                      }),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  strings.shelfTagline,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            if (controller.shelfFailure != null)
              SliverToBoxAdapter(
                child: FailureView(failure: controller.shelfFailure!),
              ),
            if (controller.writeFailure != null)
              SliverToBoxAdapter(
                child: FailureView(failure: controller.writeFailure!),
              ),
            if (!controller.shelfReady)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: LoadingView(),
              )
            else if (books.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    EmptyView(message: strings.shelfEmpty),
                    FilledButton.icon(
                      onPressed: widget.onSearch,
                      icon: const Icon(Icons.search),
                      label: Text(strings.searchTitle),
                    ),
                    if (widget.onImport != null) ...[
                      const SizedBox(height: ShioriSpace.small),
                      TextButton.icon(
                        onPressed: widget.onImport,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: Text(strings.importTitle),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              )
            else if (_grid)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 20,
                    // Cover, the 10dp gap and two title lines at the card style.
                    mainAxisExtent:
                        ((bounds.maxWidth - 32 - (columns - 1) * 16) /
                                columns) /
                            ShioriShape.coverRatio +
                        10 +
                        2 * titleLine +
                        2,
                  ),
                  itemCount: books.length,
                  itemBuilder: (_, i) => item(i),
                ),
              )
            else
              SliverList.builder(
                itemCount: books.length,
                itemBuilder: (_, i) => item(i),
              ),
          ],
        );
      },
    );
  }
}

String? _sourceBadgeLabel(NovelKey key, LocalBookFormat? format) {
  if (key.sourceId != LocalBookIdentity.sourceId) return null;
  return switch (format) {
    LocalBookFormat.epub => 'epub',
    LocalBookFormat.txt => 'txt',
    null => null,
  };
}

class _ShelfGridCard extends StatefulWidget {
  const _ShelfGridCard({
    super.key,
    required this.cover,
    required this.title,
    required this.onTap,
    required this.onLongPress,
    this.sourceLabel,
  });

  final Widget cover;
  final String title;
  final String? sourceLabel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_ShelfGridCard> createState() => _ShelfGridCardState();
}

class _ShelfGridCardState extends State<_ShelfGridCard> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = _hovered || _pressed || _focused;
    final duration = ShioriMotion.of(context, ShioriMotion.feedback);
    final radius = BorderRadius.circular(ShioriShape.cover);

    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onHover: (value) => setState(() => _hovered = value),
      onHighlightChanged: (value) => setState(() => _pressed = value),
      onFocusChange: (value) => setState(() => _focused = value),
      borderRadius: radius,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: active ? .18 : .12),
                    blurRadius: active && !_pressed ? 16 : 12,
                    offset: Offset(0, _pressed ? 2 : (active ? 7 : 5)),
                  ),
                ],
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: colors.primary.withValues(
                    alpha: _focused || _pressed ? .9 : (_hovered ? .55 : 0),
                  ),
                  width: 2,
                ),
              ),
              child: _ShelfCover(
                cover: widget.cover,
                sourceLabel: widget.sourceLabel,
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedDefaultTextStyle(
            duration: duration,
            style: (theme.textTheme.titleSmall ?? const TextStyle()).copyWith(
              fontWeight: FontWeight.w500,
              color: active ? colors.primary : colors.onSurface,
            ),
            child: Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfCover extends StatelessWidget {
  const _ShelfCover({required this.cover, this.sourceLabel});
  final Widget cover;
  final String? sourceLabel;
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        cover,
        if (sourceLabel != null)
          Positioned(
            left: 6,
            bottom: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .42),
                borderRadius: BorderRadius.circular(ShioriShape.tag),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ShioriSpace.tight,
                  vertical: 2,
                ),
                child: Text(
                  sourceLabel!,
                  // Light ink on the scrim over any cover artwork.
                  style: ShioriType.of(
                    context,
                  ).badge.copyWith(color: Colors.white.withValues(alpha: .90)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
