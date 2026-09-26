import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_list_tile.dart';
import '../../shared/widgets/desktop_content_frame.dart';

/// Gutter, frame and columns for desktop details laid out in [available]
/// width, in a window [window] wide.
///
/// The frame is centered in the available width and capped at
/// [ShioriLayout.detail]. Two columns need [ShioriLayout.detailColumns]
/// scaled by the full text scale, so large text falls back to one column
/// instead of squeezing the side column.
({
  double gutter,
  double frame,
  double inset,
  bool columns,
  double side,
  double main,
})
desktopDetailLayout(double available, double window, TextScaler scaler) {
  final gutter = ShioriLayout.gutter(window);
  final geometry = desktopContentGeometry(
    availableWidth: available,
    gutter: gutter,
    maxWidth: ShioriLayout.detail,
  );
  final frame = geometry.contentWidth;
  final scale = math.max(1.0, scaler.scale(15) / 15);
  final side = frame >= DesktopDetail.wideSide
      ? ShioriLayout.detailSideWide
      : ShioriLayout.detailSide;
  return (
    gutter: gutter,
    frame: frame,
    inset: geometry.inset,
    columns: frame >= ShioriLayout.detailColumns * scale,
    side: side,
    main: frame - side - ShioriLayout.detailGap,
  );
}

/// Novel details on the desktop: a fixed title bar over one scrolling page,
/// both on the same centered content frame, with a full-width main viewport.
///
/// Wide frames put the cover and reading actions in a side column, fixed
/// beside the book's scrolling text and catalog; narrow frames and large
/// text stack them in one scrolling column.
/// Parts keep their state across that change, so the page never reloads,
/// collapses expanded text or drops focus when the window is resized.
///
/// [catalog] is a sliver that continues the text column, laid out
/// [BookListItem.inset] wider on each side for its row tints.
class DesktopDetail extends StatefulWidget {
  const DesktopDetail({
    super.key,
    required this.menu,
    this.placeholder,
    this.notices = const [],
    this.cover,
    this.info,
    this.tags,
    this.read,
    this.shelf,
    this.actionNotes = const [],
    this.synopsis,
    this.catalog,
  }) : assert(
         placeholder != null ||
             cover != null &&
                 info != null &&
                 read != null &&
                 shelf != null &&
                 catalog != null,
       );

  /// The more actions button at the end of the title bar.
  final Widget menu;

  /// Shown in place of the page until details load.
  final Widget? placeholder;

  /// Loading, stale and refresh failure notes across the frame.
  final List<Widget> notices;
  final Widget? cover, info, tags, read, shelf, synopsis, catalog;

  /// Notes about the reading and shelf actions, kept under them.
  final List<Widget> actionNotes;

  /// Cover width in one column.
  static const singleCover = 120.0;

  /// From this frame width the side column is [ShioriLayout.detailSideWide].
  static const wideSide = 1000.0;

  @override
  State<DesktopDetail> createState() => _DesktopDetailState();
}

class _DesktopDetailState extends State<DesktopDetail> {
  // Parts that move between the one and two column trees, keyed so their
  // state moves with them: the cover image, expanded text, button focus
  // and the catalog preview's controller. Each page owns its keys.
  final _cover = GlobalKey(debugLabel: 'detail-cover');
  final _tags = GlobalKey(debugLabel: 'detail-tags');
  final _read = GlobalKey(debugLabel: 'detail-read');
  final _shelf = GlobalKey(debugLabel: 'detail-shelf');
  final _synopsis = GlobalKey(debugLabel: 'detail-synopsis');
  final _catalog = GlobalKey(debugLabel: 'detail-catalog');
  // The page scroll moves between the two trees too.
  final _scroll = GlobalKey(debugLabel: 'detail-scroll');

  Widget get _coverPart => KeyedSubtree(key: _cover, child: widget.cover!);
  Widget get _readPart => KeyedSubtree(key: _read, child: widget.read!);
  Widget get _shelfPart => KeyedSubtree(key: _shelf, child: widget.shelf!);
  Widget get _catalogPart =>
      KeyedSubtree(key: _catalog, child: widget.catalog!);

  List<Widget> _tagsPart(double gap) => [
    if (widget.tags case final tags?) ...[
      SizedBox(height: gap),
      KeyedSubtree(key: _tags, child: tags),
    ],
  ];

  /// Box parts on the frame, inside the catalog's bleed.
  static Widget _inset(List<Widget> children) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: BookListItem.inset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  List<Widget> _synopsisPart(BuildContext context) => [
    if (widget.synopsis case final synopsis?) ...[
      const SizedBox(height: ShioriSpace.section),
      Text(
        AppLocalizations.of(context).detailSynopsis,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: ShioriSpace.medium),
      KeyedSubtree(key: _synopsis, child: synopsis),
    ],
  ];

