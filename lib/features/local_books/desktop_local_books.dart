import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_list_tile.dart';
import '../../shared/widgets/desktop_menu.dart';
import '../bookshelf/book_selection_widgets.dart';

/// Local-book interaction shell; the page supplies metadata and commands.
class DesktopLocalBookRow extends StatefulWidget {
  const DesktopLocalBookRow({
    super.key,
    required this.content,
    required this.onMenu,
    this.onRead,
    this.selected,
    this.selectionLabel,
  });
  final Widget Function(Widget action) content;
  final VoidCallback? onRead;
  final Future<bool> Function(Rect anchor) onMenu;
  final bool? selected;
  final String? selectionLabel;
  @override
  State<DesktopLocalBookRow> createState() => _DesktopLocalBookRowState();
}

class _DesktopLocalBookRowState extends State<DesktopLocalBookRow> {
  final _focus = FocusNode(debugLabel: 'local-book-row');
  final _more = GlobalKey();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open(Rect at, {bool keyboard = false}) async {
    if (widget.onRead == null || widget.selected != null) return;
    final restore = await menuClosedFromKeyboard(
      widget.onMenu(at),
      keyboard: keyboard,
    );
    if (restore && mounted) _focus.requestFocus();
  }

  void _openAtMore({bool keyboard = false}) {
    final box = _more.currentContext!.findRenderObject()! as RenderBox;
    _open(box.localToGlobal(Offset.zero) & box.size, keyboard: keyboard);
  }

  @override
  Widget build(BuildContext context) => DesktopMenuShortcuts(
    onMenu: () => _openAtMore(keyboard: true),
    child: BookListItem(
      minHeight: 88,
      selected: widget.selected,
      selectionLabel: widget.selectionLabel,
      focusNode: _focus,
      onTap: widget.onRead,
      onSecondaryTapUp: widget.selected != null
          ? null
          : (details) => _open(details.globalPosition & Size.zero),
      child: widget.content(
        widget.selected != null
            ? BookSelectionCheck(selected: widget.selected!)
            : IconButton(
                key: _more,
                tooltip: AppLocalizations.of(context).moreActions,
                onPressed: widget.onRead == null ? null : _openAtMore,
                icon: const Icon(Icons.more_horiz, size: 20),
              ),
      ),
    ),
  );
}
