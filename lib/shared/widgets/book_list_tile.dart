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
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(height: 1.4),
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
