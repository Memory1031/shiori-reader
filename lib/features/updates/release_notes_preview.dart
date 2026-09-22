import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Inert, bounded release notes. Full notes and navigation belong to the
/// separately validated release-page action, not URLs inside the release body.
class ReleaseNotesPreview extends StatelessWidget {
  const ReleaseNotesPreview({super.key, required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleSmall;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: 220 * MediaQuery.textScalerOf(context).scale(14) / 14,
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          fit: OverflowBoxFit.deferToChild,
          maxHeight: double.infinity,
          child: IgnorePointer(
            child: MarkdownBody(
              data: notes.trim(),
              fitContent: false,
              // Override every image source, including files and assets. Never
              // let unsigned release text reach the default image loader.
              imageBuilder: (_, _, _) => const SizedBox.shrink(),
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyMedium,
                h1: heading,
                h2: heading,
                h3: heading,
                h4: heading,
                h5: heading,
                h6: heading,
                a: theme.textTheme.bodyMedium,
                blockSpacing: 8,
                listIndent: 18,
                code: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
