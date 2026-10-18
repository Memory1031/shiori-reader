import 'dart:ui' show AppExitResponse;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../shared/widgets/state_views.dart';

/// One normal-exit owner: save first, retire pages, then close app stores.
class AppExitScope extends StatefulWidget {
  const AppExitScope({
    super.key,
    required this.child,
    required this.save,
    this.shutdown,
  });
  final Widget child;
  final Future<bool> Function() save;
  final Future<void> Function()? shutdown;

  static AppExitScopeState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ExitScope>()?.owner;

  @override
  State<AppExitScope> createState() => AppExitScopeState();
}

class AppExitScopeState extends State<AppExitScope>
    with WidgetsBindingObserver {
  final _savers = <Future<bool> Function()>{};
  Future<AppExitResponse>? _request;
  bool _saving = false, _retired = false;
  bool get saving => _saving;

  void Function() register(Future<bool> Function() save) {
    _savers.add(save);
    return () => _savers.remove(save);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() =>
      _request ??= _exit().whenComplete(() {
        if (!_retired) _request = null;
      });

  Future<AppExitResponse> _exit() async {
    final focus = FocusManager.instance.primaryFocus;
    setState(() => _saving = true);
    try {
      await _setExitPending(true);
      WidgetsBinding.instance.scheduleForcedFrame();
      await WidgetsBinding.instance.endOfFrame;
      var saved = await widget.save();
      for (final save in _savers.toList().reversed) {
        if (_savers.contains(save)) saved = await save() && saved;
      }
      if (!saved || !mounted) return AppExitResponse.cancel;
      setState(() => _retired = true);
      // Reader disposal releases book uses before store.close waits for them.
      WidgetsBinding.instance.scheduleForcedFrame();
      await WidgetsBinding.instance.endOfFrame;
      try {
        await widget.shutdown?.call();
      } catch (_) {
        // Saves succeeded; startup recovery owns any interrupted cleanup.
      }
      return AppExitResponse.exit;
    } catch (_) {
      return AppExitResponse.cancel;
    } finally {
      if (!_retired) await _setExitPending(false);
      if (mounted && !_retired) {
        setState(() => _saving = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && focus?.context != null) focus?.requestFocus();
        });
      }
    }
  }

  Future<void> _setExitPending(bool pending) async {
    if (!Platform.isWindows) return;
    try {
      await const MethodChannel(
        'dev.shiori.reader/app',
      ).invokeMethod<bool>('setExitPending', pending);
    } on MissingPluginException {
      // Older runners and widget hosts do not expose instance activation.
    } on PlatformException {
      // Saving and closing must remain available if native activation fails.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ExitScope(
    owner: this,
    child: _retired
        ? Scaffold(
            body: Center(
              child: LoadingView(
                message: AppLocalizations.of(context).appClosing,
              ),
            ),
          )
        : ExcludeFocus(
            excluding: _saving,
            child: AbsorbPointer(absorbing: _saving, child: widget.child),
          ),
  );
}

class _ExitScope extends InheritedWidget {
  const _ExitScope({required this.owner, required super.child});
  final AppExitScopeState owner;
  @override
  bool updateShouldNotify(_ExitScope oldWidget) => owner != oldWidget.owner;
}
