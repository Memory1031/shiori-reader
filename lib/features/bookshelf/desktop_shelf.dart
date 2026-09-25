import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/shiori_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_list_tile.dart';

/// Columns and card width for the desktop shelf grid in [width].
///
/// Columns are added as the frame widens instead of stretching covers: a
/// card never drops below [minCard] (unless one column is all that fits)
/// or grows past [maxCard], and the grid stays left-aligned when capped.
/// Text size scales covers only up to [maxDensityScale]; titles keep the
/// full text scale.
({int columns, double card, double extent}) desktopShelfGrid(
  double width,
  TextScaler scaler,
) {
  final scale = (scaler.scale(15) / 15).clamp(1.0, maxDensityScale);
  final min = minCard * scale;
  final columns = math.max(1, ((width + gap) / (min + gap)).floor());
  final card = math.max(
    0.0,
    math.min((width - (columns - 1) * gap) / columns, maxCard * scale),
  );
  return (
    columns: columns,
    card: card,
    extent: columns * card + (columns - 1) * gap,
  );
}

const minCard = 132.0, maxCard = 168.0, gap = 20.0, rowGap = 24.0;
const maxDensityScale = 1.3;

/// The shelf frame's inset from the workspace edge for a window [width].
double desktopShelfGutter(double width) =>
    width >= ShioriLayout.sidebarBreakpoint
    ? ShioriLayout.shelfGutterWide
    : ShioriLayout.shelfGutter;

/// Opens a book menu from the Menu key or Shift+F10 while [child] or a
/// descendant has focus.
class ShelfMenuShortcuts extends StatelessWidget {
  const ShelfMenuShortcuts({
    super.key,
    required this.onMenu,
    required this.child,
  });
  final VoidCallback onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.contextMenu): _MenuIntent(),
      SingleActivator(LogicalKeyboardKey.f10, shift: true): _MenuIntent(),
    },
    child: Actions(
      actions: {
        _MenuIntent: CallbackAction<_MenuIntent>(onInvoke: (_) => onMenu()),
      },
      child: child,
    ),
  );
}

class _MenuIntent extends Intent {
  const _MenuIntent();
}

/// Whether a book menu that resolves [dismissed] closed from the keyboard,
/// so focus goes back to its book. The answer starts from how the menu was
/// opened ([keyboard]) and each key or pointer press while it is open takes
/// over: Escape returns focus, while clicking outside leaves focus alone so
/// the book doesn't keep a focus ring the pointer never asked for.
Future<bool> menuClosedFromKeyboard(
  Future<bool> dismissed, {
  required bool keyboard,
}) async {
  var fromKeyboard = keyboard;
  bool onKey(KeyEvent event) {
    if (event is KeyDownEvent) fromKeyboard = true;
    return false;
  }

  void onPointer(PointerEvent event) {
    if (event is PointerDownEvent) fromKeyboard = false;
  }

  HardwareKeyboard.instance.addHandler(onKey);
  GestureBinding.instance.pointerRouter.addGlobalRoute(onPointer);
  try {
    return await dismissed && fromKeyboard;
  } finally {
    HardwareKeyboard.instance.removeHandler(onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(onPointer);
  }
}

/// Grid or list as two segments sharing the host layout choice.
class ShelfLayoutToggle extends StatelessWidget {
  const ShelfLayoutToggle({super.key, required this.layout});
  final ValueNotifier<bool> layout;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: layout,
      builder: (context, grid, _) => SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: true,
            icon: const Icon(Icons.grid_view_rounded),
            tooltip: strings.shelfGrid,
          ),
          ButtonSegment(
            value: false,
            icon: const Icon(Icons.view_list_rounded),
            tooltip: strings.shelfList,
          ),
        ],
        selected: {grid},
        showSelectedIcon: false,
        onSelectionChanged: (value) => layout.value = value.first,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: ShioriSpace.medium),
          ),
        ),
      ),
    );
  }
}

/// The fixed shelf title bar, laid out on the shelf frame.
class DesktopShelfToolbar extends StatelessWidget {
  const DesktopShelfToolbar({
    super.key,
    required this.layout,
    this.count,
    this.onImport,
  });
  final ValueNotifier<bool> layout;

  /// Omitted until the shelf has books to count.
  final int? count;
  final VoidCallback? onImport;

