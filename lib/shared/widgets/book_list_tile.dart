import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';

/// Row content shared by book lists: cover, up to two title lines, an
/// optional subtitle, bottom metadata and a trailing action aligned with the
/// title. Hosts own the interactive shell (tap, swipe, dividers).
class BookListTile extends StatelessWidget {
  const BookListTile({
    super.key,
    required this.cover,
    required this.title,
    this.subtitle,
    this.metadata,
    this.trailing,
  });

  /// Rendered in a 2:3 slot, 64 logical pixels wide.
  final Widget cover;
  final String title;
  final String? subtitle, metadata;
  final Widget? trailing;

  static const coverWidth = 64.0;
  static const coverHeight = coverWidth / ShioriShape.coverRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: coverWidth, height: coverHeight, child: cover),
        const SizedBox(width: ShioriSpace.item),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: coverHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: ShioriMotion.of(context, ShioriMotion.feedback),
                      style: (theme.textTheme.titleSmall ?? const TextStyle())
                          .copyWith(
                            height: 1.4,
                            color: _TitleTint.of(context)
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (subtitle case final subtitle?) ...[
                      const SizedBox(height: ShioriSpace.tight),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: secondary,
                      ),
                    ],
                  ],
                ),
                if (metadata case final metadata? when metadata.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: ShioriSpace.small),
                    child: Text(metadata, style: secondary),
                  ),
              ],
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Tappable list row shell shared by book lists.
///
/// Interaction states are drawn as a rounded, inset accent tint rather than
/// Material's edge-to-edge grey overlay: hover and focus tint lightly and
/// lift the title colour, press tints a little more, keyboard focus adds a
/// thin accent outline. [inset] is the horizontal room between the tint's
/// edge and the content, so hosts keep their gutter by subtracting it.
class BookListItem extends StatefulWidget {
  const BookListItem({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.focusNode,
    this.minHeight = 120,
  });
  final Widget child;
  final VoidCallback? onTap, onLongPress;

  /// A right click, e.g. for a context menu at the pointer.
  final GestureTapUpCallback? onSecondaryTapUp;
  final FocusNode? focusNode;
  final double minHeight;

  static const inset = ShioriSpace.medium;

  /// Whether the row around [context] is hovered, focused or pressed, for
  /// content that tints itself like [BookListTile]'s title.
  static bool activeOf(BuildContext context) => _TitleTint.of(context);

  @override
  State<BookListItem> createState() => _BookListItemState();
}

class _BookListItemState extends State<BookListItem> {
  bool _hovered = false, _pressed = false, _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = _hovered || _focused || _pressed;
    final radius = BorderRadius.circular(ShioriShape.control);
    final duration = ShioriMotion.of(context, ShioriMotion.feedback);
    final tint = colors.primary.withValues(
      alpha: _pressed ? .12 : (active ? .06 : 0),
    );
    // Opaque paper keeps swipe actions hidden behind the row at rest.
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        focusNode: widget.focusNode,
        onHover: (value) => setState(() => _hovered = value),
        onHighlightChanged: (value) => setState(() => _pressed = value),
        onFocusChange: (value) => setState(() => _focused = value),
        borderRadius: radius,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: BookListItem.inset),
          decoration: BoxDecoration(color: tint, borderRadius: radius),
          // The focus ring paints over the row so it never shifts layout.
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: _focused
                  ? colors.primary.withValues(alpha: .6)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Container(
            constraints: BoxConstraints(minHeight: widget.minHeight),
            padding: const EdgeInsets.symmetric(vertical: ShioriSpace.medium),
            decoration: BoxDecoration(
              border: Border(
                // The hairline yields to the tint so a highlighted row reads
                // as one surface.
                bottom: BorderSide(
                  color: active
                      ? Colors.transparent
                      : colors.outlineVariant.withValues(alpha: .45),
                ),
              ),
            ),
            child: _TitleTint(active: active, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Lets [BookListTile] colour its title for an active row.
class _TitleTint extends InheritedWidget {
  const _TitleTint({required this.active, required super.child});
  final bool active;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TitleTint>()?.active ?? false;
  @override
  bool updateShouldNotify(_TitleTint old) => old.active != active;
}
