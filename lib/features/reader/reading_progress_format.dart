/// Percentage digits for reading UI, truncated to two decimals (without `%`).
String formatReadingPercent(double fraction) {
  if (fraction.isNaN || fraction < .0001) return '0.00';
  if (fraction >= 1) return '100.00';

  // In this range toString uses decimal notation. Truncate those digits instead
  // of multiplying/flooring: e.g. .0003 * 10000 can be 2.9999999999999996.
  final digits = fraction.toString().split('.')[1].padRight(4, '0');
  final whole = int.parse(digits.substring(0, 2));
  return '$whole.${digits.substring(2, 4)}';
}
