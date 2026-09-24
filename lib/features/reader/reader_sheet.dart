import 'package:flutter/material.dart';

/// Shared sheet heights. [fit] sizes to content; [half] leaves the page
/// visible above for live previews; [tall] suits long lists.
enum ReaderSheetSize {
  fit(null),
  half(.6),
  tall(.85);

  const ReaderSheetSize(this.heightFactor);
  final double? heightFactor;
}

/// Reader sheets share one shape, handle, safe-area and motion policy.
/// `useSafeArea` covers the top and sides; the bottom inset is applied here
/// once so content clears the gesture bar.
Future<T?> showReaderSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  ReaderSheetSize size = ReaderSheetSize.fit,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (context) {
    final child = SafeArea(top: false, child: builder(context));
    return switch (size.heightFactor) {
      final factor? => FractionallySizedBox(heightFactor: factor, child: child),
      null => child,
    };
  },
);
