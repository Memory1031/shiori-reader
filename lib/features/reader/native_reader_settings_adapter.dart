import 'package:flutter/material.dart';

import '../../domain/models/models.dart';
import 'reader_margin.dart';

/// Native typography and gutters resolved from the current reading environment.
/// Theme selection, pagination and page-turn interaction remain with the host.
abstract final class NativeReaderSettingsAdapter {
  static NativeReaderLayoutSettings resolve(
    ReaderSettings settings, {
    required ThemeData theme,
    required TextScaler textScaler,
    required TextDirection textDirection,
    required bool explicitUiTypeface,
  }) {
    final typography = explicitUiTypeface ? theme.textTheme.bodyLarge : null;
    return NativeReaderLayoutSettings(
      bodyStyle: TextStyle(
        fontFamily: typography?.fontFamily,
        fontFamilyFallback: typography?.fontFamilyFallback,
        // Flutter applies textScaler during measurement and painting once.
        fontSize: settings.fontSize,
        height: settings.lineHeight,
        color: theme.colorScheme.onSurface,
      ),
      horizontalMargin: readerHorizontalMargin(
        settings,
        textScaler,
        textDirection,
      ),
      paragraphSpacing: settings.paragraphSpacing,
    );
  }
}

@immutable
final class NativeReaderLayoutSettings {
  const NativeReaderLayoutSettings({
    required this.bodyStyle,
    required this.horizontalMargin,
    required this.paragraphSpacing,
  });

  final TextStyle bodyStyle;
  final double horizontalMargin;
  final double paragraphSpacing;
}
