import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/theme/shiori_theme.dart';
import '../capabilities.dart';

enum ShioriFeedbackKind { info, success, error }

abstract final class ShioriFeedback {
  /// Actions expire with their source route; plain acknowledgements survive it.
  static void show(
    BuildContext context, {
    required String message,
    ShioriFeedbackKind kind = ShioriFeedbackKind.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    assert((actionLabel == null) == (onAction == null));
    if (!context.mounted) return;
    final host = context.findAncestorStateOfType<_ShioriFeedbackHostState>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final route = ModalRoute.of(context);
    final action = onAction == null
        ? null
        : () {
            if (context.mounted && route?.isActive != false) onAction();
          };
    if (host != null) {
      host.show(context, message, kind, actionLabel, action, route);
    } else {
      _present(context, messenger, _bar(message, kind, actionLabel, action));
    }
  }

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _present(
    BuildContext context,
    ScaffoldMessengerState messenger,
    SnackBar bar,
  ) => messenger.showSnackBar(
    bar,
    snackBarAnimationStyle: AnimationStyle(
      duration: ShioriMotion.of(context, ShioriMotion.feedback),
      reverseDuration: ShioriMotion.of(context, ShioriMotion.feedback),
    ),
  );

  static SnackBar _bar(
    String message,
    ShioriFeedbackKind kind,
    String? actionLabel,
    VoidCallback? onAction,
  ) {
    return SnackBar(
      hitTestBehavior: HitTestBehavior.deferToChild,
      content: _FeedbackBody(message: message, kind: kind),
      duration: Duration(
        seconds: onAction != null
            ? 10
            : kind == ShioriFeedbackKind.error
            ? 6
            : 4,
      ),
      action: onAction == null
          ? null
          : SnackBarAction(label: actionLabel!, onPressed: onAction),
    );
  }
}

class _FeedbackBody extends StatelessWidget {
  const _FeedbackBody({required this.message, required this.kind});
  final String message;
  final ShioriFeedbackKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        ExcludeSemantics(
          child: Icon(
            switch (kind) {
              ShioriFeedbackKind.info => Icons.info_outline,
              ShioriFeedbackKind.success => Icons.check_circle_outline,
              ShioriFeedbackKind.error => Icons.error_outline,
            },
            size: 20,
            color: kind == ShioriFeedbackKind.error
                ? colors.error
                : colors.primary,
          ),
        ),
        const SizedBox(width: ShioriSpace.medium),
        Expanded(
          child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// Modal routes own interaction while the root Scaffold sits above Navigator.
class ShioriFeedbackObserver extends NavigatorObserver {
  final _modals = <Route<dynamic>>{};
  VoidCallback? changed;
  bool get blocked => _modals.isNotEmpty;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _modals.add(route);
    changed?.call();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PopupRoute) _modals.add(newRoute);
    if (oldRoute != null) _remove(oldRoute);
    changed?.call();
  }

  void _remove(Route<dynamic> route) {
    // Keep confirmations unobstructed until their exit animation finishes.
    if (route is TransitionRoute && _modals.contains(route)) {
      route.completed.then((_) {
        _modals.remove(route);
        changed?.call();
      });
    } else {
      _modals.remove(route);
      changed?.call();
    }
  }
}

/// One root Scaffold owns feedback; its body keeps the original window metrics.
class ShioriFeedbackHost extends StatefulWidget {
  const ShioriFeedbackHost({
    super.key,
    required this.observer,
    required this.child,
  });
  final Widget child;
  final ShioriFeedbackObserver observer;

  @override
  State<ShioriFeedbackHost> createState() => _ShioriFeedbackHostState();
}

class _ShioriFeedbackHostState extends State<ShioriFeedbackHost> {
  final _notices = <(BuildContext, String)>{};
  // Retain delivery across modals; Material still owns timers and animations.
  final _pending =
      Queue<
        ({SnackBar bar, bool Function() valid, (BuildContext, String)? notice})
      >();
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _ticket;
  bool _suspended = false, _consumed = false, _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.observer.changed = _changed;
  }

  void _changed() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      _sync();
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _sync();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _sync() {
    if (_ticket != null &&
        (!_pending.first.valid() || widget.observer.blocked && !_consumed)) {
      _suspended = _pending.first.valid() && !_consumed;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
    }
    _drain();
  }

  void _drain() {
    if (_ticket != null || widget.observer.blocked) return;
    while (_pending.isNotEmpty && !_pending.first.valid()) {
      _notices.remove(_pending.removeFirst().notice);
    }
    if (_pending.isEmpty) return;
    _consumed = false;
    final current = _pending.first;
    _ticket = ShioriFeedback._present(
      context,
      ScaffoldMessenger.of(context),
      current.bar,
    );
    _ticket!.closed.then((reason) {
      if (!mounted) return;
      _ticket = null;
      if (!_suspended || reason != SnackBarClosedReason.remove) {
        _notices.remove(_pending.removeFirst().notice);
      }
      _suspended = false;
      _drain();
    });
  }

  void show(
    BuildContext source,
    String message,
    ShioriFeedbackKind kind,
    String? actionLabel,
    VoidCallback? onAction,
    ModalRoute<dynamic>? route,
  ) {
    final transient = kind != ShioriFeedbackKind.error && onAction == null;
    final key = (source, message);
    if (transient && !_notices.add(key)) return;
    _pending.add((
      bar: ShioriFeedback._bar(
        message,
        kind,
        actionLabel,
        onAction == null
            ? null
            : () {
                _consumed = true;
                onAction();
              },
      ),
      valid: onAction == null
          ? () => true
          : () => source.mounted && route?.isActive != false,
      notice: transient ? key : null,
    ));
    if (onAction != null) route?.popped.then((_) => _changed());
    _drain();
  }

  @override
  void dispose() {
    widget.observer.changed = null;
    _pending.clear();
    _notices.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(
          1.0,
          constraints.maxWidth -
              media.padding.horizontal -
              ShioriSpace.item * 2,
        );
        final width = ShioriCapabilities.of(context).pointerFirst
            ? math.min(ShioriLayout.feedback, available)
            : available;
        final gutter =
            (constraints.maxWidth - media.padding.horizontal - width) / 2;
        return Theme(
          data: theme.copyWith(
            snackBarTheme: theme.snackBarTheme.copyWith(
              insetPadding: EdgeInsets.fromLTRB(
                gutter,
                0,
                gutter,
                ShioriSpace.item +
                    math.max(
                      0,
                      media.viewInsets.bottom - media.viewPadding.bottom,
                    ),
              ),
            ),
          ),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Theme(
              data: theme,
              child: MediaQuery(data: media, child: widget.child),
            ),
          ),
        );
      },
    );
  }
}
