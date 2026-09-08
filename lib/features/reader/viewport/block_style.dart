import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../article_heading.dart';

/// Shared by text measurement and rendering in both reading modes.
TextStyle readerBlockStyle(ContentBlock block, TextStyle base) {
  final title =
      block is HeadingBlock && block.level <= 2 ||
      block is ParagraphBlock && isArticleHeading(block.text);
  final subtitle =
      block is HeadingBlock ||
      block is ParagraphBlock &&
          RegExp(
            r'^(?:[^\n。！？!?]{1,48}\s*)?[（(]Day\s*[0-9０-９]+[）)]$',
            caseSensitive: false,
          ).hasMatch(block.text.trim());
  if (title || subtitle) {
    return base.copyWith(
      fontSize:
          (base.fontSize ?? 18) *
          (title
              ? 1.35
              : block is HeadingBlock
              ? 1.08
              : .94),
      fontWeight: FontWeight.w600,
      height: title ? 1.45 : 1.5,
      color: subtitle && !title
          ? base.color?.withValues(alpha: .7)
          : base.color,
    );
  }
  return base;
}

TextAlign readerBlockAlign(ContentBlock block) {
  final alignment = switch (block) {
    ParagraphBlock(:final alignment) => alignment,
    HeadingBlock(:final alignment) => alignment,
    _ => ParagraphAlignment.start,
  };
  return switch (alignment) {
    ParagraphAlignment.center => TextAlign.center,
    ParagraphAlignment.end => TextAlign.end,
    ParagraphAlignment.start => TextAlign.start,
  };
}

/// Presentation-only em spaces. They never enter content or persisted offsets.
String readerIndentPrefix(
  ContentBlock block,
  bool startsBlock,
  double width,
  TextStyle style,
  TextScaler scaler,
) {
  if (block is! ParagraphBlock ||
      !startsBlock ||
      block.alignment != ParagraphAlignment.start ||
      isArticleHeading(block.text) ||
      RegExp(r'^[\s　]').hasMatch(block.text)) {
    return '';
  }
  final capacity = (width / scaler.scale(style.fontSize ?? 20)).floor() - 1;
  return '\u2003' * block.leadingIndent.clamp(0, capacity.clamp(0, 2));
}

/// Shared vertical rhythm; measurement must reserve the same space as painting.
double readerBlockSpacing(ContentBlock block, double paragraphSpacing) {
  if (block is HeadingBlock ||
      block is ParagraphBlock && isArticleHeading(block.text)) {
    return paragraphSpacing + 20;
  }
  return paragraphSpacing;
}
