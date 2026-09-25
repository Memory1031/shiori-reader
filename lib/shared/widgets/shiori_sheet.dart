import 'package:flutter/material.dart';

/// Shared sheet heights. [fit] sizes to content; [half] leaves the page
/// visible above for live previews; [tall] suits long lists.
enum ShioriSheetSize {
  fit(null),
  half(.6),
  tall(.85);

  const ShioriSheetSize(this.heightFactor);
  final double? heightFactor;
}

/// Modal sheets share one shape, handle, safe-area and motion policy.
/// `useSafeArea` covers the top and sides; the bottom inset is applied here
/// once so content clears the gesture bar. Hosts that draw their own
/// surface (e.g. a live-themed reader panel) pass [owned] to drop the
/// default handle and background. A lighter [barrierColor] keeps the page
/// behind readable, e.g. while previewing reading colours.
Future<T?> showShioriSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  ShioriSheetSize size = ShioriSheetSize.fit,
  bool owned = false,
  Color? barrierColor,
}) => showModalBottomSheet<T>(
  context: context,
  barrierColor: barrierColor,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: !owned,
  backgroundColor: owned ? Colors.transparent : null,
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (context) {
    final child = owned
        ? builder(context)
        : SafeArea(top: false, child: builder(context));
    return switch (size.heightFactor) {
      final factor? => FractionallySizedBox(heightFactor: factor, child: child),
      null => child,
    };
  },
);
