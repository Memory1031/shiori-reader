import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme/shiori_theme.dart';

typedef CaptionAppearance = ({Color color, Brightness brightness});
typedef CaptionSender = Future<void> Function(CaptionAppearance appearance);

/// Owns the root route order and the only native caption write queue.
/// A route without a declaration inherits the nearest declaration below it.
/// An explicit null appearance means the live app default, not inheritance.
class WindowCaptionController extends NavigatorObserver {
  WindowCaptionController({CaptionSender? sender}) : _sender = sender ?? _send;

  final CaptionSender _sender;
  final _routes = <Route<dynamic>>[];
  final _claims = <Object, _CaptionClaim>{};
  CaptionAppearance? _default, _desired, _sent;
  bool _scheduled = false, _sending = false, _disposed = false;

  static Future<void> _send(CaptionAppearance appearance) async {
    await const MethodChannel(
      'dev.shiori.reader/app',
    ).invokeMethod<bool>('setCaption', {
      'color': appearance.color.toARGB32(),
      'dark': appearance.brightness == Brightness.dark,
    });
  }

  void _setDefault(CaptionAppearance appearance) {
    if (_default == appearance) return;
    _default = appearance;
    _schedule();
  }

  void _put(Object owner, _CaptionClaim claim) {
    if (_claims[owner] == claim) return;
    _claims[owner] = claim;
    _schedule();
  }

  void _remove(Object owner) {
    if (_claims.remove(owner) != null) _schedule();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _schedule();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _schedule();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _schedule();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _schedule();
  }

  CaptionAppearance? _resolve() {
    for (final route in _routes.reversed) {
      _CaptionClaim? selected;
      for (final claim in _claims.values) {
        if (claim.route == route &&
            (selected == null || claim.depth > selected.depth)) {
          selected = claim;
        }
      }
      if (selected != null) return selected.appearance ?? _default;
    }
    return _default;
  }

  void _schedule() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed) return;
      _desired = _resolve();
      unawaited(_drain());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _drain() async {
    if (_sending || _disposed) return;
    _sending = true;
    try {
      while (!_disposed &&
          !_scheduled &&
          _desired != null &&
          _desired != _sent) {
        final next = _desired!;
        _sent = next;
        try {
          await _sender(next);
        } on PlatformException {
          // Unsupported DWM attributes leave the system frame untouched.
        } on MissingPluginException {
          // Older runners and non-native test hosts can omit this channel.
        }
        // Read only the newest committed desired value after each call.
      }
    } finally {
      _sending = false;
    }
  }

  void dispose() {
    _disposed = true;
    _claims.clear();
    _routes.clear();
  }
}

typedef _CaptionClaim = ({
  Route<dynamic> route,
  int depth,
  CaptionAppearance? appearance,
});

/// Installed above the root navigator, below the live app theme.
class WindowCaptionSync extends StatefulWidget {
  const WindowCaptionSync({
    super.key,
    required this.controller,
    required this.child,
  });
  final WindowCaptionController controller;
  final Widget child;

  @override
  State<WindowCaptionSync> createState() => _WindowCaptionSyncState();
}

class _WindowCaptionSyncState extends State<WindowCaptionSync> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateDefault();
  }

  @override
  void didUpdateWidget(WindowCaptionSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateDefault();
  }

  void _updateDefault() {
    final theme = Theme.of(context);
    widget.controller._setDefault((
      color:
          theme.extension<ShioriPalette>()?.paper ??
          theme.scaffoldBackgroundColor,
      brightness: theme.brightness,
    ));
  }

  @override
  Widget build(BuildContext context) =>
      _CaptionRoot(controller: widget.controller, child: widget.child);
}

class _CaptionRoot extends InheritedWidget {
  const _CaptionRoot({required this.controller, required super.child});
  final WindowCaptionController controller;
  @override
  bool updateShouldNotify(_CaptionRoot oldWidget) =>
      controller != oldWidget.controller;
}

/// A declaration only: registration never changes or rebuilds [child].
/// Nested declarations override the same route's default page declaration.
class WindowCaptionScope extends StatefulWidget {
  const WindowCaptionScope({
    super.key,
    required this.appearance,
    this.enabled = true,
    required this.child,
  });
  const WindowCaptionScope.appDefault({super.key, required this.child})
    : appearance = null,
      enabled = true;

  final CaptionAppearance? appearance;
  final bool enabled;
  final Widget child;

  @override
  State<WindowCaptionScope> createState() => _WindowCaptionScopeState();
}

class _WindowCaptionScopeState extends State<WindowCaptionScope> {
  WindowCaptionController? _controller;
  Route<dynamic>? _route;
  int _depth = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context
        .dependOnInheritedWidgetOfExactType<_CaptionRoot>()
        ?.controller;
    if (_controller != controller) _controller?._remove(this);
    _controller = controller;
    _route = ModalRoute.of(context);
    final parent = context.dependOnInheritedWidgetOfExactType<_CaptionDepth>();
    _depth = parent?.route == _route ? parent!.depth + 1 : 0;
    _update();
  }

  @override
  void didUpdateWidget(WindowCaptionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final route = _route;
    if (widget.enabled &&
        route != null &&
        route.navigator == _controller?.navigator) {
      _controller?._put(this, (
        route: route,
        depth: _depth,
        appearance: widget.appearance,
      ));
    } else {
      _controller?._remove(this);
    }
  }

  @override
  void dispose() {
    _controller?._remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _CaptionDepth(route: _route, depth: _depth, child: widget.child);
}

class _CaptionDepth extends InheritedWidget {
  const _CaptionDepth({
    required this.route,
    required this.depth,
    required super.child,
  });
  final Route<dynamic>? route;
  final int depth;
  @override
  bool updateShouldNotify(_CaptionDepth oldWidget) =>
      route != oldWidget.route || depth != oldWidget.depth;
}
