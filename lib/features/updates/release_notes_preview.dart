import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../app/theme/shiori_theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Release text stays inert in both the preview and expanded view.
class ReleaseNotesPreview extends StatefulWidget {
  const ReleaseNotesPreview({super.key, required this.notes});

  final String notes;

  @override
  State<ReleaseNotesPreview> createState() => _ReleaseNotesPreviewState();
}

class _ReleaseNotesPreviewState extends State<ReleaseNotesPreview> {
  final _content = GlobalKey();
  bool _expanded = false;
  bool _overflows = false;

  @override
  void didUpdateWidget(ReleaseNotesPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notes != widget.notes) {
      _expanded = false;
      _overflows = false;
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (!_expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          duration: ShioriMotion.of(context, ShioriMotion.feedback),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final heading = theme.textTheme.titleSmall;
    final previewHeight = 220 * MediaQuery.textScalerOf(context).scale(14) / 14;
    final preview = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: _expanded ? double.infinity : previewHeight,
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: AlignmentDirectional.topStart,
          fit: OverflowBoxFit.deferToChild,
          maxHeight: double.infinity,
          child: IgnorePointer(
            key: _content,
            child: MarkdownBody(
              data: widget.notes.trim(),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure the actual Markdown layout, including lists and tables, rather
        // than guessing from character count. Recheck when width or text changes.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final height = _content.currentContext!.size!.height;
          final overflows = height > previewHeight;
          if (overflows != _overflows) setState(() => _overflows = overflows);
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_expanded && _overflows)
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) =>
                    const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.transparent],
                    ).createShader(
                      Rect.fromLTRB(
                        0,
                        bounds.height - ShioriSpace.section,
                        bounds.width,
                        bounds.height,
                      ),
                    ),
                child: preview,
              )
            else
              preview,
            if (_overflows) ...[
              const SizedBox(height: ShioriSpace.small),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              Semantics(
                expanded: _expanded,
                child: TextButton.icon(
                  key: const ValueKey('update-notes-toggle'),
                  onPressed: _toggle,
                  iconAlignment: IconAlignment.end,
                  icon: AnimatedRotation(
                    turns: _expanded ? .5 : 0,
                    duration: ShioriMotion.of(context, ShioriMotion.feedback),
                    child: const Icon(Icons.keyboard_arrow_down, size: 18),
                  ),
                  label: Text(
                    _expanded ? l.updateCollapseNotes : l.updateExpandNotes,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
