import 'package:flutter/material.dart';
import '../../domain/models/models.dart';

const readerMaxPageWidth = 680.0;
const readerMinColumnWidth = 500.0;
const readerColumnGap = 72.0;

// Preserve the existing preference codec; legacy values select the nearest tier.
const readerMarginValues = <double>[12, 21, 30, 39, 48];
int readerMarginTier(double value) => ((value - 12) / 9).round().clamp(0, 4);

double readerHorizontalMargin(
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
  return (30 + (readerMarginTier(settings.horizontalPadding) - 2) * cell / 2)
      .clamp(0.0, 100.0);
}
