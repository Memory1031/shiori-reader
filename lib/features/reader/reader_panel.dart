import 'package:flutter/material.dart';

import '../../domain/contracts/contracts.dart';
import '../../shared/widgets/shiori_panel.dart';

export '../../shared/widgets/shiori_panel.dart'
    show ShioriPanelScope, ShioriSheetSize;

typedef ReaderPanelPlacement = ShioriPanelSide;
typedef ReaderPanelRoute<T> = ShioriSidePanelRoute<T>;

Future<T?> showReaderPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  ReaderPanelPlacement placement = ReaderPanelPlacement.end,
  ShioriSheetSize size = ShioriSheetSize.fit,
  bool owned = false,
  Color? barrierColor,
  ThemeData Function(BuildContext)? theme,
  Listenable? themeChanges,
}) => showShioriPanel<T>(
  context,
  builder: builder,
  side: placement,
  size: size,
  owned: owned,
  barrierColor: barrierColor,
  theme: theme,
  themeChanges: themeChanges,
);

/// Closes a reader panel or sheet, then applies [then], the choice made in
/// it, if any.
///
/// A sheet applies the choice as it closes. A desktop panel hands it back
/// as its result instead: the page that opened the panel applies it once
/// the panel has closed, and only while that page still reads the same
/// session and takes commands. Either way only the first call counts.
typedef ReaderPanelDone = void Function([VoidCallback? then]);

/// Pops a one-shot panel and applies its choice, once.
ReaderPanelDone readerPanelDone(BuildContext sheet) => ([then]) {
  // A sheet already closing, or covered, takes no further choice.
  if (ModalRoute.of(sheet)?.isCurrent != true) return;
  Navigator.of(sheet).pop();
  then?.call();
};

/// An open reader panel or sheet, held by the state that opened it.
///
/// It keeps the route, its navigator and its owner rather than a
/// [BuildContext], so the owner can take the panel down from `dispose`.
///
/// Whether the panel still takes input ([isValid], which [close] ends at
/// once) is kept apart from whether a choice made in it reaches the reader:
/// the choice travels as the result in [closed], for the opener to check
/// against its session before acting on it.
class ReaderPanelHandle<T> {
  ReaderPanelHandle._(this.owner, this.navigator);

  /// Pushes a panel for [owner] onto the navigator around it.
  ///
  /// [builder] receives the handle so its controls can close the panel.
  factory ReaderPanelHandle.open(
    State owner, {
    required ReaderPanelPlacement placement,
    required Widget Function(BuildContext context, ReaderPanelHandle<T> panel)
    builder,
    String? semanticLabel,
    ThemeData Function(BuildContext context)? theme,
    Listenable? themeChanges,
    ShioriSheetSize size = ShioriSheetSize.fit,
    bool owned = false,
  }) {
    final context = owner.context;
    final handle = ReaderPanelHandle<T>._(
      owner,
      Navigator.of(context, rootNavigator: true),
    );
    handle.route = shioriPanelRoute<T>(
      context,
      side: placement,
      builder: (context) => builder(context, handle),
      size: size,
      owned: owned,
      semanticLabel: semanticLabel,
      theme: theme,
      themeChanges: themeChanges,
    );
    handle.closed = handle.navigator.push(handle.route);
    return handle;
  }

  final State owner;
  final NavigatorState navigator;
  late final ModalRoute<T> route;

  /// The panel's result: what [close] was given, or null once it is
  /// dismissed by Esc or a click outside, or removed.
  late final Future<T?> closed;

  /// Completes once the panel has finished its exit and left the overlay.
  Future<void> get completed => route.completed;

  bool _accepting = true;

  /// Whether the panel still takes input for a mounted owner: it has been
  /// neither closed, dismissed nor retired. Callbacks from the panel act
  /// only while this holds.
  bool get isValid => _accepting && owner.mounted && shioriPanelIsOpen(route);

  /// Closes the panel with its exit animation, handing back [result]. Only
  /// the first call on an open, uncovered panel counts; the panel takes no
  /// further input from then on.
  void close([T? result]) {
    if (!isValid || !route.isCurrent) return;
    _accepting = false;
    navigator.pop(result);
  }

  /// Retires the handle and removes the panel without animation, for an
  /// owner going away or no longer taking commands. [closed] then resolves
  /// with null.
  ///
  /// The owner's `dispose` and `didUpdateWidget` run while the tree is
  /// locked, so the route is removed after the frame, and only if it is
  /// still open in a mounted navigator; one already closing finishes on its
  /// own. Only this route is removed: whatever was pushed above it stays.
  void dismiss() {
    _accepting = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && shioriPanelIsOpen(route)) {
        navigator.removeRoute(route);
      }
    });
  }
}

/// The panel slot of one reader page, handed to screen-level commands such
/// as notes and prefetch so that what they open sits over that page, in its
/// reading theme, and shares its single slot.
///
/// It is passed explicitly rather than looked up, so a command always
/// reaches the page it was invoked from.
abstract interface class ReaderPanels {
  /// The page's context, in its reading theme.
  BuildContext get context;

  /// Whether the page is still mounted, reads the session the command was
  /// invoked for and takes commands. A choice returned from a panel or a
  /// sheet is acted on only while this holds.
  bool get live;

  /// Opens a responsive panel in the page's slot, in the reading theme. Null
  /// when the slot is taken or the page is not [live].
  ReaderPanelHandle<T>? open<T>(
    ReaderPanelPlacement placement, {
    required String semanticLabel,
    required Widget Function(BuildContext context, ReaderPanelHandle<T> panel)
    builder,
  });

  /// Shows a footnote in the same responsive end panel as other reader tools.
  Future<void> footnote(LocalContentLink note);
}
