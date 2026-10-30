import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import 'desktop_content_frame.dart';
import 'shiori_sheet.dart';

export 'shiori_sheet.dart' show ShioriSheetSize;

/// The logical edge of a wide reader panel. Ordinary panels omit a side.
enum ShioriPanelSide { start, end }

enum ShioriPanelPresentation { sheet, dialog, side }

/// Presentation belongs to the open route, so resizing cannot double-frame it.
class ShioriPanelScope extends InheritedWidget {
  const ShioriPanelScope({
    super.key,
    required this.presentation,
    required super.child,
  });
  final ShioriPanelPresentation presentation;

  static ShioriPanelPresentation of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ShioriPanelScope>()
          ?.presentation ??
      (ModalRoute.of(context) is ModalBottomSheetRoute
          ? ShioriPanelPresentation.sheet
          : ModalRoute.of(context) is DialogRoute
          ? ShioriPanelPresentation.dialog
          : resolve(context));

  static ShioriPanelPresentation resolve(
    BuildContext context, {
    ShioriPanelSide? side,
  }) => !DesktopLayoutScope.useDesktopPage(context)
      ? ShioriPanelPresentation.sheet
      : side == null
      ? ShioriPanelPresentation.dialog
      : ShioriPanelPresentation.side;

  static bool isSheet(BuildContext context) =>
      of(context) == ShioriPanelPresentation.sheet;

  @override
  bool updateShouldNotify(ShioriPanelScope oldWidget) =>
      presentation != oldWidget.presentation;
}

/// One policy for panel interactions: compact sheet, wide app dialog or reader
/// side panel. The route keeps its presentation until closed and bounds it to
/// the current viewport. Callers supply content, not platform/width branches.
ModalRoute<T> shioriPanelRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  WidgetBuilder? dialogBuilder,
  ShioriPanelSide? side,
  ShioriSheetSize size = ShioriSheetSize.fit,
  bool owned = false,
  bool dismissible = true,
  Color? barrierColor,
  String? semanticLabel,
  ThemeData Function(BuildContext)? theme,
  Listenable? themeChanges,
}) {
  final presentation = ShioriPanelScope.resolve(context, side: side);
  final navigator = Navigator.of(context, rootNavigator: true);
  final captured = InheritedTheme.capture(from: context, to: navigator.context);
  Widget wrap(WidgetBuilder body) => captured.wrap(
    ShioriPanelScope(
      presentation: presentation,
      child: Builder(
        builder: (context) => theme == null
            ? body(context)
            : ListenableBuilder(
                listenable: themeChanges ?? const _Unchanging(),
                builder: (context, _) => Theme(
                  data: theme(context),
                  child: Builder(builder: body),
                ),
              ),
      ),
    ),
  );
  if (presentation == ShioriPanelPresentation.sheet) {
    return shioriSheetRoute<T>(
      context,
      builder: builder,
      wrapper: wrap,
      size: size,
      owned: owned,
      dismissible: dismissible,
      barrierColor: barrierColor,
    );
  }
  if (side != null) {
    return ShioriSidePanelRoute<T>(
      placement: side,
      builder: builder,
      wrapper: (child) => wrap((_) => child),
      semanticLabel: semanticLabel,
      dismissible: dismissible,
      barrierColor: barrierColor ?? Colors.black.withValues(alpha: .18),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      duration: ShioriMotion.of(context, ShioriSidePanelRoute.motion),
    );
  }
  return DialogRoute<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierColor: barrierColor ?? Colors.black54,
    builder: (_) => wrap(
      dialogBuilder ??
          (context) => Dialog(
            constraints: const BoxConstraints(maxWidth: ShioriLayout.panel),
            child: builder(context),
          ),
    ),
  );
}

Future<T?> showShioriPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  WidgetBuilder? dialogBuilder,
  ShioriPanelSide? side,
  ShioriSheetSize size = ShioriSheetSize.fit,
  bool owned = false,
  bool dismissible = true,
  Color? barrierColor,
  String? semanticLabel,
  ThemeData Function(BuildContext)? theme,
  Listenable? themeChanges,
}) => Navigator.of(context, rootNavigator: true).push(
  shioriPanelRoute<T>(
    context,
    builder: builder,
    dialogBuilder: dialogBuilder,
    side: side,
    size: size,
    owned: owned,
    dismissible: dismissible,
    barrierColor: barrierColor,
    semanticLabel: semanticLabel,
    theme: theme,
    themeChanges: themeChanges,
  ),
);

bool shioriPanelIsOpen(ModalRoute<dynamic> route) =>
    route.isActive &&
    switch (route.animation?.status) {
      AnimationStatus.forward || AnimationStatus.completed => true,
      _ => false,
    };

/// A modal side surface; the page underneath keeps its layout and focus history.
class ShioriSidePanelRoute<T> extends PopupRoute<T> {
  ShioriSidePanelRoute({
    required this.placement,
    required this.builder,
    required this.barrierLabel,
    required Duration duration,
    this.semanticLabel,
    this.wrapper,
    this.dismissible = true,
    this.barrierColor = Colors.black26,
    super.settings,
  }) : _duration = duration,
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

  final ShioriPanelSide placement;
  final WidgetBuilder builder;
  final String? semanticLabel;
  final Widget Function(Widget)? wrapper;
  final bool dismissible;

  final Duration _duration;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => dismissible;

  @override
  final Color? barrierColor;

  @override
  Duration get transitionDuration => _duration;

  @override
  Duration get reverseTransitionDuration => _duration;

  /// A side panel's width in a window [width] wide.
  static double sideWidth(ShioriPanelSide placement, double width) {
    if (width < 480) return math.max(0, width - 2 * margin);
    final preferred = placement == ShioriPanelSide.start
        ? (width * .28).clamp(320.0, 360.0)
        : (width * .30).clamp(360.0, 400.0);
    return math.max(0, math.min(preferred, width - 2 * margin - reveal));
  }

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

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final content = SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) => _side(context, bounds),
      ),
    );
    return wrapper?.call(content) ?? content;
  }

  Widget _side(BuildContext context, BoxConstraints bounds) => Align(
    alignment: placement == ShioriPanelSide.start
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
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final towardStart = (placement == ShioriPanelSide.start) != rtl;
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

class _Unchanging implements Listenable {
  const _Unchanging();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
