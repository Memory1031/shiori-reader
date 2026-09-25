import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/shiori_menu.dart';
import 'reader_chrome.dart';
import 'reader_commands.dart';

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
  final List<(ReaderCommand, String)> menu;
  final ValueChanged<ReaderCommand> onMenu;

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
        PopupMenuButton<ReaderCommand>(
          tooltip: l.moreActions,
          icon: const Icon(Icons.more_horiz),
          onSelected: onMenu,
          itemBuilder: (_) => [
            for (final (action, label) in menu)
              ShioriMenuItem(value: action, label: label),
          ],
        ),
      ],
    );
  }
}

/// Contents, progress and typography entry points.
///
/// Phones and tablets spread the three across the bar. Where a pointer is
/// the primary input they sit together in the middle at their own widths,
/// and their tooltips name their shortcuts.
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.contentsTooltip,
    required this.onContents,
    required this.progress,
    required this.onProgress,
    required this.onSettings,
    this.progressKey,
  });
  final String contentsTooltip;

  /// Null while the command is unavailable.
  final VoidCallback? onContents, onProgress, onSettings;

  /// Live chapter progress label.
  final Widget progress;

  /// Keys the progress control, so a popover can find it wherever the bar
  /// lays it out.
  final GlobalKey? progressKey;

  /// Least widths of the grouped controls, so the group keeps its shape as
  /// the percentage changes. Longer labels and larger text widen them.
  static const contentsWidth = 96.0;
  static const progressWidth = 120.0;
  static const settingsWidth = 48.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final grouped = ShioriCapabilities.of(context).pointerFirst;
    String tip(String action, String shortcut) =>
        grouped ? l.readerShortcutTooltip(action, shortcut) : action;
    final contents = Tooltip(
      message: tip(contentsTooltip, ReaderShortcutLabels.contents),
      child: TextButton.icon(
        onPressed: onContents,
        icon: const Icon(Icons.list, size: 20),
        label: Text(l.catalogTitle),
      ),
    );
    final progress = TextButton(
      key: progressKey,
      onPressed: onProgress,
      child: this.progress,
    );
    final settings = Tooltip(
      message: tip(l.readerSettings, ReaderShortcutLabels.settings),
      child: TextButton(
        onPressed: onSettings,
        child: Text('Aa', semanticsLabel: l.readerSettings),
      ),
    );
    if (!grouped) {
      return Row(
        children: [
          Expanded(child: contents),
          Expanded(child: progress),
          Expanded(child: settings),
        ],
      );
    }
    Widget least(double width, Widget child) => ConstrainedBox(
      constraints: BoxConstraints(minWidth: width),
      child: child,
    );
    // Too narrow for the group at a large text size, it scrolls rather
    // than clipping or shrinking its labels.
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: ShioriSpace.small),
        child: Row(
          key: const ValueKey('reader-bottom-group'),
          mainAxisSize: MainAxisSize.min,
          children: [
            least(contentsWidth, contents),
            const SizedBox(width: ShioriSpace.small),
            least(
              progressWidth,
              Tooltip(
                message: tip(
                  l.readerProgressLabel,
                  ReaderShortcutLabels.progress,
                ),
                child: progress,
              ),
            ),
            const SizedBox(width: ShioriSpace.small),
            least(settingsWidth, settings),
          ],
        ),
      ),
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
            child: Padding(
              padding: const EdgeInsets.only(
                top: ReaderChromeMetrics.edge,
                bottom: ReaderChromeMetrics.inner,
              ),
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
          ),
          Positioned(
            bottom: 0,
            left: margin,
            right: margin,
            height: metrics.footer,
            child: Padding(
              padding: const EdgeInsets.only(
                top: ReaderChromeMetrics.inner,
                bottom: ReaderChromeMetrics.edge,
              ),
              child: Center(
                child: statusRow
                    ? ReaderStatusRow(progress: progress)
                    : progress,
              ),
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