  /// Below this frame width the import action drops its label.
  static const labelledImport = 520.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.only(
          top: ShioriSpace.item,
          bottom: ShioriSpace.medium,
        ),
        child: LayoutBuilder(
          builder: (context, bounds) => Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(
                          strings.homeShelf,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ),
                    if (count case final count?) ...[
                      const SizedBox(width: ShioriSpace.medium),
                      Text(
                        strings.shelfBookCount(count),
                        maxLines: 1,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: ShioriSpace.item),
              ShelfLayoutToggle(layout: layout),
              if (onImport case final onImport?) ...[
                const SizedBox(width: ShioriSpace.medium),
                if (bounds.maxWidth < labelledImport)
                  IconButton(
                    onPressed: onImport,
                    tooltip: strings.importTitle,
                    icon: const Icon(Icons.file_upload_outlined),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.file_upload_outlined, size: 20),
                    label: Text(strings.importTitle),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A desktop shelf list row: title and author, then source and progress
/// columns while they fit, moving below the text once space or text size
/// runs out. Rows grow rather than clip.
class DesktopBookRow extends StatefulWidget {
  const DesktopBookRow({
    super.key,
    required this.cover,
    required this.title,
    required this.onTap,
    required this.onMenu,
    this.subtitle,
    this.sourceLabel,
    this.progressLabel,
    this.progress,
    this.moreKey,
  });

  final Widget cover;
  final String title;
  final String? subtitle, sourceLabel, progressLabel;

  /// Fraction read, drawn as a bar under [progressLabel] when known.
  final double? progress;
  final VoidCallback onTap;

  /// Opens the book menu at a global anchor; resolves true when the menu
  /// closed without a choice, and focus returns to the row if the keyboard
  /// closed it.
  final Future<bool> Function(Rect anchor) onMenu;
  final Key? moreKey;

  static const minHeight = 88.0;
  static const coverWidth = 40.0;
  static const minTitle = 240.0;
  static const sourceColumn = 72.0;
  static const progressColumn = 180.0, narrowProgressColumn = 120.0;

  /// Content narrower than this uses [narrowProgressColumn].
  static const wideContent = 900.0;
  static const maxProgressBar = 160.0;

  @override
  State<DesktopBookRow> createState() => _DesktopBookRowState();
}

class _DesktopBookRowState extends State<DesktopBookRow> {
  final _focus = FocusNode(debugLabel: 'shelf-row');
  final _more = GlobalKey();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open(Rect anchor, {bool keyboard = false}) async {
    final restore = await menuClosedFromKeyboard(
      widget.onMenu(anchor),
      keyboard: keyboard,
    );
    if (restore && mounted) _focus.requestFocus();
  }

  void _openAtMore({bool keyboard = false}) {
    final box = _more.currentContext!.findRenderObject()! as RenderBox;
    _open(box.localToGlobal(Offset.zero) & box.size, keyboard: keyboard);
  }

  Widget? _bar(double? width) => widget.progress == null
      ? null
      : SizedBox(
          width: width,
          child: ExcludeSemantics(
            child: LinearProgressIndicator(
              value: widget.progress,
              minHeight: 3,
              borderRadius: BorderRadius.circular(ShioriShape.indicator),
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .75),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .10),
              stopIndicatorRadius: 0,
            ),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final largeText =
        MediaQuery.textScalerOf(context).scale(14) > 14 * maxDensityScale;
    final more = SizedBox(
      width: 40,
      child: IconButton(
        key: widget.moreKey,
        tooltip: AppLocalizations.of(context).moreActions,
        onPressed: _openAtMore,
        icon: Icon(Icons.more_horiz, size: 20, key: _more),
      ),
    );
    final tag = widget.sourceLabel == null
        ? null
        : ShelfFormatTag(label: widget.sourceLabel!);
    final label = widget.progressLabel;
    final cover = SizedBox(
      width: DesktopBookRow.coverWidth,
      height: DesktopBookRow.coverWidth / ShioriShape.coverRatio,
      child: widget.cover,
    );
    final text = _RowText(
      title: widget.title,
      subtitle: widget.subtitle,
      secondary: secondary,
    );

    return ShelfMenuShortcuts(
      onMenu: () => _openAtMore(keyboard: true),
      child: BookListItem(
        focusNode: _focus,
        minHeight: DesktopBookRow.minHeight,
        onTap: widget.onTap,
        onLongPress: _openAtMore,
        onSecondaryTapUp: (details) =>
            _open(details.globalPosition & Size.zero),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final progressWidth = bounds.maxWidth < DesktopBookRow.wideContent
                ? DesktopBookRow.narrowProgressColumn
                : DesktopBookRow.progressColumn;
            final fixed =
                DesktopBookRow.coverWidth +
                ShioriSpace.item * 3 +
                DesktopBookRow.sourceColumn +
                progressWidth +
                ShioriSpace.small +
                40;
            if (!largeText &&
                bounds.maxWidth - fixed >= DesktopBookRow.minTitle) {
              return Row(
                children: [
                  cover,
                  const SizedBox(width: ShioriSpace.item),
                  Expanded(child: text),
                  const SizedBox(width: ShioriSpace.item),
                  SizedBox(
                    width: DesktopBookRow.sourceColumn,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      heightFactor: 1,
                      child: tag,
                    ),
                  ),
                  const SizedBox(width: ShioriSpace.item),
                  SizedBox(
                    width: progressWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (label != null)
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: secondary,
                          ),
                        if (_bar(progressWidth) case final bar?) ...[
                          const SizedBox(height: 6),
                          bar,
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: ShioriSpace.small),
                  more,
                ],
              );
            }
            final meta = <Widget>[
              ?tag,
              if (label != null) Text(label, style: secondary),
            ];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cover,
                const SizedBox(width: ShioriSpace.item),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      text,
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: ShioriSpace.small),
                        Wrap(
                          spacing: ShioriSpace.small,
                          runSpacing: ShioriSpace.tight,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: meta,
                        ),
                      ],
                      if (_bar(null) case final bar?) ...[
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: DesktopBookRow.maxProgressBar,
                          ),
                          child: bar,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: ShioriSpace.small),
                more,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RowText extends StatelessWidget {
  const _RowText({required this.title, this.subtitle, this.secondary});
  final String title;
  final String? subtitle;
  final TextStyle? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedDefaultTextStyle(
          duration: ShioriMotion.of(context, ShioriMotion.feedback),
          style: (theme.textTheme.titleSmall ?? const TextStyle()).copyWith(
            height: 1.4,
            color: BookListItem.activeOf(context)
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
          ),
          child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
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
    );
  }
}

/// A book file format as a small tag on the page.
class ShelfFormatTag extends StatelessWidget {
  const ShelfFormatTag({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(ShioriShape.tag),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: ShioriType.of(
            context,
          ).badge.copyWith(color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}
