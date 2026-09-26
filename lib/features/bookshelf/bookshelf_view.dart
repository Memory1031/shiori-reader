import 'package:flutter/material.dart';
import '../../shared/widgets/shiori_sheet.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_cover.dart';
import '../../shared/widgets/book_list_tile.dart';
import '../../shared/widgets/desktop_content_frame.dart';
import '../../shared/widgets/shiori_menu.dart';
import '../../shared/widgets/state_views.dart';
import 'desktop_shelf.dart';
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
    this.layout,
    this.showTitle = true,
    this.desktop = false,
  });
  final LibraryController controller;

  /// The pointer-first shelf: a fixed toolbar over centered content,
  /// a density-driven grid, column rows without swipe actions, and book
  /// menus on right click, the Menu key and Shift+F10. [showTitle] does not
  /// apply; the toolbar always titles the shelf.
  final bool desktop;

  /// Grid (true) or list, owned by a host that outlives this view so the
  /// choice survives leaving the page; the view keeps its own otherwise.
  final ValueNotifier<bool>? layout;

  /// Hosts that title the page themselves, with a [ShelfLayoutButton] in
  /// their toolbar, hide the shelf's own title row.
  final bool showTitle;

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
  ValueNotifier<bool>? _ownLayout;
  ValueNotifier<bool> get _layout =>
      widget.layout ?? (_ownLayout ??= ValueNotifier(true));
  bool get _grid => _layout.value;
  NovelKey? _revealed;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _layout.addListener(_layoutChanged);
  }

  @override
  void didUpdateWidget(BookshelfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.layout ?? _ownLayout;
    if (old != _layout) {
      old?.removeListener(_layoutChanged);
      _layout.addListener(_layoutChanged);
    }
  }

  @override
  void dispose() {
    _layout.removeListener(_layoutChanged);
    _ownLayout?.dispose();
    super.dispose();
  }

  void _layoutChanged() => setState(() => _revealed = null);

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

  /// A book menu anchored at [anchor] in global coordinates. Resolves true
  /// when it closed without a choice, so the caller can take focus back.
  Future<bool> _menu(NovelSummary book, Rect anchor) async {
    final strings = AppLocalizations.of(context);
    final controller = widget.controller;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()!
            as RenderBox;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final at = overlay.globalToLocal(
      rtl ? anchor.bottomRight : anchor.bottomLeft,
    );
    final started = controller.progressFor(book.key) != null;
    ShioriMenuItem<_BookAction> entry(
      _BookAction value,
      IconData icon,
      String label, {
      bool enabled = true,
    }) => ShioriMenuItem(
      value: value,
      icon: icon,
      label: label,
      enabled: enabled,
    );
    // On the root navigator the shell sees its route covered, so Escape
    // closes the menu without leaving the workspace page.
    final action = await showMenu<_BookAction>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        at & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        entry(
          _BookAction.open,
          started ? Icons.play_arrow_rounded : Icons.menu_book_outlined,
          started ? strings.detailContinue : strings.detailStart,
        ),
        entry(
          _BookAction.details,
          Icons.info_outline,
          strings.novelDetailsTitle,
          enabled: widget.onDetails != null,
        ),
        const PopupMenuDivider(),
        entry(
          _BookAction.remove,
          Icons.bookmark_remove_outlined,
          strings.detailRemoveShelf,
          enabled: !controller.writing,
        ),
      ],
    );
    if (!mounted) return false;
    switch (action) {
      case null:
        return true;
      case _BookAction.open:
        widget.onOpen(book.key);
      case _BookAction.details:
        widget.onDetails?.call(book.key);
      case _BookAction.remove:
        removeShelfBook(context, controller, book);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.desktop) return _desktop(context);
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
            if (widget.showTitle)
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
                      ShelfLayoutButton(layout: _layout),
                    ],
                  ),
                ),
              ),
            // An invitation for an empty shelf, not a caption for a full one.
            if (controller.shelfReady && books.isEmpty)
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
              SliverFillRemaining(hasScrollBody: false, child: _empty(strings))
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

  Widget _empty(AppLocalizations strings) => Column(
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
  );

  Widget _desktop(BuildContext context) {
    final controller = widget.controller;
    final strings = AppLocalizations.of(context);
    final books = controller.sorted;
    final scaler = MediaQuery.textScalerOf(context);
    final gutter = desktopShelfGutter(DesktopLayoutScope.widthOf(context));
    final maxFrame = _grid ? ShioriLayout.shelfGrid : ShioriLayout.shelfList;
    // Two title lines at the card style and the real text scale.
    final titles = TextPainter(
      text: TextSpan(
        text: '书 Ag\n书 Ag',
        style: _ShelfGridCard.titleStyle(Theme.of(context)),
      ),
      textScaler: scaler,
      textDirection: Directionality.of(context),
      maxLines: 2,
    )..layout();
    final titleHeight = titles.height;
    titles.dispose();

    return LayoutBuilder(
      builder: (context, bounds) {
        final geometry = desktopContentGeometry(
          availableWidth: bounds.maxWidth,
          gutter: gutter,
          maxWidth: maxFrame,
        );
        final frame = geometry.contentWidth;
        // Keep the viewport across the Workspace for edge scrollbar and wheel
        // access. Only its content is centered; row tints bleed into the gutter.
        Widget framed(Widget sliver, {double bleed = 0}) => SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: (geometry.inset - bleed).clamp(0.0, double.infinity),
          ),
          sliver: sliver,
        );
        final grid = desktopShelfGrid(frame, scaler);

        Widget item(int index) {
          final book = books[index].snapshot;
          final format = controller.localFormats[book.key];
          final cover = BookCover(book: book, images: widget.images);
          final sourceLabel = _sourceBadgeLabel(book.key, format);
          if (_grid) {
            return _ShelfGridCard(
              key: ValueKey(book.key),
              onTap: () => widget.onOpen(book.key),
              onMenu: (anchor) => _menu(book, anchor),
              cover: cover,
              title: book.title,
              sourceLabel: sourceLabel,
            );
          }
          final progress = controller.progressFor(book.key)?.bookProgress;
          return DesktopBookRow(
            key: ValueKey(book.key),
            moreKey: ValueKey(('shelf-more', book.key)),
            cover: cover,
            title: book.title,
            subtitle: book.authors.isEmpty ? null : book.authors.join(', '),
            sourceLabel: sourceLabel,
            progressLabel: bookProgressLabel(
              strings,
              progress,
              descriptive: true,
            ),
            progress: progress?.fraction,
            onTap: () => widget.onOpen(book.key),
            onMenu: (anchor) => _menu(book, anchor),
          );
        }

        return Column(
          children: [
            DesktopContentFrame(
              maxWidth: maxFrame,
              child: DesktopShelfToolbar(
                layout: _layout,
                count: controller.shelfReady && books.isNotEmpty
                    ? books.length
                    : null,
                onImport: widget.onImport,
              ),
            ),
            Expanded(
              child: CustomScrollView(
                key: PageStorageKey(_grid ? 'shelf-grid' : 'shelf-list'),
                slivers: [
                  if (widget.header case final header?)
                    framed(
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: rowGap),
                        sliver: SliverToBoxAdapter(child: header),
                      ),
                    ),
                  if (controller.shelfFailure != null)
                    framed(
                      SliverToBoxAdapter(
                        child: FailureView(failure: controller.shelfFailure!),
                      ),
                    ),
                  if (controller.writeFailure != null)
                    framed(
                      SliverToBoxAdapter(
                        child: FailureView(failure: controller.writeFailure!),
                      ),
                    ),
                  if (!controller.shelfReady)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: LoadingView(),
                    )
                  else if (books.isEmpty)
                    framed(
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _empty(strings),
                      ),
                    )
                  else if (_grid)
                    framed(
                      SliverPadding(
                        padding: const EdgeInsets.only(
                          top: ShioriSpace.tight,
                          bottom: ShioriSpace.section,
                        ),
                        // Capped cards leave the spare width at the end.
                        sliver: SliverConstrainedCrossAxis(
                          maxExtent: grid.extent,
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: grid.columns,
                                  crossAxisSpacing: gap,
                                  mainAxisSpacing: rowGap,
                                  // Cover, the title gap, two title lines
                                  // and rounding slack.
                                  mainAxisExtent:
                                      grid.card / ShioriShape.coverRatio +
                                      _ShelfGridCard.titleGap +
                                      titleHeight +
                                      2,
                                ),
                            itemCount: books.length,
                            itemBuilder: (_, i) => item(i),
                          ),
                        ),
                      ),
                    )
                  else
                    framed(
                      SliverPadding(
                        padding: const EdgeInsets.only(
                          bottom: ShioriSpace.section,
                        ),
                        sliver: SliverList.builder(
                          itemCount: books.length,
                          itemBuilder: (_, i) => item(i),
                        ),
                      ),
                      bleed: BookListItem.inset,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _BookAction { open, details, remove }

/// Switches a shelf between grid and list.
class ShelfLayoutButton extends StatelessWidget {
  const ShelfLayoutButton({super.key, required this.layout});
  final ValueNotifier<bool> layout;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: layout,
      builder: (context, grid, _) => IconButton(
        tooltip: grid ? strings.shelfList : strings.shelfGrid,
        icon: Icon(grid ? Icons.grid_view_rounded : Icons.view_list_rounded),
        onPressed: () => layout.value = !grid,
      ),
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
    this.onLongPress,
    this.onMenu,
    this.sourceLabel,
  });

  final Widget cover;
  final String title;
  final String? sourceLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// A book menu at a global anchor for pointer-first shelves, opened by
  /// right click, the Menu key, Shift+F10, a long press or the more button
  /// shown on hover and focus. Resolves true when it closed without a
  /// choice; focus then returns to the card if the keyboard closed it.
  final Future<bool> Function(Rect anchor)? onMenu;

  static const titleGap = 10.0;
  static TextStyle titleStyle(ThemeData theme) =>
      (theme.textTheme.titleSmall ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w500,
      );

  @override
  State<_ShelfGridCard> createState() => _ShelfGridCardState();
}

