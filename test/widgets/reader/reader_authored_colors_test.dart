import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/reader_authored_colors.dart';

void main() {
  test(
    'pastel pink green blue and orange remain distinct on warm and dark paper',
    () {
      const originals = [
        Color(0xfffefafb),
        Color(0xfff2faef),
        Color(0xfff6fbff),
        Color(0xfffff4e8),
      ];
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final colors = ReaderAuthoredColors(
          readerTheme(ReaderSettings(paper: ReaderPaper.warm), brightness),
        );
        final result = originals
            .map((c) => colors.resolve(c, ReaderColorRole.background))
            .toList();
        expect(result.map((c) => c.toARGB32()).toSet(), hasLength(4));
        // Pairwise separation must survive 8-bit output, not merely float rounding.
        for (var i = 0; i < result.length; i++) {
          for (var j = i + 1; j < result.length; j++) {
            final a = result[i], b = result[j];
            final distance =
                ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) *
                255;
            expect(distance, greaterThan(10));
            final authoredRG =
                originals[i].r -
                originals[i].g -
                originals[j].r +
                originals[j].g;
            final renderedRG = a.r - a.g - b.r + b.g;
            expect(renderedRG, closeTo(authoredRG * 1.25, .005));
          }
        }
      }
    },
  );
  test(
    'near-white backgrounds adapt to paper while colored surfaces survive',
    () {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final paper in ReaderPaper.values) {
          final theme = readerTheme(ReaderSettings(paper: paper), brightness);
          final resolver = ReaderAuthoredColors(theme);
          for (final argb in [0xffffffff, 0xfffefafb, 0xfff6fbff, 0xfffafafa]) {
            final authored = Color(argb);
            final surface = resolver.resolve(
              authored,
              ReaderColorRole.background,
            );
            if (brightness == Brightness.dark || paper == ReaderPaper.warm) {
              expect(surface, isNot(authored));
            } else {
              expect(surface, authored);
            }
            final foreground = resolver.resolve(
              Colors.black,
              ReaderColorRole.foreground,
              background: surface,
            );
            expect(
              readerColorContrast(foreground, surface),
              greaterThanOrEqualTo(4.5),
            );
            if (brightness == Brightness.dark) {
              expect(surface.computeLuminance(), lessThan(.1));
            }
          }
          for (final argb in [0xffffdd00, 0xffe95283, 0xff905ca3]) {
            expect(
              resolver.resolve(Color(argb), ReaderColorRole.background),
              Color(argb),
            );
          }
        }
      }
    },
  );
  test('dark foreground corrections keep hue and borders remain visible', () {
    final theme = readerTheme(ReaderSettings(), Brightness.dark);
    final resolver = ReaderAuthoredColors(theme);
    final surface = resolver.resolve(
      const Color(0xfffefafb),
      ReaderColorRole.background,
    );
    for (final color in [
      const Color(0xff9161a4),
      const Color(0xff75b637),
      const Color(0xffe95283),
    ]) {
      final ink = resolver.resolve(
        color,
        ReaderColorRole.foreground,
        background: surface,
      );
      expect(readerColorContrast(ink, surface), greaterThanOrEqualTo(4.49));
      expect(
        HSLColor.fromColor(ink).hue,
        closeTo(HSLColor.fromColor(color).hue, 1),
      );
    }
    final border = resolver.resolve(
      const Color(0xffdccedf),
      ReaderColorRole.border,
      background: surface,
    );
    expect(readerColorContrast(border, surface), greaterThanOrEqualTo(1.49));
    final yellow = resolver.resolve(
      const Color(0xffffdd00),
      ReaderColorRole.background,
    );
    expect(
      readerColorContrast(
        resolver.resolve(
          Colors.white,
          ReaderColorRole.foreground,
          background: yellow,
        ),
        yellow,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });
}
