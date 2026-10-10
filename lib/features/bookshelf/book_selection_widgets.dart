import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/shiori_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/desktop_content_frame.dart';
import 'book_batch_actions.dart';

/// Page-scoped keys and back handling. Overlay routes retain priority; InkWell
/// owns Space activation on each focused book, so there is only one toggle.
class BookSelectionScope extends StatelessWidget {
  const BookSelectionScope({
    super.key,
    required this.actions,
    required this.child,
  });
  final BookBatchActions actions;
  final Widget child;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !actions.selection.active && !actions.busy,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !actions.busy && actions.selection.active) actions.leave();
    },
    child: Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent ||
            !actions.selection.active ||
            actions.busy) {
          return KeyEventResult.ignored;
        }
        final focused = primaryFocus?.context;
        if (focused?.findAncestorStateOfType<EditableTextState>() != null) {
          return KeyEventResult.ignored;
        }
        var current = ModalRoute.of(context)?.isCurrent != false;
        context.visitAncestorElements((element) {
          if (ModalRoute.of(element)?.isCurrent == false) current = false;
          return current;
        });
        if (!current) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          actions.leave();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyA &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          if (!actions.selection.allSelected) actions.selection.toggleAll();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    ),
  );
}

class BookSelectionEntry extends StatelessWidget {
  const BookSelectionEntry({
    super.key,
    required this.actions,
    this.compact = false,
  });
  final BookBatchActions actions;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return compact
        ? IconButton(
            key: const ValueKey('book-multi-select'),
            tooltip: l.bookMultiSelect,
            onPressed: actions.canEnter ? actions.enter : null,
            icon: const Icon(Icons.checklist),
          )
        : OutlinedButton.icon(
            key: const ValueKey('book-multi-select'),
            onPressed: actions.canEnter ? actions.enter : null,
            icon: const Icon(Icons.checklist, size: 20),
            label: Text(l.bookMultiSelect),
          );
  }
}

class BookSelectionToolbar extends StatelessWidget {
  const BookSelectionToolbar({
    super.key,
    required this.actions,
    this.operations = false,
    this.localOnly = false,
    this.layout,
  });
  final BookBatchActions actions;
  final bool operations, localOnly;
  final Widget? layout;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), selection = actions.selection;
    return DesktopPageToolbar(
      title: l.bookSelectedCount(selection.selected.length),
      leading: IconButton(
        key: const ValueKey('book-selection-exit'),
        style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
        tooltip: l.importCancel,
        onPressed: actions.busy ? null : actions.leave,
        icon: const Icon(Icons.close),
      ),
      actions: [
        _SelectAll(actions: actions),
        ?layout,
        if (operations)
          ..._operationButtons(context, actions, localOnly, desktop: true),
      ],
    );
  }
}

class BookSelectionAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const BookSelectionAppBar({super.key, required this.actions});
  final BookBatchActions actions;
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(
    leading: IconButton(
      key: const ValueKey('book-selection-exit'),
      tooltip: AppLocalizations.of(context).importCancel,
      onPressed: actions.busy ? null : actions.leave,
      icon: const Icon(Icons.close),
    ),
    title: Text(
      AppLocalizations.of(
        context,
      ).bookSelectedCount(actions.selection.selected.length),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    actions: [
      _SelectAll(
        actions: actions,
        compact:
            MediaQuery.textScalerOf(context).scale(14) > 18 ||
            MediaQuery.sizeOf(context).width < 360,
      ),
      const SizedBox(width: ShioriSpace.small),
    ],
  );
}

double _labelWidth(BuildContext context, Iterable<String> labels) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );
  var width = 0.0;
  for (final label in labels) {
    painter.text = TextSpan(
      text: label,
      style: Theme.of(context).textTheme.labelLarge,
    );
    painter.layout();
    if (painter.width > width) width = painter.width;
  }
  painter.dispose();
  return width;
}

