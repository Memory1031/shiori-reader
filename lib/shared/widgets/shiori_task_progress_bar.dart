import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';

/// Compact task feedback; unknown work never exposes a percentage.
class ShioriTaskProgressBar extends StatelessWidget {
  const ShioriTaskProgressBar({super.key, this.value, this.semanticsLabel});
  final double? value;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(ShioriShape.indicator);
    if (value == null && MediaQuery.disableAnimationsOf(context)) {
      return Semantics(
        label: semanticsLabel,
        child: SizedBox(
          height: ShioriSpace.tight,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  borderRadius: radius,
                ),
              ),
              FractionallySizedBox(
                widthFactor: 1 / 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: radius,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return LinearProgressIndicator(
      value: value,
      semanticsLabel: semanticsLabel,
      minHeight: ShioriSpace.tight,
      borderRadius: radius,
      color: colors.primary,
      backgroundColor: colors.outlineVariant,
    );
  }
}
