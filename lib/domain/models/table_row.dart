import 'value_model.dart';

/// Bounded native two-cell row geometry. Offsets are source code points;
/// neither these dimensions nor the group participate in content identity.
final class TableRowLayout extends ValueModel {
  TableRowLayout({
    required this.group,
    required this.leftEnd,
    required this.rightStart,
    required this.leftWidthEm,
    required this.leftPaddingEm,
    required this.rightPaddingEm,
    required this.dividerWidth,
    required this.dividerColor,
    this.gapAfterEm = 0,
  }) {
    nonNegative(group, 'table group');
    if (leftEnd < 1 ||
        leftEnd > 64 ||
        rightStart < leftEnd ||
        rightStart > 128) {
      throw ArgumentError('Invalid cell ranges');
    }
    finiteRange(leftWidthEm, .25, 12, 'left width');
    finiteRange(leftPaddingEm, 0, 4, 'left padding');
    finiteRange(rightPaddingEm, 0, 4, 'right padding');
    finiteRange(dividerWidth, 0, 4, 'divider width');
    finiteRange(gapAfterEm, 0, 4, 'row gap');
    if (dividerColor < 0 || dividerColor > 0xffffffff) {
      throw ArgumentError('Invalid divider color');
    }
  }
  final int group, leftEnd, rightStart, dividerColor;
  final double leftWidthEm,
      leftPaddingEm,
      rightPaddingEm,
      dividerWidth,
      gapAfterEm;
  TableRowLayout withGap(double gap) => TableRowLayout(
    group: group,
    leftEnd: leftEnd,
    rightStart: rightStart,
    leftWidthEm: leftWidthEm,
    leftPaddingEm: leftPaddingEm,
    rightPaddingEm: rightPaddingEm,
    dividerWidth: dividerWidth,
    dividerColor: dividerColor,
    gapAfterEm: gap,
  );
  factory TableRowLayout.fromJson(Map<String, Object?> json) => TableRowLayout(
    group: json['group'] as int,
    leftEnd: json['leftEnd'] as int,
    rightStart: json['rightStart'] as int,
    leftWidthEm: (json['leftWidthEm'] as num).toDouble(),
    leftPaddingEm: (json['leftPaddingEm'] as num).toDouble(),
    rightPaddingEm: (json['rightPaddingEm'] as num).toDouble(),
    dividerWidth: (json['dividerWidth'] as num).toDouble(),
    dividerColor: json['dividerColor'] as int,
    gapAfterEm: (json['gapAfterEm'] as num?)?.toDouble() ?? 0,
  );
  Map<String, Object?> toJson() => {
    'group': group,
    'leftEnd': leftEnd,
    'rightStart': rightStart,
    'leftWidthEm': leftWidthEm,
    'leftPaddingEm': leftPaddingEm,
    'rightPaddingEm': rightPaddingEm,
    'dividerWidth': dividerWidth,
    'dividerColor': dividerColor,
    'gapAfterEm': gapAfterEm,
  };
  @override
  List<Object?> get values => [
    group,
    leftEnd,
    rightStart,
    leftWidthEm,
    leftPaddingEm,
    rightPaddingEm,
    dividerWidth,
    dividerColor,
    gapAfterEm,
  ];
}
