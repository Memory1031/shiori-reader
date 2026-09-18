import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'epub_webview_host.dart';

/// A short authored page, not the renderer for normal long-form reading.
class EpubLayoutPage extends StatefulWidget {
  const EpubLayoutPage({
    super.key,
    required this.html,
    required this.onCenterTap,
    this.onPrevious,
    this.onNext,
    required this.onReady,
    this.onFailed,
  });
  final String html;
  final VoidCallback onCenterTap, onReady;
  final VoidCallback? onPrevious, onNext, onFailed;
  @override
  State<EpubLayoutPage> createState() => _EpubLayoutPageState();
}

class _EpubLayoutPageState extends State<EpubLayoutPage> {
  Offset? _down;
  Duration? _downTime;

  // Inlined documents can reach ~10 MiB, so identity stays on the inputs and
  // the string itself is rebuilt only when one of them changes.
  ({int html, Color paper, Color foreground, TargetPlatform platform})? _inputs;
  String? _document;

  ({int html, Color paper, Color foreground, TargetPlatform platform})
  _inputsOf(BuildContext context) => (
    html: identityHashCode(widget.html),
    paper: Theme.of(context).scaffoldBackgroundColor,
    foreground: Theme.of(context).colorScheme.onSurface,
    platform: defaultTargetPlatform,
  );

  String _documentOf(
    ({int html, Color paper, Color foreground, TargetPlatform platform}) inputs,
  ) {
    final cached = _document;
    if (cached != null && _inputs == inputs) return cached;
    final background = inputs.paper.toARGB32().toRadixString(16).substring(2);
    final foreground = inputs.foreground
        .toARGB32()
        .toRadixString(16)
        .substring(2);
    final interactionStyle = inputs.platform == TargetPlatform.windows
        ? 'html,body,body *{-webkit-user-select:none!important;user-select:none!important;-webkit-user-drag:none!important;}'
        : '';
    final document = widget.html.replaceFirst('</head>', '''<style>
html,body{background:#$background!important;color:#$foreground;margin:0!important;}
html,body{scrollbar-width:none;}
::-webkit-scrollbar{display:none;}
body{font-size:clamp(12px,5.7vw,20px);padding:8px!important;box-sizing:border-box;display:flow-root;overflow-wrap:break-word;}
img{max-width:100%;height:auto;}
$interactionStyle
</style></head>''');
    _inputs = inputs;
    return _document = document;
  }

  @override
  Widget build(BuildContext context) {
    final inputs = _inputsOf(context);
    final document = _documentOf(inputs);
    return LayoutBuilder(
      builder: (context, bounds) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          _down = e.localPosition;
          _downTime = e.timeStamp;
        },
        onPointerCancel: (_) {
          _down = null;
        },
        onPointerUp: (e) {
          final down = _down;
          _down = null;
          if (down == null) return;
          final delta = e.localPosition - down;
          if (delta.dx.abs() >= 48 && delta.dx.abs() > delta.dy.abs() * 1.5) {
            (delta.dx < 0 ? widget.onNext : widget.onPrevious)?.call();
          } else if (delta.distance < 8 &&
              e.timeStamp - _downTime! < const Duration(milliseconds: 350)) {
            if (down.dx < bounds.maxWidth * .25) {
              widget.onPrevious?.call();
            } else if (down.dx > bounds.maxWidth * .75) {
              widget.onNext?.call();
            } else {
              widget.onCenterTap();
            }
          }
        },
        child: _StaticWebView(
          key: ValueKey(inputs),
          document: document,
          onReady: widget.onReady,
          onFailed: widget.onFailed,
        ),
      ),
    );
  }
}

/// A fresh owner per document/theme rejects callbacks from retired native views.
class _StaticWebView extends StatefulWidget {
  const _StaticWebView({
    super.key,
    required this.document,
    required this.onReady,
    this.onFailed,
  });
  final String document;
  final VoidCallback onReady;
  final VoidCallback? onFailed;
  @override
  State<_StaticWebView> createState() => _StaticWebViewState();
}

class _StaticWebViewState extends State<_StaticWebView> {
  HeadlessInAppWebView? _headless;
  WebViewEnvironment? _environment;
  Timer? _deadline;
  bool _starting = false, _prepared = false, _attached = false;
  bool _loaded = false, _ready = false, _failed = false;

