import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Width classes shared by layout decisions; values follow Material 3.
enum WindowClass {
  compact,
  medium,
  expanded;

  static WindowClass forWidth(double width) => width < 600
      ? compact
      : width < 840
      ? medium
      : expanded;

  static WindowClass of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);
}

/// Platform conventions resolved once from the theme, so widgets ask for a
/// behaviour instead of naming an operating system. Tests steer it through
/// `ThemeData.platform`.
@immutable
class ShioriCapabilities {
  const ShioriCapabilities(this.platform);

  factory ShioriCapabilities.of(BuildContext context) =>
      ShioriCapabilities(Theme.of(context).platform);

  final TargetPlatform platform;

  /// Pages slide horizontally and support the interactive edge-swipe back.
  bool get cupertinoNavigation =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  /// Touch is the primary input; tap zones and immersive reading apply.
  bool get touchFirst =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  /// Mouse and keyboard are the primary input.
  bool get pointerFirst => !touchFirst;

  /// The app may hide the status and navigation bars while reading.
  bool get immersiveSystemUi => touchFirst;

  /// Windows needs an explicit CJK UI face; see `shioriTheme`.
  bool get explicitUiTypeface => platform == TargetPlatform.windows;

  /// Installing an update exits the app while an updater replaces files.
  bool get updateRestartsApp => platform == TargetPlatform.windows;
}

/// Full-screen page route following the platform's navigation convention.
PageRoute<T> platformPageRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
}) => ShioriCapabilities.of(context).cupertinoNavigation
    ? CupertinoPageRoute<T>(builder: builder, settings: settings)
    : MaterialPageRoute<T>(builder: builder, settings: settings);
