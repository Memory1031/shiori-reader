import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';

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
///
/// Sheets open on the root navigator, like dialogs, so on desktop they cover
/// the whole window instead of the shell's workspace. Close one with its own
/// builder context, and open follow-up pages with the caller's context.
Future<T?> showShioriSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  ShioriSheetSize size = ShioriSheetSize.fit,
  bool owned = false,
  Color? barrierColor,
}) => Navigator.of(context, rootNavigator: true).push(
  shioriSheetRoute<T>(
    context,
    builder: builder,
    size: size,
    owned: owned,
    barrierColor: barrierColor,
  ),
);

/// The route [showShioriSheet] pushes, for owners that retire the sheet
/// themselves. A sheet that is not [dismissible] has no handle, drag or
/// barrier dismissal; its content takes the handle's room as top padding.
ModalBottomSheetRoute<T> shioriSheetRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  ShioriSheetSize size = ShioriSheetSize.fit,
  bool owned = false,
  bool dismissible = true,
  Color? barrierColor,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final localizations = MaterialLocalizations.of(context);
  return ModalBottomSheetRoute<T>(
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    modalBarrierColor:
        barrierColor ?? Theme.of(context).bottomSheetTheme.modalBarrierColor,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    showDragHandle: !owned && dismissible,
    backgroundColor: owned ? Colors.transparent : null,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (context) {
      Widget child = owned
          ? builder(context)
          : SafeArea(top: false, child: builder(context));
      if (!owned && !dismissible) {
        child = Padding(
          padding: const EdgeInsets.only(top: ShioriSpace.page),
          child: child,
        );
      }
      return switch (size.heightFactor) {
        final factor? => FractionallySizedBox(
          heightFactor: factor,
          child: child,
        ),
        null => child,
      };
    },
  );
}
