import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/shiori_theme.dart';
import '../../shared/widgets/shiori_logo.dart';
import '../../shared/widgets/desktop_content_frame.dart';
import 'home_navigation.dart';

/// How the desktop shell presents its navigation at a given width.
enum ShellLayout {
  /// A bottom bar below the workspace, for narrow windows.
  bar,

  /// An icon rail beside the workspace.
  rail,

  /// A labelled sidebar beside the workspace.
  sidebar,
}

/// Judged from the shell's own width, not the screen's.
ShellLayout shellLayoutFor(double width) => width < ShioriLayout.page
    ? ShellLayout.bar
    : width < ShioriLayout.sidebarBreakpoint
    ? ShellLayout.rail
    : ShellLayout.sidebar;

/// One navigation entry. Entries with a [section] select it; the others,
/// such as app appearance, run [onPressed] without leaving the section.
class ShellItem {
  const ShellItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.section,
    this.onPressed,
  }) : assert((section == null) != (onPressed == null));

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final HomeSection? section;
  final VoidCallback? onPressed;
}

/// Leaves the current workspace page, the same as its back button.
class WorkspaceBackIntent extends Intent {
  const WorkspaceBackIntent({this.keepTextEditing = false});

  /// Leave text fields their own use of the key, e.g. Alt+← word moves.
  final bool keepTextEditing;
}

/// Pointer-first home: section navigation beside one workspace navigator.
///
/// The workspace is kept under a global key, so crossing a breakpoint only
/// moves the navigation and never rebuilds the workspace or its stack.
/// Escape, Alt+← and the mouse back button leave the current workspace
/// page. They are bound here, above the sidebar and the workspace, with an
/// intent of their own: the modal-dismiss action every page route installs
/// is disabled for pages and would otherwise stop the lookup. Dialogs,
/// sheets and the reader live on the root navigator, outside this subtree,
/// and keep their own Escape handling.
class DesktopShell extends StatefulWidget {
  const DesktopShell({
    super.key,
    required this.navigation,
    required this.workspace,
    required this.workspaceNavigator,
    required this.groups,
    required this.footer,
    required this.semanticLabel,
  });

  final HomeNavigation navigation;
  final Widget workspace;
  final GlobalKey<NavigatorState> workspaceNavigator;

  /// Section entries, separated by dividers, then the entries at the end.
  final List<List<ShellItem>> groups;
  final List<ShellItem> footer;
  final String semanticLabel;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final _workspaceHost = GlobalKey(debugLabel: 'workspace');

  /// Only while the home route is on top: a dialog, sheet or the reader
  /// above it owns back.
  bool _canGoBack() =>
      ModalRoute.of(context)?.isCurrent != false &&
      widget.workspaceNavigator.currentState?.canPop() == true;

  void _goBack() => widget.workspaceNavigator.currentState?.maybePop();

