import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/reader/reading_progress_format.dart';

void main() {
  test('reading percentage truncates rather than rounding up', () {
    expect(formatReadingPercent(.267899), '26.78');
    expect(formatReadingPercent(.9999999999999999), '99.99');
    expect(formatReadingPercent(.00009999999999999), '0.00');
    expect(formatReadingPercent(1e-9), '0.00');
    expect(formatReadingPercent(-.1), '0.00');
    expect(formatReadingPercent(1.1), '100.00');
  });

  test('all exact hundredth-percent boundaries keep both decimal places', () {
    for (var i = 0; i <= 10000; i++) {
      final expected = '${i ~/ 100}.${(i % 100).toString().padLeft(2, '0')}';
      expect(formatReadingPercent(i / 10000), expected, reason: '$i / 10000');
    }
  });
}
