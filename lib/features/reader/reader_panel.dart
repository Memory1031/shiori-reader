import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';

/// Where a desktop reader panel sits over the page.
enum ReaderPanelPlacement {
  /// A contents column at the window's start edge.
  start,

  /// A settings column at the window's end edge.
  end,

  /// A popover above the bottom bar's progress control.
  anchored,
}

/// A desktop reader panel over the page: side columns for contents and
/// settings, and a popover for progress.
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
    if (placement == ReaderPanelPlacement.anchored) return fade;
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

/// An open [ReaderPanelRoute], held by the reader state that opened it.
///
/// It keeps the route, its navigator and its owner rather than a
/// [BuildContext], so the owner can take the panel down from `dispose`.
class ReaderPanelHandle {
  ReaderPanelHandle._(this.owner, this.navigator);

  /// Pushes a panel for [owner] onto the navigator around it.
  ///
  /// [builder] receives the handle so its controls can close the panel.
  factory ReaderPanelHandle.open(
    State owner, {
    required ReaderPanelPlacement placement,
    required Widget Function(BuildContext context, ReaderPanelHandle panel)
    builder,
    String? semanticLabel,
    ThemeData Function(BuildContext context)? theme,
    Listenable? themeChanges,
    GlobalKey? anchor,
  }) {
    final context = owner.context;
    final handle = ReaderPanelHandle._(owner, Navigator.of(context));
    handle.route = ReaderPanelRoute<void>(
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
  late final ReaderPanelRoute<void> route;

  /// Completes once the panel is closed or removed.
  late final Future<void> closed;

  bool _valid = true;

  /// Whether the panel still belongs to a mounted owner. Callbacks from the
  /// panel act only while this holds.
  bool get isValid => _valid && owner.mounted;

  /// Closes the panel with its exit animation.
  void close() {
    if (_valid && route.isCurrent && route.isOpen) navigator.pop();
  }

  /// Retires the handle and removes the panel without animation, for an
  /// owner going away.
  ///
  /// The owner's `dispose` runs while the tree is locked, so the route is
  /// removed after the frame, and only if it is still open in a mounted
  /// navigator; one already closing finishes on its own.
  void dismiss() {
    _valid = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && route.isActive && route.isOpen) {
        navigator.removeRoute(route);
      }
    });
  }
}