  void _pointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons & kBackMouseButton != 0 &&
        _canGoBack()) {
      _goBack();
    }
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      // A held Esc goes back once: its repeats must not carry on here after
      // it closed a reader, dialog or menu above.
      SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
          WorkspaceBackIntent(),
      SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
          WorkspaceBackIntent(keepTextEditing: true),
    },
    child: Actions(
      actions: {WorkspaceBackIntent: _WorkspaceBackAction(this)},
      child: Listener(
        onPointerDown: _pointerDown,
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = shellLayoutFor(constraints.maxWidth);
              // One Flex for every layout, so its children keep their
              // elements; the bar sits below by laying out upwards.
              return Flex(
                direction: layout == ShellLayout.bar
                    ? Axis.vertical
                    : Axis.horizontal,
                verticalDirection: layout == ShellLayout.bar
                    ? VerticalDirection.up
                    : VerticalDirection.down,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListenableBuilder(
                    listenable: widget.navigation,
                    builder: (context, _) => ShellNavigation(
                      layout: layout,
                      selected: widget.navigation.section,
                      onSelect: widget.navigation.select,
                      groups: widget.groups,
                      footer: widget.footer,
                      semanticLabel: widget.semanticLabel,
                    ),
                  ),
                  Expanded(
                    child: KeyedSubtree(
                      key: _workspaceHost,
                      child: DesktopLayoutScope(
                        width: constraints.maxWidth,
                        child: widget.workspace,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _WorkspaceBackAction extends Action<WorkspaceBackIntent> {
  _WorkspaceBackAction(this.shell);
  final _DesktopShellState shell;

  @override
  bool isEnabled(WorkspaceBackIntent intent) {
    if (!shell.mounted || !shell._canGoBack()) return false;
    if (!intent.keepTextEditing) return true;
    final focused = primaryFocus?.context;
    return focused == null ||
        focused.findAncestorStateOfType<EditableTextState>() == null;
  }

  @override
  void invoke(WorkspaceBackIntent intent) => shell._goBack();
}

/// Sidebar, rail or bottom bar for the shell's sections.
class ShellNavigation extends StatelessWidget {
  const ShellNavigation({
    super.key,
    required this.layout,
    required this.selected,
    required this.onSelect,
    required this.groups,
    required this.footer,
    required this.semanticLabel,
  });

  final ShellLayout layout;
  final HomeSection selected;
  final ValueChanged<HomeSection> onSelect;
  final List<List<ShellItem>> groups;
  final List<ShellItem> footer;
  final String semanticLabel;

  Widget _item(ShellItem item) => _ShellNavigationItem(
    item: item,
    layout: layout,
    selected: item.section != null && item.section == selected,
    onPressed: item.onPressed ?? () => onSelect(item.section!),
  );

  @override
  Widget build(BuildContext context) {
    final separator = Theme.of(context).colorScheme.outlineVariant;
    final edge = BorderSide(color: separator.withValues(alpha: .7), width: .5);
    final Widget content = switch (layout) {
      ShellLayout.bar => SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (final item in [...groups.expand((g) => g), ...footer])
                Expanded(child: _item(item)),
            ],
          ),
        ),
      ),
      ShellLayout.rail || ShellLayout.sidebar => SafeArea(
        right: false,
        child: SizedBox(
          width: layout == ShellLayout.rail
              ? ShioriLayout.rail
              : ShioriLayout.sidebar,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (layout == ShellLayout.sidebar)
                const SizedBox(
                  height: 56,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: ShioriSpace.page),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ShioriLogo(),
                    ),
                  ),
                )
              else
                const SizedBox(height: ShioriSpace.medium),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ShioriSpace.medium,
                    vertical: ShioriSpace.tight,
                  ),
                  children: [
                    for (final (index, group) in groups.indexed) ...[
                      if (index > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: ShioriSpace.small,
                            horizontal: ShioriSpace.small,
                          ),
                          child: Divider(height: 1, color: separator),
                        ),
                      for (final item in group) _item(item),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ShioriSpace.medium,
                  ShioriSpace.tight,
                  ShioriSpace.medium,
                  ShioriSpace.medium,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final item in footer) _item(item)],
                ),
              ),
            ],
          ),
        ),
      ),
    };
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: layout == ShellLayout.bar
              ? Border(top: edge)
              : BorderDirectional(end: edge),
        ),
        child: FocusTraversalGroup(child: content),
      ),
    );
  }
}

class _ShellNavigationItem extends StatelessWidget {
  const _ShellNavigationItem({
    required this.item,
    required this.layout,
    required this.selected,
    required this.onPressed,
  });

  final ShellItem item;
  final ShellLayout layout;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final indicator =
        theme.navigationBarTheme.indicatorColor ?? colors.secondaryContainer;
    final foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    final icon = Icon(
      selected ? item.selectedIcon ?? item.icon : item.icon,
      size: 22,
      color: foreground,
    );
    final radius = BorderRadius.circular(ShioriShape.control);
    final labelled = layout == ShellLayout.sidebar;
    Widget body = labelled
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: ShioriSpace.medium),
            child: Row(
              children: [
                icon,
                const SizedBox(width: ShioriSpace.medium),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? colors.onSurface : foreground,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          )
        : Center(child: icon);
    body = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? indicator : null,
            borderRadius: radius,
          ),
          child: body,
        ),
      ),
    );
    body = switch (layout) {
      ShellLayout.sidebar => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 42),
        child: body,
      ),
      ShellLayout.rail => SizedBox(height: 44, child: body),
      ShellLayout.bar => Center(
        child: SizedBox(width: 56, height: 36, child: body),
      ),
    };
    body = Semantics(
      container: true,
      button: true,
      selected: item.section == null ? null : selected,
      label: item.label,
      onTap: onPressed,
      excludeSemantics: true,
      child: body,
    );
    if (!labelled) {
      body = Tooltip(
        message: item.label,
        excludeFromSemantics: true,
        child: body,
      );
    }
    return Padding(
      padding: layout == ShellLayout.bar
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 1),
      child: body,
    );
  }
}
