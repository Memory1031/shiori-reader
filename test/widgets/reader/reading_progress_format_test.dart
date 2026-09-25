import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/reader/reading_progress_format.dart';

void main() {
  test('reading percentage truncates to a whole number', () {
    expect(formatReadingPercent(.267899), '26');
    expect(formatReadingPercent(.9999999999999999), '99');
    expect(formatReadingPercent(.00999999999999), '0');
    expect(formatReadingPercent(1e-9), '0');
    expect(formatReadingPercent(-.1), '0');
    expect(formatReadingPercent(double.nan), '0');
    expect(formatReadingPercent(1), '100');
    expect(formatReadingPercent(1.1), '100');
  });

  test('exact percent boundaries are not lost to float error', () {
    for (var i = 0; i <= 100; i++) {
      expect(formatReadingPercent(i / 100), '$i', reason: '$i / 100');
    }
    // Just below a boundary stays on the lower whole number.
    for (var i = 1; i <= 100; i++) {
      expect(
        formatReadingPercent(i / 100 - 1e-9),
        '${i - 1}',
        reason: '$i / 100 - ε',
      );
    }
  });
}
