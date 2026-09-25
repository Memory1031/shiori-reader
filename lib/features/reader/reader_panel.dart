import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';

/// Where a desktop reader panel sits over the page.
enum ReaderPanelPlacement {
  /// A contents column at the window's start edge.
  start,

  /// A settings column at the window's end edge.
  end,

  /// A popover above the bottom bar's progress control.
  anchored,

  /// A compact dialog in the middle of the window, for a single note.
  center,
}

/// A desktop reader panel over the page: side columns for contents,
/// settings, notes and prefetch, a popover for progress and a dialog for a
/// single footnote.
///
/// The route is modal. Its barrier takes every pointer event bound for the
/// page, blocks the page's semantics and dismisses on a click or Esc, and
/// keyboard traversal loops inside the panel, so neither the reader nor the
/// shell behind it takes focus or input while it is open. Closing returns
/// focus to where it was through the navigator's focus history.
///
/// The page keeps its size underneath, so an open panel never changes the
/// reading layout.
class ReaderPanelRoute<T> extends PopupRoute<T> {
  ReaderPanelRoute({
    required this.placement,
    required this.builder,
    required this.barrierLabel,
    required Duration duration,
    this.semanticLabel,
    this.theme,
    this.themeChanges,
    this.anchor,
    super.settings,
  }) : assert((placement == ReaderPanelPlacement.anchored) == (anchor != null)),
       _duration = duration,
       super(
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
         directionalTraversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );

  /// Side panels slide this far in from their edge as they fade in.
  static const slide = 16.0;
  static const motion = Duration(milliseconds: 150);

  /// Room between a panel and the window's edges.
  static const margin = ShioriSpace.medium;

  /// Page left in view beside a side panel on narrow windows.
  static const reveal = 56.0;

  /// Space between the popover and its anchor.
  static const anchorGap = ShioriSpace.small;

  /// A centred dialog's widest and tallest extent.
  static const dialogWidth = 480.0;
  static const dialogHeight = 560.0;

  final ReaderPanelPlacement placement;
  final WidgetBuilder builder;
  final String? semanticLabel;

  /// Theme for the panel, rebuilt whenever [themeChanges] notifies, so the
  /// panel follows live reading-theme edits. Null keeps the ambient theme.
  final ThemeData Function(BuildContext context)? theme;
  final Listenable? themeChanges;

  /// The progress control an [ReaderPanelPlacement.anchored] panel sits
  /// above. The popover measures it whenever it lays out rather than once on
  /// opening, so resizing the window keeps it in place.
  final GlobalKey? anchor;
  final Duration _duration;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => placement == ReaderPanelPlacement.anchored
      ? null
      : Colors.black.withValues(alpha: .18);

  @override
  Duration get transitionDuration => _duration;

  @override
  Duration get reverseTransitionDuration => _duration;

  /// A side panel's width in a window [width] wide.
  static double sideWidth(ReaderPanelPlacement placement, double width) {
    if (width < 480) return math.max(0, width - 2 * margin);
    final preferred = placement == ReaderPanelPlacement.start
        ? (width * .28).clamp(320.0, 360.0)
        : (width * .30).clamp(360.0, 400.0);
    return math.max(0, math.min(preferred, width - 2 * margin - reveal));
  }

  /// The popover's width in a window [width] wide.
  static double popoverWidth(double width) =>
      math.max(0, math.min(360, width - 2 * margin));

  /// The centred dialog's limits in a window of [size]: its width, and the
  /// height it may grow to with its content.
  static Size dialogExtent(Size size) => Size(
    math.max(0, math.min(dialogWidth, size.width - 2 * margin)),
    math.max(0, math.min(dialogHeight, size.height - 2 * margin)),
  );

