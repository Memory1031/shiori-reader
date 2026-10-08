import 'package:characters/characters.dart';
import 'value_model.dart';

/// Two authored text rows, separated by a retained source newline. Layout only:
/// offsets use code points and never replace or reorder the paragraph text.
final class InlineStack extends ValueModel {
  InlineStack({
    required this.start,
    required this.length,
    required this.separator,
    this.upperLineHeightEm,
    this.lowerLineHeightEm,
    this.upperLineHeightBasisEm = 1,
    this.lowerLineHeightBasisEm = 1,
  }) {
    if (start < 0 ||
        length < 3 ||
        length > 512 ||
        separator <= start ||
        separator >= end - 1 ||
        separator - start > 256 ||
        end - separator - 1 > 256 ||
        [
          upperLineHeightEm,
          lowerLineHeightEm,
        ].any((v) => v != null && (!v.isFinite || v <= 0 || v > 8)) ||
        [
          upperLineHeightBasisEm,
          lowerLineHeightBasisEm,
        ].any((v) => !v.isFinite || v < .25 || v > 4)) {
      throw ArgumentError('Invalid inline stack');
    }
  }
  final int start, length, separator;
  final double? upperLineHeightEm, lowerLineHeightEm;
  // Scale the computed length through its font basis, not as a font size.
  final double upperLineHeightBasisEm, lowerLineHeightBasisEm;
  int get end => start + length;
  Map<String, Object?> toJson() => {
    'start': start,
    'length': length,
    'separator': separator,
    if (upperLineHeightEm != null) 'upperLineHeightEm': upperLineHeightEm,
    if (lowerLineHeightEm != null) 'lowerLineHeightEm': lowerLineHeightEm,
    if (upperLineHeightBasisEm != 1)
      'upperLineHeightBasisEm': upperLineHeightBasisEm,
    if (lowerLineHeightBasisEm != 1)
      'lowerLineHeightBasisEm': lowerLineHeightBasisEm,
  };
  factory InlineStack.fromJson(Map<String, dynamic> json) => InlineStack(
    start: json['start'] as int,
    length: json['length'] as int,
    separator: json['separator'] as int,
    upperLineHeightEm: (json['upperLineHeightEm'] as num?)?.toDouble(),
    lowerLineHeightEm: (json['lowerLineHeightEm'] as num?)?.toDouble(),
    upperLineHeightBasisEm:
        (json['upperLineHeightBasisEm'] as num?)?.toDouble() ?? 1,
    lowerLineHeightBasisEm:
        (json['lowerLineHeightBasisEm'] as num?)?.toDouble() ?? 1,
  );
  @override
  List<Object?> get values => [
    start,
    length,
    separator,
    upperLineHeightEm,
    lowerLineHeightEm,
    upperLineHeightBasisEm,
    lowerLineHeightBasisEm,
  ];
}

void validateInlineStacks(
  String text,
  List<InlineStack> stacks,
  Iterable<(int, int)> otherAtoms,
) {
  if (stacks.isEmpty) return;
  if (stacks.length > 64) throw ArgumentError('Too many inline stacks');
  final runes = text.runes.toList();
  final boundaries = <int>{0};
  var at = 0;
  for (final g in text.characters) {
    at += g.runes.length;
    boundaries.add(at);
  }
  var end = 0;
  for (final s in stacks) {
    if (s.start < end ||
        s.end > runes.length ||
        ![
          s.start,
          s.separator,
          s.separator + 1,
          s.end,
        ].every(boundaries.contains) ||
        runes[s.separator] != 10 ||
        runes.sublist(s.start, s.end).where((r) => r == 10).length != 1 ||
        runes.sublist(s.start, s.end).contains(0xfffc) ||
        String.fromCharCodes(
          runes.sublist(s.start, s.separator),
        ).trim().isEmpty ||
        String.fromCharCodes(
          runes.sublist(s.separator + 1, s.end),
        ).trim().isEmpty ||
        otherAtoms.any((a) => a.$1 < s.end && s.start < a.$2)) {
      throw ArgumentError(
        'Inline stacks must reference disjoint complete text rows',
      );
    }
    end = s.end;
  }
}