  InAppWebViewSettings get _settings => InAppWebViewSettings(
    javaScriptEnabled: false,
    javaScriptCanOpenWindowsAutomatically: false,
    supportMultipleWindows: true,
    blockNetworkLoads: true,
    allowFileAccess: false,
    allowContentAccess: false,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    domStorageEnabled: false,
    databaseEnabled: false,
    geolocationEnabled: false,
    disableContextMenu: true,
    transparentBackground: true,
    overScrollMode: OverScrollMode.NEVER,
    disallowOverScroll: true,
    useShouldOverrideUrlLoading: true,
    useOnRenderProcessGone: true,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_starting) {
      _starting = true;
      _deadline = Timer(const Duration(seconds: 15), _fail);
      unawaited(_prepare());
    }
  }

  Future<void> _prepare() async {
    try {
      _environment = await EpubWebViewHost.prepare(context);
      if (!mounted || _failed) return;
      // A Windows environment creates a new inline native view; the plugin
      // does not adopt the headless document. Wait for the visible view's load.
      if (_environment != null) {
        setState(() => _prepared = true);
        return;
      }
      final headless = _headless = HeadlessInAppWebView(
        webViewEnvironment: _environment,
        initialSettings: _settings,
        initialData: InAppWebViewInitialData(
          data: widget.document,
          baseUrl: WebUri('about:blank'),
        ),
        shouldOverrideUrlLoading: _navigation,
        onCreateWindow: (_, _) async => false,
        onPermissionRequest: (_, request) async => PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.DENY,
        ),
        onLoadStop: (_, _) => _loadFinished(),
        onReceivedError: (_, request, _) {
          if (request.isForMainFrame == true) _fail();
        },
        onRenderProcessGone: (_, _) => _fail(),
        onWebContentProcessDidTerminate: (_) => _fail(),
      );
      // Native creation is awaitable here, unlike an inline platform view's initState.
      await headless.run();
      if (!mounted || _failed) {
        await _disposeHeadless(headless);
        return;
      }
      setState(() => _prepared = true);
    } catch (_) {
      _fail();
    }
  }

  Future<NavigationActionPolicy> _navigation(
    InAppWebViewController _,
    NavigationAction action,
  ) async {
    final url = action.request.url?.toString();
    return url == 'about:blank'
        ? NavigationActionPolicy.ALLOW
        : NavigationActionPolicy.CANCEL;
  }

  void _loadFinished() {
    _loaded = true;
    _notifyReady();
  }

  void _notifyReady() {
    if (!mounted || _failed || _ready || !_loaded || !_attached) return;
    _ready = true;
    _deadline?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_failed) widget.onReady();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _fail() {
    if (!mounted || _failed) return;
    _failed = true;
    _deadline?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFailed?.call();
    });
    setState(() {});
  }

  Future<void> _disposeHeadless(HeadlessInAppWebView? view) async {
    try {
      await view?.dispose();
    } catch (_) {
      // A failed native creation may have no native resource to dispose.
    }
  }

  @override
  void dispose() {
    _deadline?.cancel();
    unawaited(_disposeHeadless(_headless));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_prepared || _failed) return const SizedBox.expand();
    return InAppWebView(
      headlessWebView: _headless,
      webViewEnvironment: _environment,
      initialSettings: _settings,
      initialData: _headless == null
          ? InAppWebViewInitialData(
              data: widget.document,
              baseUrl: WebUri('about:blank'),
            )
          : null,
      onWebViewCreated: (_) {
        _attached = true;
        _notifyReady();
      },
      shouldOverrideUrlLoading: _navigation,
      onCreateWindow: (_, _) async => false,
      onPermissionRequest: (_, request) async => PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      ),
      onLoadStop: (_, _) => _loadFinished(),
      onReceivedError: (_, request, _) {
        if (request.isForMainFrame == true) _fail();
      },
      onRenderProcessGone: (_, _) => _fail(),
      onWebContentProcessDidTerminate: (_) => _fail(),
      gestureRecognizers: {
        Factory<VerticalDragGestureRecognizer>(
          () => VerticalDragGestureRecognizer(),
        ),
      },
    );
  }
}