class _ShelfGridCardState extends State<_ShelfGridCard> {
  final _focus = FocusNode(debugLabel: 'shelf-card');
  final _more = GlobalKey();
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  bool _menuOpen = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open(Rect anchor, {bool keyboard = false}) async {
    setState(() => _menuOpen = true);
    final restore = await menuClosedFromKeyboard(
      widget.onMenu!(anchor),
      keyboard: keyboard,
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (restore) _focus.requestFocus();
  }

  void _openAtMore({bool keyboard = false}) {
    final box = _more.currentContext!.findRenderObject()! as RenderBox;
    _open(box.localToGlobal(Offset.zero) & box.size, keyboard: keyboard);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = _hovered || _pressed || _focused;
    final duration = ShioriMotion.of(context, ShioriMotion.feedback);
    final radius = BorderRadius.circular(ShioriShape.cover);
    final menu = widget.onMenu != null;

    Widget card = InkWell(
      focusNode: _focus,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress ?? (menu ? _openAtMore : null),
      onSecondaryTapUp: menu
          ? (details) => _open(details.globalPosition & Size.zero)
          : null,
      onHover: menu ? null : (value) => setState(() => _hovered = value),
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
          const SizedBox(height: _ShelfGridCard.titleGap),
          AnimatedDefaultTextStyle(
            duration: duration,
            style: _ShelfGridCard.titleStyle(
              theme,
            ).copyWith(color: active ? colors.primary : colors.onSurface),
            child: Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (!menu) return card;

    // Shown on hover or focus without its own Tab stop; the Menu key and
    // Shift+F10 reach the same menu from the focused card.
    final showMore = _hovered || _focused || _menuOpen;
    card = Stack(
      children: [
        ShelfMenuShortcuts(
          onMenu: () => _openAtMore(keyboard: true),
          child: card,
        ),
        PositionedDirectional(
          top: 6,
          end: 6,
          child: IgnorePointer(
            ignoring: !showMore || _menuOpen,
            child: AnimatedOpacity(
              opacity: showMore ? 1 : 0,
              duration: duration,
              child: ExcludeFocus(
                child: Tooltip(
                  message: AppLocalizations.of(context).moreActions,
                  child: Material(
                    color: Colors.black.withValues(alpha: .42),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: _more,
                      onTap: _openAtMore,
                      child: SizedBox.square(
                        dimension: 28,
                        child: Icon(
                          Icons.more_horiz,
                          size: 18,
                          // Light ink on the scrim over any cover artwork.
                          color: Colors.white.withValues(alpha: .90),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    // Hover spans the card and its more button, so reaching for the
    // button keeps it visible.
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: card,
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
