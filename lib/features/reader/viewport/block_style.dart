import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/contracts/local_books.dart';
import '../article_heading.dart';

bool _isChapterHeading(ContentBlock block) =>
    block is HeadingBlock && block.level <= 2 ||
    block is ParagraphBlock && isArticleHeading(block.text);

/// Shared by text measurement and rendering in both reading modes.
TextStyle readerBlockStyle(ContentBlock block, TextStyle base) {
  final title = _isChapterHeading(block);
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
              ? 1.4
              : block is HeadingBlock
              ? 1.15
              : .94),
      fontWeight: title ? FontWeight.w700 : FontWeight.w600,
      height: title ? 1.3 : 1.5,
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
    ParagraphAlignment.start =>
      _isChapterHeading(block) ? TextAlign.center : TextAlign.start,
  };
}

/// Presentation-only em spaces. They never enter content or persisted offsets.
String readerIndentPrefix(
  ContentBlock block,
  bool startsBlock,
  double width,
  TextStyle style,
  TextScaler scaler, {
  ChapterKey? chapter,
}) {
  if (block is! ParagraphBlock ||
      !startsBlock ||
      block.text.trim().isEmpty ||
      block.alignment != ParagraphAlignment.start ||
      isArticleHeading(block.text) ||
      RegExp(r'^[\s　]').hasMatch(block.text)) {
    return '';
  }
  final capacity = (width / scaler.scale(style.fontSize ?? 20)).floor() - 1;
  final onlineBody =
      chapter != null &&
      chapter.novelKey.sourceId != LocalBookIdentity.sourceId &&
      RegExp(r'[㐀-鿿]').hasMatch(block.text) &&
      !RegExp(
        r'^[（(]Day\s*[0-9０-９]+[）)]$',
        caseSensitive: false,
      ).hasMatch(block.text.trim());
  final indent = block.leadingIndent > 0
      ? block.leadingIndent
      : onlineBody
      ? 2
      : 0;
  return '\u2003' * indent.clamp(0, capacity.clamp(0, 2));
}

/// Shared vertical rhythm; measurement must reserve the same space as painting.
double readerBlockSpacing(ContentBlock block, double paragraphSpacing) {
  if (_isChapterHeading(block)) return paragraphSpacing + 64;
  if (block is HeadingBlock) return paragraphSpacing + 28;
  return paragraphSpacing;
}
