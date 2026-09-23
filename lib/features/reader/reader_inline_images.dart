import 'package:flutter/material.dart';

import '../../domain/models/models.dart';
import 'reader_ruby.dart';

/// Shared replacement geometry for pagination and painted rich text. Offsets
/// count Unicode code points; each image occupies one U+FFFC in the source.
List<InlineSpan> readerInlineSpans({
  required String text,
  required int offset,
  required List<InlineImage> images,
  List<InlineTextStyle> styles = const [],
  required TextStyle style,
  Widget Function(InlineImage)? imageBuilder,
  List<InlineRuby> ruby = const [],
  TextScaler scaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
  Locale? locale,
  double maxWidth = double.infinity,
  VoidCallback? onRubyTap,
  Color Function(Color)? resolveColor,
}) {
  final runes = text.runes.toList();
  final end = offset + runes.length;
  final cuts = <int>{offset, end};
  final pictures = {for (final i in images) i.offset: i};
  final pairs = {
    for (final r in ruby)
      if (r.start >= offset && r.end <= end) r.start: r,
  };
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
  for (final r in pairs.values) {
    cuts.removeWhere((c) => c > r.start && c < r.end);
    cuts.addAll([r.start, r.end]);
  }
  final ordered = cuts.toList()..sort();
  return [
    for (var i = 0; i + 1 < ordered.length; i++)
      if (pairs[ordered[i]] case final pair?)
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          style: readerAuthoredStyle(style, styles, pair.start),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRubyTap,
            child: ReaderRuby(
              baseText: String.fromCharCodes(
                runes.sublist(pair.start - offset, pair.end - offset),
              ),
              layout: readerRubyLayout(
                text: String.fromCharCodes(
                  runes.sublist(pair.start - offset, pair.end - offset),
                ),
                ruby: pair,
                styles: styles,
                style: style,
                scaler: scaler,
                direction: direction,
                locale: locale,
                maxWidth: maxWidth,
                resolveColor: resolveColor,
              ),
            ),
          ),
        )
      else if (pictures[ordered[i]] case final image?)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          // Flutter scales the child once using this authored font size.
          style: readerAuthoredStyle(style, styles, ordered[i]),
          child: SizedBox(
            width: readerInlineSize(
              image,
              readerAuthoredStyle(style, styles, ordered[i]),
              TextScaler.noScaling,
            ).width,
            height: readerInlineSize(
              image,
              readerAuthoredStyle(style, styles, ordered[i]),
              TextScaler.noScaling,
            ).height,
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
    fontWeight: switch (range.bold) {
      true => FontWeight.bold,
      false => FontWeight.normal,
      null => base.fontWeight,
    },
    fontStyle: switch (range.italic) {
      true => FontStyle.italic,
      false => FontStyle.normal,
      null => base.fontStyle,
    },
  );
}

ReaderRubyLayout readerRubyLayout({
  required String text,
  required InlineRuby ruby,
  required List<InlineTextStyle> styles,
  required TextStyle style,
  required TextScaler scaler,
  required TextDirection direction,
  required double maxWidth,
  Locale? locale,
  Color Function(Color)? resolveColor,
}) => ReaderRubyLayout(
  base: TextSpan(
    style: style,
    children: readerInlineSpans(
      text: text,
      offset: ruby.start,
      images: const [],
      styles: styles,
      style: style,
      resolveColor: resolveColor,
    ),
  ),
  annotation: ruby.annotation,
  style: readerAuthoredStyle(
    style,
    styles,
    ruby.start,
    resolveColor: resolveColor,
  ),
  scaler: scaler,
  direction: direction,
  locale: locale,
  maxWidth: maxWidth,
);

List<PlaceholderDimensions> readerInlineDimensions({
  required int offset,
  required int length,
  required List<InlineImage> images,
  List<InlineTextStyle> styles = const [],
  List<InlineRuby> ruby = const [],
  String text = '',
  TextDirection direction = TextDirection.ltr,
  Locale? locale,
  required TextStyle style,
  required TextScaler scaler,
  required double maxWidth,
}) {
  final dimensions = <(int, PlaceholderDimensions)>[
    for (final image in images)
      if (image.offset >= offset && image.offset < offset + length)
        (
          image.offset,
          PlaceholderDimensions(
            size: readerInlineSize(
              image,
              readerAuthoredStyle(style, styles, image.offset),
              scaler,
              maxWidth: maxWidth,
            ),
            alignment: PlaceholderAlignment.middle,
          ),
        ),
    for (final pair in ruby)
      if (pair.start >= offset && pair.end <= offset + length)
        (
          pair.start,
          (() {
            final layout = readerRubyLayout(
              text: String.fromCharCodes(
                text.runes.skip(pair.start - offset).take(pair.length),
              ),
              ruby: pair,
              styles: styles,
              style: style,
              scaler: scaler,
              direction: direction,
              locale: locale,
              maxWidth: maxWidth,
            );
            return PlaceholderDimensions(
              size: layout.metrics.size,
              baseline: TextBaseline.alphabetic,
              baselineOffset: layout.metrics.baseline,
              alignment: PlaceholderAlignment.baseline,
            );
          })(),
        ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return dimensions.map((d) => d.$2).toList();
}

/// TextPainter counts a ruby WidgetSpan as one UTF-16 unit. Positions outside
/// Flutter continue to address the original base text, never the annotation.
int readerInlineSourceBoundary(
  String text,
  int offset,
  List<InlineRuby> ruby,
  int display,
) {
  final runes = text.runes.toList();
  final pairs = {
    for (final r in ruby)
      if (r.start >= offset && r.end <= offset + runes.length)
        r.start - offset: r,
  };
  var source = 0, rendered = 0, utf16 = 0;
  while (source < runes.length && rendered < display) {
    final pair = pairs[source];
    final count = pair?.length ?? 1;
    final units = pair != null ? 1 : (runes[source] > 0xffff ? 2 : 1);
    if (rendered + units > display) break;
    utf16 += String.fromCharCodes(runes.skip(source).take(count)).length;
    source += count;
    rendered += units;
  }
  return utf16;
}

/// WidgetSpan uses unscaled child geometry and applies the same scaler itself.
Size readerInlineSize(
  InlineImage image,
  TextStyle style,
  TextScaler scaler, {
  double maxWidth = double.infinity,
}) {
  final em = scaler.scale(style.fontSize ?? 20);
  return Size((image.widthEm * em).clamp(0, maxWidth), image.heightEm * em);
}
