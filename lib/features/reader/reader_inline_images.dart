import 'package:flutter/material.dart';

import '../../domain/models/models.dart';

/// Shared replacement geometry for pagination and painted rich text. Offsets
/// count Unicode code points; each image occupies one U+FFFC in the source.
List<InlineSpan> readerInlineSpans({
  required String text,
  required int offset,
  required List<InlineImage> images,
  List<InlineTextStyle> styles = const [],
  required TextStyle style,
  Widget Function(InlineImage)? imageBuilder,
  Color Function(Color)? resolveColor,
}) {
  final runes = text.runes.toList();
  final end = offset + runes.length;
  final cuts = <int>{offset, end};
  final pictures = {for (final i in images) i.offset: i};
  for (final range in styles) {
    if (range.start > offset && range.start < end) cuts.add(range.start);
    final last = range.start + range.length;
    if (last > offset && last < end) cuts.add(last);
  }
  for (final image in images) {
    if (image.offset >= offset && image.offset < end) {
      cuts.add(image.offset);
      cuts.add(image.offset + 1);
    }
  }
  final ordered = cuts.toList()..sort();
  return [
    for (var i = 0; i + 1 < ordered.length; i++)
      if (pictures[ordered[i]] case final image?)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox(
            width:
                image.widthEm *
                (readerAuthoredStyle(style, styles, ordered[i]).fontSize ?? 20),
            height:
                image.heightEm *
                (readerAuthoredStyle(style, styles, ordered[i]).fontSize ?? 20),
            child: imageBuilder?.call(image),
          ),
        )
      else
        TextSpan(
          text: String.fromCharCodes(
            runes.sublist(ordered[i] - offset, ordered[i + 1] - offset),
          ),
          style: readerAuthoredStyle(
            style,
            styles,
            ordered[i],
            resolveColor: resolveColor,
          ),
        ),
  ];
}

TextStyle readerAuthoredStyle(
  TextStyle base,
  List<InlineTextStyle> styles,
  int offset, {
  Color Function(Color)? resolveColor,
}) {
  final range = styles
      .where((s) => s.start <= offset && offset < s.start + s.length)
      .firstOrNull;
  if (range == null) return base;
  return base.copyWith(
    color: range.color == null
        ? base.color
        : (resolveColor?.call(Color(range.color!)) ?? Color(range.color!)),
    fontSize: (base.fontSize ?? 20) * range.fontScale,
    fontWeight: range.bold ? FontWeight.bold : FontWeight.normal,
    fontStyle: range.italic ? FontStyle.italic : FontStyle.normal,
  );
}

List<PlaceholderDimensions> readerInlineDimensions({
  required int offset,
  required int length,
  required List<InlineImage> images,
  List<InlineTextStyle> styles = const [],
  required TextStyle style,
  required TextScaler scaler,
  required double maxWidth,
}) => [
  for (final image in images)
    if (image.offset >= offset && image.offset < offset + length)
      PlaceholderDimensions(
        size: Size(
          (image.widthEm *
                  scaler.scale(
                    readerAuthoredStyle(style, styles, image.offset).fontSize ??
                        20,
                  ))
              .clamp(0.0, maxWidth),
          image.heightEm *
              scaler.scale(
                readerAuthoredStyle(style, styles, image.offset).fontSize ?? 20,
              ),
        ),
        alignment: PlaceholderAlignment.middle,
      ),
];
