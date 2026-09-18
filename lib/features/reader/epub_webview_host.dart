import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Owns the shared Windows browser environment; reader pages borrow it.
/// Initialization is lazy so ordinary reading never depends on WebView2.
class EpubWebViewHost extends StatefulWidget {
  const EpubWebViewHost({
    super.key,
    required this.userDataDirectory,
    required this.child,
    this.operatingSystem,
  });

  final Directory userDataDirectory;
  final Widget child;

  /// Composition override for platform-boundary tests.
  final String? operatingSystem;

  static Future<WebViewEnvironment?> prepare(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_EnvironmentScope>();
    if (scope != null) return scope.prepare();
    if (!Platform.isWindows) {
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        return Future.value();
      }
      return Future.error(UnsupportedError('WebView is unavailable'));
    }
    return Future.error(StateError('Missing WebView environment owner'));
  }

  @override
  State<EpubWebViewHost> createState() => _EpubWebViewHostState();
}

class _EpubWebViewHostState extends State<EpubWebViewHost> {
  Future<WebViewEnvironment?>? _environment;

  Future<WebViewEnvironment?> _prepare() => _environment ??= _create();

  Future<WebViewEnvironment?> _create() async {
    final platform = widget.operatingSystem ?? Platform.operatingSystem;
    if (platform != 'windows') {
      if (['android', 'ios', 'macos'].contains(platform)) return null;
      throw UnsupportedError('WebView is unavailable');
    }
    final version = await WebViewEnvironment.getAvailableVersion();
    if (version == null || version.isEmpty) {
      throw UnsupportedError('WebView2 Runtime is unavailable');
    }
    final directory = widget.userDataDirectory;
    await directory.create(recursive: true);
    return WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(userDataFolder: directory.path),
    );
  }

  @override
  void dispose() {
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() async {
    try {
      final environment = await _environment;
      await environment?.dispose();
    } catch (_) {
      // Initialization failure is handled by the page's native fallback.
    }
  }

  @override
  Widget build(BuildContext context) =>
      _EnvironmentScope(prepare: _prepare, child: widget.child);
}

class _EnvironmentScope extends InheritedWidget {
  const _EnvironmentScope({required this.prepare, required super.child});
  final Future<WebViewEnvironment?> Function() prepare;
  @override
  bool updateShouldNotify(_EnvironmentScope oldWidget) => false;
}
