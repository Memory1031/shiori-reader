import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import 'reader_chrome.dart';

/// Overflow menu entries of the reader top bar.
enum ReaderMenuAction {
  links,
  prefetch,
  details,
  retrySave,
  retrySettings,
  hideControls,
}

/// Title row with back / return and the overflow menu. Placement agnostic:
/// it fills whatever box its host gives it.
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.title,
    required this.onLeave,
    required this.menu,
    required this.onMenu,
    this.returnToOrigin = false,
  });
  final String title;
  final VoidCallback onLeave;

  /// A linked (auxiliary) reader returns to its origin instead of going back.
  final bool returnToOrigin;
  final List<(ReaderMenuAction, String)> menu;
  final ValueChanged<ReaderMenuAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        if (returnToOrigin)
          TextButton(onPressed: onLeave, child: Text(l.readerLinkReturn))
        else
          BackButton(onPressed: onLeave),
        Expanded(
          child: Tooltip(
            message: title,
            child: Text(
              title,
              key: const ValueKey('reader-chapter-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        PopupMenuButton<ReaderMenuAction>(
          tooltip: l.moreActions,
          icon: const Icon(Icons.more_horiz),
          onSelected: onMenu,
          itemBuilder: (_) => [
            for (final (action, label) in menu)
              PopupMenuItem(value: action, child: Text(label)),
          ],
        ),
      ],
    );
  }
}

/// Contents, progress and typography entry points.
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.contentsTooltip,
    required this.onContents,
    required this.progress,
    required this.onProgress,
    required this.onSettings,
  });
  final String contentsTooltip;
  final VoidCallback onContents, onProgress, onSettings;

  /// Live chapter progress label.
  final Widget progress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: contentsTooltip,
            child: TextButton.icon(
              onPressed: onContents,
              icon: const Icon(Icons.list, size: 20),
              label: Text(l.catalogTitle),
            ),
          ),
        ),
        Expanded(
          child: TextButton(onPressed: onProgress, child: progress),
        ),
        Expanded(
          child: Tooltip(
            message: l.readerSettings,
            child: TextButton(
              onPressed: onSettings,
              child: Text('Aa', semanticsLabel: l.readerSettings),
            ),
          ),
        ),
      ],
    );
  }
}

/// Overlays both bars on the page, bleeding into [insets] so each reads as
/// one surface with the system area it covers.
class ReaderToolbars extends StatelessWidget {
  const ReaderToolbars({
    super.key,
    required this.metrics,
    required this.insets,
    required this.top,
    required this.bottom,
  });
  final ReaderChromeMetrics metrics;
  final EdgeInsets insets;
  final Widget top, bottom;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(
        top: -insets.top,
        left: -insets.left,
        right: -insets.right,
        height: insets.top + metrics.topBar,
        child: ReaderToolbarSurface(
          edge: VerticalDirection.down,
          padding: EdgeInsets.fromLTRB(
            insets.left,
            insets.top,
            insets.right,
            0,
          ),
          child: top,
        ),
      ),
      Positioned(
        bottom: -insets.bottom,
        left: -insets.left,
        right: -insets.right,
        height: insets.bottom + metrics.bottomBar,
        child: ReaderToolbarSurface(
          edge: VerticalDirection.up,
          padding: EdgeInsets.fromLTRB(
            insets.left,
            0,
            insets.right,
            insets.bottom,
          ),
          child: bottom,
        ),
      ),
    ],
  );
}

/// Running header and footer shown while the toolbars are hidden. With the
/// system bars hidden ([statusRow]) the footer carries clock and battery.
class ReaderRunningChrome extends StatelessWidget {
  const ReaderRunningChrome({
    super.key,
    required this.metrics,
    required this.margin,
    required this.title,
    required this.progress,
    required this.statusRow,
  });
  final ReaderChromeMetrics metrics;

  /// Horizontal page margin, so both lines align with the text column.
  final double margin;
  final String title;
  final Widget progress;
  final bool statusRow;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: margin,
            right: margin,
            height: metrics.header,
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: margin,
            right: margin,
            height: metrics.footer,
            child: Center(
              child: statusRow ? ReaderStatusRow(progress: progress) : progress,
            ),
          ),
        ],
      ),
    );
  }
}

/// First-use explanation of the tap zones.
class ReaderControlsHint extends StatelessWidget {
  const ReaderControlsHint({super.key, required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(ShioriShape.control),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .4,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(ShioriSpace.item),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.readerControlsHint),
                TextButton(onPressed: onDismiss, child: Text(l.readerGotIt)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
