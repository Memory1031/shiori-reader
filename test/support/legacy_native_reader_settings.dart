import 'package:flutter/material.dart';
import 'package:shiori/domain/models/models.dart';

// Independent pre-extraction expectations. Keep these separate from the adapter
// and readerHorizontalMargin so a changed mapping cannot bless itself.
TextStyle legacyNativeBodyStyle(
  ReaderSettings settings,
  ThemeData theme, {
  required bool explicitUiTypeface,
}) {
  final typography = explicitUiTypeface ? theme.textTheme.bodyLarge : null;
  return TextStyle(
    fontFamily: typography?.fontFamily,
    fontFamilyFallback: typography?.fontFamilyFallback,
    fontSize: settings.fontSize,
    height: settings.lineHeight,
    color: theme.colorScheme.onSurface,
  );
}

double legacyNativeMargin(
  ReaderSettings settings,
  TextScaler scaler,
  TextDirection direction,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: '正文排版',
      style: TextStyle(fontSize: settings.fontSize),
    ),
    textScaler: scaler,
    textDirection: direction,
  )..layout();
  final cell = painter.width / 4;
  painter.dispose();
  final tier = ((settings.horizontalPadding - 12) / 9).round().clamp(0, 4);
  return (30 + (tier - 2) * cell / 2).clamp(0.0, 100.0);
}
