import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/desktop_menu.dart';
import '../../shared/widgets/shiori_menu.dart';

/// Keeps the book subtree stable while desktop menu input is enabled/disabled.
/// The ExpansionTile and chapter ListTiles retain their own keyboard focus.
class CacheBookMenu extends StatefulWidget {
  const CacheBookMenu({
    super.key,
    required this.desktop,
    required this.enabled,
    required this.onClear,
    required this.mobileMenu,
    required this.builder,
  });
  final bool desktop, enabled;
  final VoidCallback onClear;
  final Widget mobileMenu;
  final Widget Function(Widget menu) builder;

  @override
  State<CacheBookMenu> createState() => _CacheBookMenuState();
}

class _CacheBookMenuState extends State<CacheBookMenu> {
  final _anchor = GlobalKey();
  bool _open = false;

  Future<void> _show({Offset? at, bool keyboard = false}) async {
    if (!widget.desktop || !widget.enabled || _open) return;
    _open = true;
    final focus = FocusManager.instance.primaryFocus;
    final box = _anchor.currentContext!.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()!
            as RenderBox;
    final point = overlay.globalToLocal(
      at ??
          box.localToGlobal(
            Directionality.of(context) == TextDirection.rtl
                ? box.size.bottomRight(Offset.zero)
                : box.size.bottomLeft(Offset.zero),
          ),
    );
    Future<bool> menu() async {
      final action = await showMenu<String>(
        context: context,
        useRootNavigator: true,
        position: RelativeRect.fromRect(
          point & Size.zero,
          Offset.zero & overlay.size,
        ),
        items: [
          ShioriMenuItem(
            value: 'clear',
            label: AppLocalizations.of(context).cacheClearBook,
          ),
        ],
      );
      if (action == 'clear' && mounted && widget.enabled) widget.onClear();
      return action == null;
    }

    try {
      final restore = await menuClosedFromKeyboard(menu(), keyboard: keyboard);
      if (restore && mounted && focus?.context != null) focus!.requestFocus();
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ShioriCapabilities.of(context).touchFirst) {
      return widget.builder(widget.mobileMenu);
    }
    return DesktopMenuShortcuts(
      onMenu: () => _show(keyboard: true),
      child: GestureDetector(
        onSecondaryTapUp: widget.desktop && widget.enabled
            ? (event) => _show(at: event.globalPosition)
            : null,
        child: widget.builder(
          widget.desktop
              ? IconButton(
                  key: _anchor,
                  tooltip: AppLocalizations.of(context).moreActions,
                  onPressed: widget.enabled ? () => _show() : null,
                  icon: const Icon(Icons.more_horiz, size: 20),
                )
              : widget.mobileMenu,
        ),
      ),
    );
  }
}
