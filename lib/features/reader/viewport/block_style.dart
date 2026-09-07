import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';

/// Shared by text measurement and rendering in both reading modes.
TextStyle readerBlockStyle(ContentBlock block, TextStyle base) =>
    block is HeadingBlock
    ? base.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: (base.fontSize ?? 20) * (1.3 - (block.level - 1) * .05),
      )
    : base;

TextAlign readerBlockAlign(ContentBlock block) =>
    block is ParagraphBlock && block.alignment == ParagraphAlignment.center
    ? TextAlign.center
    : TextAlign.start;

double readerBlockIndent(
  ContentBlock block,
  TextStyle base,
  TextScaler scaler,
  double width,
  bool startsBlock,
) => block is ParagraphBlock && startsBlock
    ? (block.leadingIndent * scaler.scale(base.fontSize ?? 20)).clamp(
        0.0,
        (width - 1).clamp(0.0, double.infinity),
      )
    : 0;
