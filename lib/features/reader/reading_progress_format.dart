/// Whole percentage digits for reading UI, truncated (without `%`), so a
/// position never reads further along than it is and only the end reads
/// 100. Progress itself keeps full precision; only its display is rounded.
String formatReadingPercent(double fraction) {
  if (fraction.isNaN || fraction < .01) return '0';
  if (fraction >= 1) return '100';

  // In this range toString uses decimal notation. Read the digits instead of
  // multiplying and flooring: e.g. .29 * 100 is 28.999999999999996.
  final digits = fraction.toString().split('.')[1].padRight(2, '0');
  return int.parse(digits.substring(0, 2)).toString();
}