  /// The cover and reading actions, fixed beside the scrolling text. They
  /// scroll on their own only when large text makes them taller than the
  /// page.
  Widget _side(double side) => SizedBox(
    width: side,
    child: SingleChildScrollView(
      key: const ValueKey('detail-side'),
      padding: const EdgeInsets.only(
        top: ShioriSpace.small,
        bottom: ShioriSpace.section,
      ),
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _coverPart,
            const SizedBox(height: ShioriSpace.page),
            _readPart,
            const SizedBox(height: ShioriSpace.small),
            _shelfPart,
            ...widget.actionNotes,
          ],
        ),
      ),
    ),
  );

  /// The book's text, then its catalog, beside the side column.
  Widget _text(BuildContext context) => FocusTraversalGroup(
    child: SliverMainAxisGroup(
      slivers: [
        _inset([
          widget.info!,
          ..._tagsPart(ShioriSpace.item),
          ..._synopsisPart(context),
          const SizedBox(height: ShioriSpace.section),
        ]),
        _catalogPart,
      ],
    ),
  );

  /// The mobile header's arrangement on the frame: cover beside the text,
  /// tags across below, then the actions in a row until space or text size
  /// runs out.
  Widget _single(BuildContext context, double frame) {
    final scaler = MediaQuery.textScalerOf(context);
    final stackHeader = frame < 340 || frame < 560 && scaler.scale(20) > 28;
    final cover = SizedBox(width: DesktopDetail.singleCover, child: _coverPart);
    return SliverMainAxisGroup(
      slivers: [
        _inset([
          ...widget.notices,
          if (stackHeader)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: cover),
                const SizedBox(height: 24),
                widget.info!,
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cover,
                const SizedBox(width: 24),
                Expanded(child: widget.info!),
              ],
            ),
          ..._tagsPart(ShioriSpace.page),
          const SizedBox(height: ShioriSpace.section),
          if (frame < 340 || scaler.scale(14) > 20)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _readPart,
                const SizedBox(height: ShioriSpace.small),
                _shelfPart,
              ],
            )
          else
            Row(
              children: [
                Expanded(flex: 3, child: _readPart),
                const SizedBox(width: ShioriSpace.medium),
                Expanded(flex: 2, child: _shelfPart),
              ],
            ),
          ...widget.actionNotes,
          ..._synopsisPart(context),
          const SizedBox(height: ShioriSpace.section),
        ]),
        _catalogPart,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final layout = desktopDetailLayout(
            bounds.maxWidth,
            DesktopLayoutScope.widthOf(context),
            MediaQuery.textScalerOf(context),
          );
          Widget framed(Widget child) =>
              DesktopContentFrame(maxWidth: ShioriLayout.detail, child: child);
          // Scrolled content sits on the frame widened by the catalog's
          // bleed; the scroll view itself reaches the window's end.
          final end = math.max(0.0, layout.inset - BookListItem.inset);
          Widget scroll(double start, Widget sliver) => KeyedSubtree(
            key: _scroll,
            child: CustomScrollView(
              key: const ValueKey('detail-scroll'),
              slivers: [
                SliverPadding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    math.max(0.0, start),
                    ShioriSpace.small,
                    end,
                    ShioriSpace.section,
                  ),
                  sliver: sliver,
                ),
              ],
            ),
          );
          final Widget page;
          if (widget.placeholder case final placeholder?) {
            page = framed(placeholder);
          } else if (layout.columns) {
            page = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Loading and refresh notes stay across the frame.
                if (widget.notices.isNotEmpty)
                  framed(
                    Padding(
                      padding: const EdgeInsets.only(top: ShioriSpace.small),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: widget.notices,
                      ),
                    ),
                  ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Full-width main scroll owns the blank margins. The
                      // independent side viewport takes hits only on its box.
                      scroll(
                        layout.inset +
                            layout.side +
                            ShioriLayout.detailGap -
                            BookListItem.inset,
                        _text(context),
                      ),
                      PositionedDirectional(
                        start: layout.inset,
                        top: 0,
                        bottom: 0,
                        width: layout.side,
                        child: _side(layout.side),
                      ),
                    ],
                  ),
                ),
              ],
            );
          } else {
            page = scroll(
              layout.inset - BookListItem.inset,
              _single(context, layout.frame),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              framed(DesktopDetailBar(menu: widget.menu)),
              Expanded(child: page),
            ],
          );
        },
      ),
    ),
  );
}

/// The fixed detail title bar on the page frame: back in its own slot at
/// the frame's start, the page title after it, more actions ending on the
/// frame's end.
class DesktopDetailBar extends StatelessWidget {
  const DesktopDetailBar({super.key, required this.menu});
  final Widget menu;

  /// The back and more buttons' square slots; spacing belongs to the toolbar.
  static const slot = 40.0;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return DesktopPageToolbar(
      title: AppLocalizations.of(context).novelDetailsTitle,
      leading: canPop
          ? const SizedBox.square(
              dimension: slot,
              child: BackButton(key: ValueKey('detail-back')),
            )
          : null,
      actions: [SizedBox.square(dimension: slot, child: menu)],
    );
  }
}