class _SelectAll extends StatelessWidget {
  const _SelectAll({required this.actions, this.compact = false});
  final BookBatchActions actions;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), selection = actions.selection;
    final label = selection.allSelected ? l.bookDeselectAll : l.bookSelectAll;
    final onPressed = actions.busy || !selection.reliable
        ? null
        : selection.toggleAll;
    if (compact) {
      return IconButton(
        key: const ValueKey('book-selection-all'),
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(selection.allSelected ? Icons.deselect : Icons.select_all),
      );
    }
    return SizedBox(
      width:
          _labelWidth(context, [l.bookSelectAll, l.bookDeselectAll]) +
          ShioriSpace.section,
      child: TextButton(
        key: const ValueKey('book-selection-all'),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

String _operationHint(AppLocalizations l, BookBatchActions actions) =>
    actions.selection.selected.isEmpty
    ? l.bookNoSelection
    : actions.eligible == 0
    ? l.bookNoReparse
    : l.bookReparseAvailable(actions.eligible);

/// Reparse is a management action and takes the tonal weight used by
/// "Reparse all"; removal keeps an outlined error treatment so the
/// destructive choice is distinct without becoming the bar's emphasis.
List<Widget> _operationButtons(
  BuildContext context,
  BookBatchActions actions,
  bool localOnly, {
  bool desktop = false,
}) {
  final l = AppLocalizations.of(context),
      colors = Theme.of(context).colorScheme;
  final hasSelection = actions.selection.selected.isNotEmpty;
  final idle = !actions.busy && !actions.library.writing;
  return [
    Tooltip(
      message: _operationHint(l, actions),
      child: FilledButton.tonalIcon(
        key: const ValueKey('book-selection-reparse'),
        onPressed: idle && actions.eligible > 0
            ? () => actions.reparseSelected(context)
            : null,
        icon: const Icon(Icons.autorenew, size: 20),
        label: desktop
            ? SizedBox(
                width: _labelWidth(context, [
                  l.bookReparseAction(actions.selection.visible.length),
                ]),
                child: Text(
                  l.bookReparseAction(actions.eligible),
                  textAlign: TextAlign.center,
                ),
              )
            : Text(l.localReparse),
      ),
    ),
    Tooltip(
      message: hasSelection
          ? (localOnly ? l.bookDeleteSelected : l.bookRemoveSelected)
          : l.bookNoSelection,
      child: OutlinedButton.icon(
        key: const ValueKey('book-selection-remove'),
        style: OutlinedButton.styleFrom(foregroundColor: colors.error).copyWith(
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? colors.outlineVariant
                  : colors.error.withValues(alpha: .45),
            ),
          ),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? colors.error.withValues(alpha: .1)
                : states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                ? colors.error.withValues(alpha: .06)
                : null,
          ),
        ),
        onPressed: idle && hasSelection
            ? () => actions.removeSelected(context)
            : null,
        icon: Icon(
          localOnly ? Icons.delete_outline : Icons.bookmark_remove_outlined,
          size: 20,
        ),
        label: Text(localOnly ? l.bookDeleteSelected : l.bookRemoveSelected),
      ),
    ),
  ];
}

/// Phone selection actions, pinned above the bottom inset. The hint keeps
/// one stable line of scope so the buttons do not move as books toggle.
class BookSelectionBottomBar extends StatelessWidget {
  const BookSelectionBottomBar({
    super.key,
    required this.actions,
    this.localOnly = false,
  });
  final BookBatchActions actions;
  final bool localOnly;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), theme = Theme.of(context);
    final buttons = _operationButtons(context, actions, localOnly);
    // Icon, gap and the buttons' own horizontal padding.
    const chrome = 20 + ShioriSpace.small + 2 * 24.0;
    final needed =
        _labelWidth(context, [
          l.localReparse,
          localOnly ? l.bookDeleteSelected : l.bookRemoveSelected,
        ]) +
        chrome;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        shape: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ShioriSpace.page,
              ShioriSpace.medium,
              ShioriSpace.page,
              ShioriSpace.small,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _operationHint(l, actions),
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: ShioriSpace.small),
                LayoutBuilder(
                  builder: (context, bounds) =>
                      bounds.maxWidth >= 2 * needed + ShioriSpace.medium
                      ? Row(
                          children: [
                            Expanded(child: buttons[0]),
                            const SizedBox(width: ShioriSpace.medium),
                            Expanded(child: buttons[1]),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buttons[0],
                            const SizedBox(height: ShioriSpace.small),
                            buttons[1],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The row/card owns activation and semantics; this indicator has no second
/// gesture or keyboard target, including when the pointer hits the marker.
/// [overArtwork] adds a paper halo so the marker reads on any cover.
class BookSelectionCheck extends StatelessWidget {
  const BookSelectionCheck({
    super.key,
    required this.selected,
    this.overArtwork = false,
  });
  final bool selected, overArtwork;
  static const size = 24.0;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = ShioriMotion.of(context, ShioriMotion.feedback);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: SizedBox.square(
          dimension: 40,
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? colors.primary
                    : colors.surface.withValues(alpha: overArtwork ? .82 : 0),
                border: Border.all(
                  color: selected
                      ? colors.primary
                      : colors.onSurfaceVariant.withValues(alpha: .7),
                  width: 1.5,
                ),
                boxShadow: overArtwork
                    ? [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: .22),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: AnimatedScale(
                duration: duration,
                curve: Curves.easeOutBack,
                scale: selected ? 1 : .4,
                child: AnimatedOpacity(
                  duration: duration,
                  opacity: selected ? 1 : 0,
                  child: Icon(Icons.check, size: 16, color: colors.onPrimary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
