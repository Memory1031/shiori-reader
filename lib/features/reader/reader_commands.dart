import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What the reader can be asked to do, whichever input asks: a toolbar
/// button, the overflow or context menu, or a keyboard shortcut. Each input
/// runs the command through the same availability check and handler.
enum ReaderCommand {
  previousPage,
  nextPage,
  toggleControls,
  contents,
  progress,
  settings,
  notes,
  prefetch,
  details,
  retrySave,
  retrySettings,
}

/// Runs a [ReaderCommand] from a shortcut.
class ReaderCommandIntent extends Intent {
  const ReaderCommandIntent(this.command, {this.yieldsToControls = false});
  final ReaderCommand command;

  /// Whether the key belongs to a focused control first. Space (and
  /// Shift+Space) activates a focused toolbar button instead of turning the
  /// page; the arrows and Page Up / Page Down always turn.
  final bool yieldsToControls;
}

/// Esc on the page: the route's own back handling, as the system back
/// gesture on phones.
class ReaderBackIntent extends Intent {
  const ReaderBackIntent();
}

/// The Menu key or Shift+F10: the page's context menu.
class ReaderContextMenuIntent extends Intent {
  const ReaderContextMenuIntent();
}

/// Reader shortcuts on every platform.
const readerShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.f2): ReaderCommandIntent(
    ReaderCommand.toggleControls,
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight): ReaderCommandIntent(
    ReaderCommand.nextPage,
  ),
  SingleActivator(LogicalKeyboardKey.arrowLeft): ReaderCommandIntent(
    ReaderCommand.previousPage,
  ),
  SingleActivator(LogicalKeyboardKey.pageDown): ReaderCommandIntent(
    ReaderCommand.nextPage,
  ),
  SingleActivator(LogicalKeyboardKey.pageUp): ReaderCommandIntent(
    ReaderCommand.previousPage,
  ),
};

/// Shortcuts added where a keyboard and mouse are the primary input.
/// Commands that open something ignore key repeats, so holding a key opens
/// it once.
const desktopReaderShortcuts = <ShortcutActivator, Intent>{
  ...readerShortcuts,
  SingleActivator(LogicalKeyboardKey.space): ReaderCommandIntent(
    ReaderCommand.nextPage,
    yieldsToControls: true,
  ),
  SingleActivator(LogicalKeyboardKey.space, shift: true): ReaderCommandIntent(
    ReaderCommand.previousPage,
    yieldsToControls: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.keyT,
    control: true,
    includeRepeats: false,
  ): ReaderCommandIntent(
    ReaderCommand.contents,
  ),
  SingleActivator(
    LogicalKeyboardKey.keyG,
    control: true,
    includeRepeats: false,
  ): ReaderCommandIntent(
    ReaderCommand.progress,
  ),
  SingleActivator(
    LogicalKeyboardKey.comma,
    control: true,
    includeRepeats: false,
  ): ReaderCommandIntent(
    ReaderCommand.settings,
  ),
  SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
      ReaderBackIntent(),
  SingleActivator(LogicalKeyboardKey.contextMenu, includeRepeats: false):
      ReaderContextMenuIntent(),
  SingleActivator(LogicalKeyboardKey.f10, shift: true, includeRepeats: false):
      ReaderContextMenuIntent(),
};

/// Shortcut labels shown in desktop tooltips.
abstract final class ReaderShortcutLabels {
  static const contents = 'Ctrl+T';
  static const progress = 'Ctrl+G';
  static const settings = 'Ctrl+,';
}
