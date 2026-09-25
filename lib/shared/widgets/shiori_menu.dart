import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../capabilities.dart';

/// A popup menu entry with an optional leading icon.
///
/// Its hover, focus and press tint is inset from the menu's edge and
/// rounded like the list rows', rather than Material's edge-to-edge band;
/// the entry is otherwise a [PopupMenuItem], so selection, keyboard use and
/// semantics are unchanged. Entries are compact where a pointer is the
/// primary input and keep the touch target height elsewhere.
class ShioriMenuItem<T> extends PopupMenuEntry<T> {
  const ShioriMenuItem({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool enabled;

  /// The entry's height where a pointer is the primary input.
  static const compactHeight = 36.0;

  /// Room between the tint and the menu's edge.
  static const inset = ShioriSpace.tight;

  // Only used to align an initial value, which no Shiori menu passes.
  @override
  double get height => kMinInteractiveDimension;

  @override
  bool represents(T? value) => value == this.value;

  @override
  State<ShioriMenuItem<T>> createState() => _ShioriMenuItemState<T>();
}

class _ShioriMenuItemState<T> extends State<ShioriMenuItem<T>> {
  @override
  Widget build(BuildContext context) {
    final compact = ShioriCapabilities.of(context).pointerFirst;
    final icon = widget.icon;
    final label = Text(widget.label);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ShioriMenuItem.inset),
      // The item's ink lands on this clipped surface, concentric with the
      // menu's corners.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(
          ShioriShape.control - ShioriMenuItem.inset,
        ),
        clipBehavior: Clip.antiAlias,
        child: PopupMenuItem<T>(
          value: widget.value,
          enabled: widget.enabled,
          height: compact
              ? ShioriMenuItem.compactHeight
              : kMinInteractiveDimension,
          padding: const EdgeInsets.symmetric(horizontal: ShioriSpace.medium),
          child: icon == null
              ? label
              : Row(
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: ShioriSpace.medium),
                    Flexible(child: label),
                  ],
                ),
        ),
      ),
    );
  }
}