  Widget _surface(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Material(
        // As the settings panel: night paper sits a step below the dark
        // surface, so the panel lifts off the page by tone as well.
        color: theme.brightness == Brightness.dark
            ? scheme.surface
            : theme.scaffoldBackgroundColor,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(ShioriShape.card),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  Widget _themed(BuildContext context, WidgetBuilder child) {
    final theme = this.theme;
    if (theme == null) return Builder(builder: child);
    return ListenableBuilder(
      listenable: themeChanges ?? const _Unchanging(),
      builder: (context, _) => Theme(
        data: theme(context),
        child: Builder(builder: child),
      ),
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _themed(
    context,
    (context) => MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: LayoutBuilder(
        builder: (context, bounds) => switch (placement) {
          ReaderPanelPlacement.anchored => _popover(context, bounds),
          ReaderPanelPlacement.center => _dialog(context, bounds),
          _ => _side(context, bounds),
        },
      ),
    ),
  );

  Widget _side(BuildContext context, BoxConstraints bounds) => Align(
    alignment: placement == ReaderPanelPlacement.start
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.centerEnd,
    child: Padding(
      padding: const EdgeInsets.all(margin),
      child: SizedBox(
        key: const ValueKey('reader-panel'),
        width: sideWidth(placement, bounds.maxWidth),
        height: math.max(0, bounds.maxHeight - 2 * margin),
        child: _surface(context, Builder(builder: builder)),
      ),
    ),
  );

  /// As tall as its content up to [dialogExtent]; the content scrolls past
  /// it.
  Widget _dialog(BuildContext context, BoxConstraints bounds) {
    final extent = dialogExtent(bounds.biggest);
    return Center(
      child: ConstrainedBox(
        key: const ValueKey('reader-panel'),
        constraints: BoxConstraints(
          minWidth: extent.width,
          maxWidth: extent.width,
          maxHeight: extent.height,
        ),
        child: _surface(context, Builder(builder: builder)),
      ),
    );
  }

  Widget _popover(BuildContext context, BoxConstraints bounds) =>
      _AnchoredPopover(
        anchor: anchor!,
        bounds: bounds,
        child: _surface(
          context,
          SingleChildScrollView(
            padding: const EdgeInsets.only(top: ShioriSpace.item),
            child: Builder(builder: builder),
          ),
        ),
      );

  // Made once: a curve listens to its parent until it is disposed.
  CurvedAnimation? _curve;
  CurvedAnimation get _curved => _curve ??= CurvedAnimation(
    parent: animation!,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Whether the panel is showing or opening, rather than closing.
  bool get isOpen => switch (animation?.status) {
    AnimationStatus.forward || AnimationStatus.completed => true,
    _ => false,
  };

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = _curved;
    final fade = FadeTransition(opacity: curved, child: child);
    if (placement
        case ReaderPanelPlacement.anchored || ReaderPanelPlacement.center) {
      return fade;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final towardStart = (placement == ReaderPanelPlacement.start) != rtl;
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Transform.translate(
        offset: Offset((1 - curved.value) * (towardStart ? -slide : slide), 0),
        child: child,
      ),
      child: fade,
    );
  }
}

/// Places the popover above its anchor, centred on it and kept inside the
/// window.
///
/// The anchor lives in the route below, so it is measured rather than
/// followed through a layer link: a follower layer would leave tooltips and
/// menus inside the popover without a reliable transform. The measurement
/// runs in the route's layout callback, after the page below has laid out
/// for a resize, and is checked again after each frame in case the page
/// moved on its own.
class _AnchoredPopover extends StatefulWidget {
  const _AnchoredPopover({
    required this.anchor,
    required this.bounds,
    required this.child,
  });

  final GlobalKey anchor;
  final BoxConstraints bounds;
  final Widget child;

  @override
  State<_AnchoredPopover> createState() => _AnchoredPopoverState();
}

class _AnchoredPopoverState extends State<_AnchoredPopover> {
  Rect? _placed;

  /// The anchor's rect in the overlay, which this route fills.
  Rect? _measure() {
    final anchor = widget.anchor.currentContext?.findRenderObject();
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (anchor is! RenderBox ||
        overlay is! RenderBox ||
        !anchor.attached ||
        !anchor.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
      anchor.getTransformTo(overlay),
      Offset.zero & anchor.size,
    );
  }

  void _recheck(Duration _) {
    if (!mounted) return;
    final rect = _measure();
    if (rect != null && rect != _placed) setState(() {});
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, _) {
      final rect = _placed = _measure() ?? _placed;
      WidgetsBinding.instance.addPostFrameCallback(_recheck);
      if (rect == null) return const SizedBox.shrink();
      final bounds = widget.bounds;
      const margin = ReaderPanelRoute.margin;
      final width = ReaderPanelRoute.popoverWidth(bounds.maxWidth);
      final left = (rect.center.dx - width / 2)
          .clamp(margin, math.max(margin, bounds.maxWidth - margin - width))
          .toDouble();
      final above = rect.top - ReaderPanelRoute.anchorGap;
      return Stack(
        children: [
          Positioned(
            left: left,
            bottom: bounds.maxHeight - above,
            width: width,
            child: ConstrainedBox(
              key: const ValueKey('reader-panel'),
              constraints: BoxConstraints(
                maxHeight: math.max(
                  0,
                  math.min(bounds.maxHeight * .6, above - margin),
                ),
              ),
              child: widget.child,
            ),
          ),
        ],
      );
    },
  );
}

class _Unchanging implements Listenable {
  const _Unchanging();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// Closes a reader panel or sheet, then applies [then], the choice made in
/// it, if any.
///
/// A sheet applies the choice as it closes. A desktop panel hands it back
/// as its result instead: the page that opened the panel applies it once
/// the panel has closed, and only while that page still reads the same
/// session and takes commands. Either way only the first call counts.
typedef ReaderPanelDone = void Function([VoidCallback? then]);

/// [ReaderPanelDone] for a sheet: pops it and applies the choice, once.
ReaderPanelDone readerSheetDone(BuildContext sheet) => ([then]) {
  // A sheet already closing, or covered, takes no further choice.
  if (ModalRoute.of(sheet)?.isCurrent != true) return;
  Navigator.of(sheet).pop();
  then?.call();
};

/// An open [ReaderPanelRoute], held by the reader state that opened it.
///
/// It keeps the route, its navigator and its owner rather than a
/// [BuildContext], so the owner can take the panel down from `dispose`.
///
/// Whether the panel still takes input ([isValid], which [close] ends at
/// once) is kept apart from whether a choice made in it reaches the reader:
/// the choice travels as the result in [closed], for the opener to check
/// against its session before acting on it.
class ReaderPanelHandle<T> {
  ReaderPanelHandle._(this.owner, this.navigator);

  /// Pushes a panel for [owner] onto the navigator around it.
  ///
  /// [builder] receives the handle so its controls can close the panel.
  factory ReaderPanelHandle.open(
    State owner, {
    required ReaderPanelPlacement placement,
    required Widget Function(BuildContext context, ReaderPanelHandle<T> panel)
    builder,
    String? semanticLabel,
    ThemeData Function(BuildContext context)? theme,
    Listenable? themeChanges,
    GlobalKey? anchor,
  }) {
    final context = owner.context;
    final handle = ReaderPanelHandle<T>._(owner, Navigator.of(context));
    handle.route = ReaderPanelRoute<T>(
      placement: placement,
      builder: (context) => builder(context, handle),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      duration: ShioriMotion.of(context, ReaderPanelRoute.motion),
      semanticLabel: semanticLabel,
      theme: theme,
      themeChanges: themeChanges,
      anchor: anchor,
    );
    handle.closed = handle.navigator.push(handle.route);
    return handle;
  }

  final State owner;
  final NavigatorState navigator;
  late final ReaderPanelRoute<T> route;

  /// The panel's result: what [close] was given, or null once it is
  /// dismissed by Esc or a click outside, or removed.
  late final Future<T?> closed;

  /// Completes once the panel has finished its exit and left the overlay.
  Future<void> get completed => route.completed;

  bool _accepting = true;

  /// Whether the panel still takes input for a mounted owner: it has been
  /// neither closed, dismissed nor retired. Callbacks from the panel act
  /// only while this holds.
  bool get isValid =>
      _accepting && owner.mounted && route.isActive && route.isOpen;

  /// Closes the panel with its exit animation, handing back [result]. Only
  /// the first call on an open, uncovered panel counts; the panel takes no
  /// further input from then on.
  void close([T? result]) {
    if (!isValid || !route.isCurrent) return;
    _accepting = false;
    navigator.pop(result);
  }

  /// Retires the handle and removes the panel without animation, for an
  /// owner going away or no longer taking commands. [closed] then resolves
  /// with null.
  ///
  /// The owner's `dispose` and `didUpdateWidget` run while the tree is
  /// locked, so the route is removed after the frame, and only if it is
  /// still open in a mounted navigator; one already closing finishes on its
  /// own. Only this route is removed: whatever was pushed above it stays.
  void dismiss() {
    _accepting = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && route.isActive && route.isOpen) {
        navigator.removeRoute(route);
      }
    });
  }
}

/// The panel slot of one reader page, handed to screen-level commands such
/// as notes and prefetch so that what they open sits over that page, in its
/// reading theme, and shares its single slot.
///
/// It is passed explicitly rather than looked up, so a command always
/// reaches the page it was invoked from.
abstract interface class ReaderPanels {
  /// Whether panels open over the page (pointer-first desktops) rather than
  /// as sheets.
  bool get desktop;

  /// The page's context, in its reading theme, for sheets.
  BuildContext get context;

  /// Whether the page is still mounted, reads the session the command was
  /// invoked for and takes commands. A choice returned from a panel or a
  /// sheet is acted on only while this holds.
  bool get live;

  /// Opens a desktop panel in the page's slot, in the reading theme. Null
  /// when the slot is taken or the page is not [live].
  ReaderPanelHandle<T>? open<T>(
    ReaderPanelPlacement placement, {
    required String semanticLabel,
    required Widget Function(BuildContext context, ReaderPanelHandle<T> panel)
    builder,
  });

  /// Shows a single footnote over the page: a dialog on desktop, a sheet
  /// elsewhere.
  Future<void> footnote(LocalContentLink note);
}
