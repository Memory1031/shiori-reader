import 'package:flutter/material.dart';

import '../../domain/models/models.dart';

/// Shared replacement geometry for pagination and painted rich text. Offsets
/// count Unicode code points; each image occupies one U+FFFC in the source.
List<InlineSpan> readerInlineSpans({
  required String text,
  required int offset,
  required List<InlineImage> images,
  required TextStyle style,
  Widget Function(InlineImage)? imageBuilder,
}) {
  final runes = text.runes.toList();
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final image in images) {
    final at = image.offset - offset;
    if (at < 0 || at >= runes.length) continue;
    if (at > cursor) {
      spans.add(
        TextSpan(text: String.fromCharCodes(runes.sublist(cursor, at))),
      );
    }
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SizedBox(
          width: image.widthEm * (style.fontSize ?? 20),
          height: image.heightEm * (style.fontSize ?? 20),
          child: imageBuilder?.call(image),
        ),
      ),
    );
    cursor = at + 1;
  }
  if (cursor < runes.length) {
    spans.add(TextSpan(text: String.fromCharCodes(runes.sublist(cursor))));
  }
  return spans;
}

List<PlaceholderDimensions> readerInlineDimensions({
  required int offset,
  required int length,
  required List<InlineImage> images,
  required TextStyle style,
  required TextScaler scaler,
  required double maxWidth,
}) => [
  for (final image in images)
    if (image.offset >= offset && image.offset < offset + length)
      PlaceholderDimensions(
        size: Size(
          (image.widthEm * scaler.scale(style.fontSize ?? 20)).clamp(
            0.0,
            maxWidth,
          ),
          image.heightEm * scaler.scale(style.fontSize ?? 20),
        ),
        alignment: PlaceholderAlignment.middle,
      ),
];
