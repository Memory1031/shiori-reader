import 'package:flutter/material.dart';

enum ReaderColorRole { foreground, background, border }

/// Rendering policy only: authored ARGB values remain unchanged in Domain.
class ReaderAuthoredColors {
  ReaderAuthoredColors(ThemeData theme)
    : paper = theme.scaffoldBackgroundColor,
      ink = theme.colorScheme.onSurface,
      dark = theme.brightness == Brightness.dark;
  final Color paper, ink;
  final bool dark;

  bool _paperLike(Color c) {
    final channels = [c.r, c.g, c.b]..sort();
    return channels.last - channels.first <= .12 &&
        (channels.first >= .9 || channels.last <= .12);
  }

  bool get _warm => paper.r - paper.b > .035;

  Color resolve(Color authored, ReaderColorRole role, {Color? background}) {
    final surface = background ?? paper;
    switch (role) {
      case ReaderColorRole.background:
        if (!_paperLike(authored)) return authored;
        if (!dark && !_warm && authored.computeLuminance() > .8) {
          return authored;
        }
        final channels = [authored.r, authored.g, authored.b]..sort();
        final mean = (authored.r + authored.g + authored.b) / 3;
        final base = dark ? Color.lerp(paper, ink, .08)! : paper;
        // Retain channel differences instead of blending 97% of them away.
        // Light paper subtracts the publisher tint from white; dark paper
        // carries the same chromatic offsets around an elevated dark surface.
        double channel(double value, double paperValue) => dark
            ? (paperValue + (value - mean) * 1.25).clamp(0.0, 1.0)
            : (paperValue * .985 -
                      (channels.last - value) * 1.25 -
                      (channels.last > .5 ? 1 - channels.last : 0) * .5)
                  .clamp(0.0, 1.0);
        return Color.from(
          alpha: authored.a,
          red: channel(authored.r, base.r),
          green: channel(authored.g, base.g),
          blue: channel(authored.b, base.b),
        );
      case ReaderColorRole.foreground:
        if (_paperLike(authored)) {
          return readerColorContrast(ink, surface) >= 4.5
              ? ink
              : _bestInk(surface);
        }
        return dark ? _contrast(authored, surface, 4.5) : authored;
      case ReaderColorRole.border:
        final tinted = dark || _warm
            ? Color.lerp(authored, paper, .25)!
            : authored;
        return dark ? _contrast(tinted, surface, 1.5) : tinted;
    }
  }

  Color _bestInk(Color background) =>
      readerColorContrast(Colors.white, background) >
          readerColorContrast(Colors.black, background)
      ? Colors.white
      : Colors.black;

  Color _contrast(Color color, Color background, double minimum) {
    if (readerColorContrast(color, background) >= minimum) return color;
    final hsl = HSLColor.fromColor(color);
    final target = _bestInk(background) == Colors.white ? 1.0 : 0.0;
    var low = 0.0, high = 1.0;
    for (var i = 0; i < 16; i++) {
      final t = (low + high) / 2;
      final candidate = hsl
          .withLightness(hsl.lightness + (target - hsl.lightness) * t)
          .toColor();
      if (readerColorContrast(candidate, background) >= minimum) {
        high = t;
      } else {
        low = t;
      }
    }
    return hsl
        .withLightness(hsl.lightness + (target - hsl.lightness) * high)
        .toColor();
  }
}

double readerColorContrast(Color a, Color b) {
  final foreground = Color.alphaBlend(a, b).computeLuminance();
  final background = b.computeLuminance();
  return foreground > background
      ? (foreground + .05) / (background + .05)
      : (background + .05) / (foreground + .05);
}
