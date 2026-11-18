import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';

/// Equal-width choices with a single raised selection. The page owns the
/// selected value, the control width and its alignment.
class ShioriSegmentedControl extends StatelessWidget {
  const ShioriSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    assert(
      labels.length >= 2 && selectedIndex >= 0 && selectedIndex < labels.length,
    );
    final theme = Theme.of(context), colors = theme.colorScheme;
    const inset = 3.0;
    final radius = BorderRadius.circular(ShioriShape.control - inset);
    final selectedColor = theme.brightness == Brightness.dark
        ? Color.lerp(colors.surface, colors.onSurface, .14)!
        : colors.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(ShioriShape.control),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(inset),
              child: AnimatedAlign(
                duration: ShioriMotion.of(context, ShioriMotion.transition),
                curve: Curves.easeOut,
                alignment: AlignmentDirectional(
                  -1 + 2 * selectedIndex / (labels.length - 1),
                  0,
                ),
                child: FractionallySizedBox(
                  widthFactor: 1 / labels.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selectedColor,
                      borderRadius: radius,
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: .08),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: i == selectedIndex,
                      child: TextButton(
                        onPressed: onChanged == null
                            ? null
                            : () => onChanged!(i),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.standard,
                          minimumSize: const Size(0, kMinInteractiveDimension),
                          padding: const EdgeInsets.symmetric(
                            horizontal: ShioriSpace.tight,
                            vertical: ShioriSpace.small,
                          ),
                          foregroundColor: i == selectedIndex
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                          textStyle: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: i == selectedIndex
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: radius),
                        ),
                        child: Text(labels[i], textAlign: TextAlign.center),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
