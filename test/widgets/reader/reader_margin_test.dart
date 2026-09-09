import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_margin.dart';

void main() {
  test(
    'medium remains 30 and adjacent tiers change one cell of line width',
    () {
      for (final scale in [1.0, 1.5]) {
        final margins = [
          for (final value in readerMarginValues)
            readerHorizontalMargin(
              ReaderSettings(horizontalPadding: value),
              TextScaler.linear(scale),
              TextDirection.ltr,
            ),
        ];
        expect(margins[2], 30);
        for (var i = 1; i < margins.length; i++) {
          expect(margins[i], greaterThan(margins[i - 1]));
          expect(margins[i] - margins[i - 1], closeTo(10 * scale, .001));
        }
        expect(readerMarginTier(40), 3);
        expect(readerMarginTier(30), 2);
      }
    },
  );
}
