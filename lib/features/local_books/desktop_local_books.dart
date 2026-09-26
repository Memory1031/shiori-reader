import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_list_tile.dart';
import '../../shared/widgets/desktop_menu.dart';

/// Local-book interaction shell; the page supplies metadata and commands.
class DesktopLocalBookRow extends StatefulWidget {
  const DesktopLocalBookRow({
    super.key,
    required this.content,
    required this.onMenu,
    this.onRead,
  });
  final Widget content;
  final VoidCallback? onRead;
  final Future<bool> Function(Rect anchor) onMenu;
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
    if (widget.onRead == null) return;
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
      focusNode: _focus,
      onTap: widget.onRead,
      onSecondaryTapUp: (details) => _open(details.globalPosition & Size.zero),
      // Keep the shared mobile book content readable without shrinking the
      // pointer target, hover surface, or the surrounding Workspace viewport.
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShioriSpace.item - BookListItem.inset,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ShioriLayout.page,
                  ),
                  child: widget.content,
                ),
              ),
            ),
            const SizedBox(width: ShioriSpace.item),
            IconButton(
              key: _more,
              tooltip: AppLocalizations.of(context).moreActions,
              onPressed: widget.onRead == null ? null : _openAtMore,
              icon: const Icon(Icons.more_horiz, size: 20),
            ),
          ],
        ),
      ),
    ),
  );
}
