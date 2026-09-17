import 'package:flutter/material.dart';
import 'reader_box.dart';

import '../../../domain/models/models.dart';
import '../../../domain/contracts/local_books.dart';
import '../article_heading.dart';

bool _isChapterHeading(ContentBlock block, ChapterKey? chapter) =>
    block is HeadingBlock && block.level <= 2 ||
    chapter?.novelKey.sourceId != LocalBookIdentity.sourceId &&
        block is ParagraphBlock &&
        isArticleHeading(block.text);

/// Shared by text measurement and rendering in both reading modes.
TextStyle readerBlockStyle(
  ContentBlock block,
  TextStyle base, {
  ChapterKey? chapter,
}) {
  final title = _isChapterHeading(block, chapter);
  final subtitle =
      block is HeadingBlock ||
      chapter?.novelKey.sourceId != LocalBookIdentity.sourceId &&
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

TextAlign readerBlockAlign(ContentBlock block, {ChapterKey? chapter}) {
  final alignment = switch (block) {
    ParagraphBlock(:final alignment) => alignment,
    HeadingBlock(:final alignment) => alignment,
    _ => ParagraphAlignment.start,
  };
  return switch (alignment) {
    ParagraphAlignment.center => TextAlign.center,
    ParagraphAlignment.end => TextAlign.end,
    ParagraphAlignment.start =>
      _isChapterHeading(block, chapter) ? TextAlign.center : TextAlign.start,
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
      _isChapterHeading(block, chapter) ||
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
double readerBlockSpacing(
  ContentBlock block,
  double paragraphSpacing, {
  ChapterKey? chapter,
}) {
  if (_isChapterHeading(block, chapter)) return paragraphSpacing + 64;
  if (block is HeadingBlock) return paragraphSpacing + 28;
  return paragraphSpacing;
}

/// Keep natural glyph spacing while sharing the unused CJK cell across margins.
/// Measurement and painting must use the same width. Other alignments and
/// headings retain their original layout.
double readerBlockWidth(
  ContentBlock block,
  double available,
  TextStyle style,
  TextScaler scaler,
  TextDirection direction, {
  ChapterKey? chapter,
  Locale? locale,
}) {
  available = readerBoxInnerWidth(block, available);
  if (block.inlineStyles.isNotEmpty) return available;
  if (block is! ParagraphBlock ||
      block.alignment != ParagraphAlignment.start ||
      _isChapterHeading(block, chapter) ||
      !RegExp(r'[㐀-鿿]').hasMatch(block.text) ||
      !available.isFinite) {
    return available;
  }
  final painter = TextPainter(
    text: TextSpan(
      text: '正文排版',
      style: readerBlockStyle(block, style, chapter: chapter),
    ),
    textScaler: scaler,
    locale: locale,
    textDirection: direction,
  )..layout();
  final cell = painter.width / 4;
  painter.dispose();
  if (cell <= 0 || available < cell * 2) return available;
  final cells = (available / cell).floor();
  // A tiny tolerance avoids floating-point rounding moving the last glyph.
  return (cells * cell + .01).clamp(0.0, available);
}
