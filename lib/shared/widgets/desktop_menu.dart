import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens a book menu from the Menu key or Shift+F10 while [child] or a
/// descendant has focus.
class DesktopMenuShortcuts extends StatelessWidget {
  const DesktopMenuShortcuts({
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
