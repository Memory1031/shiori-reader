import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'epub_webview_host.dart';
import 'reader_tap_zones.dart';
import 'svg_paper_art.dart';
import '../../shared/capabilities.dart';
import '../../domain/contracts/local_content_links.dart';
import '../../shared/epub_link_address.dart';

/// The exact themed document loaded by the static native host.
String epubLayoutDocument(
  String html,
  Color paper,
  Color foreground,
  Brightness brightness,
  bool pointerFirst,
) {
  final background = paper.toARGB32().toRadixString(16).substring(2);
  final ink = foreground.toARGB32().toRadixString(16).substring(2);
  // Mouse drags turn pages; keep them from selecting or dragging content.
  final interactionStyle = pointerFirst
      ? 'html,body,body *{-webkit-user-select:none!important;user-select:none!important;-webkit-user-drag:none!important;}'
      : '';
  final svgTextStyle =
      brightness == Brightness.dark && html.contains('class="shiori-svg-page"')
      ? 'body.shiori-svg-page>svg text:not([fill]){fill:#$ink;}'
      : '';
  // The first anonymous layer stays below authored layers and unlayered rules.
  // Engines without cascade layers ignore this optional width protection.
  final document = html.replaceFirst(
    '<head>',
    '<head><meta http-equiv="Content-Security-Policy" content="script-src \'none\'; connect-src \'none\'; base-uri \'none\'; form-action \'none\'"><style>@layer{:where(body:not(.shiori-svg-page) p){max-width:100%;}}</style>',
  );
  return document.replaceFirst('</head>', '''<style>
html,body{background:#$background!important;color:#$ink;margin:0!important;}
html,body{scrollbar-width:none;}
::-webkit-scrollbar{display:none;}
body{font-size:clamp(12px,5.7vw,20px);padding:8px!important;box-sizing:border-box;display:flow-root;overflow-wrap:break-word;}
img{max-width:100%;height:auto;}
$svgTextStyle
$interactionStyle
</style></head>''');
}

/// A short authored page, not the renderer for normal long-form reading.
class EpubLayoutPage extends StatefulWidget {
  const EpubLayoutPage({
    super.key,
    required this.html,
    required this.onCenterTap,
    this.chromeVisible,
    this.onPrevious,
    this.onNext,
    required this.onReady,
    this.onFailed,
    this.links = const [],
    this.onLink,
    this.prepareArtwork = themedSvgPaperArtwork,
  });
  final Future<String> Function(String html, Color ink) prepareArtwork;
  final List<LocalContentLink> links;
  final ValueChanged<LocalContentLink>? onLink;
  final String html;
  final VoidCallback onCenterTap, onReady;

  /// While true, taps dismiss the reader chrome instead of turning pages.
  final ValueListenable<bool>? chromeVisible;
  final VoidCallback? onPrevious, onNext, onFailed;
  @override
  State<EpubLayoutPage> createState() => _EpubLayoutPageState();
}

class _EpubLayoutPageState extends State<EpubLayoutPage>
    with WidgetsBindingObserver {
  Offset? _down;
  Duration? _downTime;
  String? _loadedDocument;
  String? _reportedDocument;
  bool get _ready =>
      !_artworkPending &&
      _document != null &&
      identical(_loadedDocument, _document);
  String? _preparedHtml;
  String? _preparingSource;
  Color? _preparingInk;
  bool _artworkPending = false;
  int _viewGeneration = 0;
  int _artworkGeneration = 0;
  int _tapRequest = 0;
  InAppWebViewController? _webController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // A foreground return cannot revive a hit query from an interrupted tap.
      _tapRequest++;
      _down = null;
      _downTime = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _prepareArtwork(String html, Color ink, {required bool keepView}) {
    if (identical(_preparingSource, html) && _preparingInk == ink) return;
    final sameSource = identical(_preparingSource, html);
    _preparingSource = html;
    _preparingInk = ink;
    final generation = ++_artworkGeneration;
    if (!keepView || !sameSource) _preparedHtml = null;
    _artworkPending = false;
    if (!html.contains('class="shiori-svg-page"')) {
      _preparedHtml = html;
      return;
    }
    _artworkPending = true;
    unawaited(
      widget.prepareArtwork(html, ink).then((prepared) {
        if (mounted && generation == _artworkGeneration) {
          setState(() {
            _preparedHtml = prepared;
            _artworkPending = false;
          });
        }
      }),
    );
  }

  @override
  void didUpdateWidget(covariant EpubLayoutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.html, widget.html)) {
      _viewGeneration++;
      _down = null;
      _loadedDocument = null;
      _reportedDocument = null;
    }
  }

  Rect _regionRect(LocalLinkRegion region, Size size) {
    // Matches the sanitized SVG's xMidYMin meet, including side letterboxing.
    final width = size.width < size.height * region.aspectRatio
        ? size.width
        : size.height * region.aspectRatio;
    final height = width / region.aspectRatio;
    final left = (size.width - width) / 2;
    return Rect.fromLTRB(
      left + region.left * width,
      region.top * height,
      left + region.right * width,
      region.bottom * height,
    );
  }

  LocalContentLink? _linkAt(Offset point, Size size) {
    if (!_ready || widget.onLink == null) return null;
    for (final link in widget.links.reversed) {
      if (link.region case final region?) {
        if (_regionRect(region, size).contains(point)) return link;
      }
    }
    return null;
  }

  void _pageTap(Offset point, Size size) {
    switch (readerTapZone(
      point.dx,
      size.width,
      chromeVisible: widget.chromeVisible?.value ?? false,
    )) {
      case ReaderTap.previous:
        widget.onPrevious?.call();
      case ReaderTap.next:
        widget.onNext?.call();
      case ReaderTap.center:
        widget.onCenterTap();
    }
  }

  Future<void> _textPageTap(Offset point, Size size) async {
    final controller = _webController;
    final document = _document;
    final request = _tapRequest;
    if (!_ready ||
        controller == null ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    try {
      // The browser owns transformed glyphs, wrapping, scrolling and zoom.
      // This fixed host query only decides whether the reader may also tap;
      // the canceled native link callback is the sole navigation dispatcher.
      final address = await controller
          .evaluateJavascript(
            source:
                '''(function(){
const v=window.visualViewport;
const x=${point.dx / size.width}*(v?v.width:window.innerWidth)+(v?v.offsetLeft:0);
const y=${point.dy / size.height}*(v?v.height:window.innerHeight)+(v?v.offsetTop:0);
const e=document.elementFromPoint(x,y);
const a=e&&e.closest('a[href^="$epubLinkPrefix"]');
return a?a.getAttribute('href'):null;
})()''',
          )
          .timeout(const Duration(seconds: 2));
      if (!mounted ||
          request != _tapRequest ||
          !_ready ||
          !identical(document, _document) ||
          !identical(controller, _webController) ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      if (address == null) _pageTap(point, size);
    } catch (_) {
      // A failed or late hit test must not turn a link into a page turn.
    }
  }

  // Inlined documents can reach ~10 MiB. The source string is held by
  // reference and compared with identical(), so no multi-MiB hashing or
  // equality ever runs; the generation keys the webview owner instead of the
  // document itself. identity hashes are avoided on purpose: they are not
  // unique and can be reused after the old string is collected.
  String? _sourceHtml;
  Color? _paper;
  Color? _foreground;
  Brightness? _brightness;
  bool? _pointerFirst;
  int _generation = 0;
  String? _document;

  String _documentOf(
    String html,
    Color paper,
    Color foreground,
    Brightness brightness,
    bool pointerFirst,
  ) {
    final cached = _document;
    if (cached != null &&
        identical(_sourceHtml, html) &&
        _paper == paper &&
        _foreground == foreground &&
        _brightness == brightness &&
        _pointerFirst == pointerFirst) {
      return cached;
    }
    final document = epubLayoutDocument(
      html,
      paper,
      foreground,
      brightness,
      pointerFirst,
    );
    _sourceHtml = html;
    _paper = paper;
    _foreground = foreground;
    _brightness = brightness;
    _pointerFirst = pointerFirst;
    _generation++;
    _down = null;
    return _document = document;
  }

  void _reportReady() {
    if (!mounted || !_ready || identical(_reportedDocument, _document)) return;
    _reportedDocument = _document;
    widget.onReady();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inlineView = EpubWebViewHost.usesInlineView(context);
    _prepareArtwork(
      widget.html,
      theme.colorScheme.onSurface,
      keepView: inlineView,
    );
    if (_preparedHtml == null) {
      return ColoredBox(color: theme.scaffoldBackgroundColor);
    }
    final document = _artworkPending && _document != null
        ? _document!
        : _documentOf(
            _preparedHtml!,
            theme.scaffoldBackgroundColor,
            theme.colorScheme.onSurface,
            theme.brightness,
            ShioriCapabilities.of(context).pointerFirst,
          );
    // Artwork may resolve to the document already loaded by the retained
    // owner. No navigation (and therefore no new load callback) is needed.
    if (_ready && !identical(_reportedDocument, document)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportReady());
    }
    return LayoutBuilder(
      builder: (context, bounds) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          _tapRequest++;
          // Only a primary press may navigate or turn the page. Pointer-up
          // no longer carries the released mouse button, so decide here.
          _down = e.buttons == kPrimaryButton ? e.localPosition : null;
          _downTime = _down == null ? null : e.timeStamp;
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
            // The enclosing Listener receives taps even when the native
            // WebView wins the gesture arena. Dispatch links here so a
            // hotspot in the center cannot turn into a Chrome tap or vanish.
            if (_linkAt(down, bounds.biggest) case final link?) {
              widget.onLink?.call(link);
              return;
            }
            if (widget.html.contains('href="$epubLinkPrefix')) {
              unawaited(_textPageTap(down, bounds.biggest));
            } else {
              _pageTap(down, bounds.biggest);
            }
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _StaticWebView(
              key: ValueKey(inlineView ? _viewGeneration : _generation),
              document: document,
              onController: (controller) {
                if (identical(document, _document)) _webController = controller;
              },
              onTextLink: (id) {
                if (!mounted ||
                    !_ready ||
                    !identical(document, _document) ||
                    ModalRoute.of(context)?.isCurrent == false) {
                  return;
                }
                _tapRequest++;
                final link = widget.links
                    .where((link) => link.presentationId == id)
                    .firstOrNull;
                if (link != null) widget.onLink?.call(link);
              },
              onReady: () {
                if (!identical(document, _document)) return;
                setState(() => _loadedDocument = document);
                _reportReady();
              },
              onFailed: () {
                setState(() => _loadedDocument = null);
                widget.onFailed?.call();
              },
            ),
            if (_ready && widget.onLink != null)
              for (final link in widget.links)
                if (link.region case final region?)
                  Positioned.fromRect(
                    rect: _regionRect(region, bounds.biggest),
                    child: Semantics(
                      label: link.label,
                      link: true,
                      onTap: () => widget.onLink?.call(link),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Windows reloads static theme data on its inline owner, one document at a
/// time. Mobile keeps its existing headless owner per document/theme.
class _StaticWebView extends StatefulWidget {
  const _StaticWebView({
    super.key,
    required this.document,
    required this.onReady,
    this.onFailed,
    required this.onController,
    required this.onTextLink,
  });
  final String document;
  final VoidCallback onReady;
  final VoidCallback? onFailed;
  final ValueChanged<InAppWebViewController> onController;
  final ValueChanged<int> onTextLink;
  @override
  State<_StaticWebView> createState() => _StaticWebViewState();
}

class _StaticWebViewState extends State<_StaticWebView> {
  HeadlessInAppWebView? _headless;
  WebViewEnvironment? _environment;
  Timer? _deadline;
  bool _starting = false, _prepared = false, _attached = false;
  bool _loaded = false, _ready = false, _failed = false;
  InAppWebViewController? _controller;
  InAppWebView? _view;
  String? _loadingDocument;
  Offset? _themeScrollOffset;
  bool _restoringScroll = false;

  @override
  void didUpdateWidget(_StaticWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document) &&
        _environment != null) {
      _ready = false;
      // An in-flight navigation finishes before loading the newest theme.
      // WebView2's about:blank load callbacks carry no document identity.
      if (_loaded && _controller != null) unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    if (!mounted || _failed || _controller == null) return;
    _loaded = false;
    _ready = false;
    _deadline?.cancel();
    _deadline = Timer(const Duration(seconds: 15), _fail);
    try {
      // Keep the original position across superseded theme navigations. The
      // Windows plugin does not implement getScrollY/scrollTo; ExecuteScript
      // runs these fixed host commands while authored JavaScript stays disabled.
      if (_themeScrollOffset == null) {
        try {
          final position = await _controller!.evaluateJavascript(
            source: '[window.scrollX, window.scrollY]',
          );
          if (position is List &&
              position.length == 2 &&
              position.every((value) => value is num && value.isFinite)) {
            _themeScrollOffset = Offset(
              (position[0] as num).toDouble(),
              (position[1] as num).toDouble(),
            );
          }
        } catch (_) {
          // An unavailable position must not prevent the theme from loading.
        }
      }
      if (!mounted || _failed) return;
      _loadingDocument = widget.document;
      await _controller!.loadData(
        data: _loadingDocument!,
        baseUrl: WebUri('about:blank'),
      );
    } catch (_) {
      _fail();
    }
  }

  InAppWebViewSettings get _settings => InAppWebViewSettings(
    // Android requires this for the fixed DOM hit query. Authored scripts
    // remain stripped and forbidden by both parser and host CSPs.
    javaScriptEnabled: widget.document.contains('href="$epubLinkPrefix'),
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
        _loadingDocument = widget.document;
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
        onReceivedError: (_, request, _) => _receivedError(request),
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
    final id = epubLinkId(action.request.url?.toString());
    if (mounted &&
        _ready &&
        !_failed &&
        action.isForMainFrame &&
        action.hasGesture != false &&
        id != null) {
      widget.onTextLink(id);
    }
    final url = action.request.url?.toString();
    return url == 'about:blank'
        ? NavigationActionPolicy.ALLOW
        : NavigationActionPolicy.CANCEL;
  }

  void _receivedError(WebResourceRequest request) {
    // WebView2 reports the intentionally canceled host-link request as an
    // error. It must not retire the readable static document or its owner.
    if (request.isForMainFrame == true &&
        epubLinkId(request.url.toString()) == null) {
      _fail();
    }
  }

  Future<void> _loadFinished() async {
    if (!mounted || _failed || _restoringScroll) return;
    if (_environment != null && !identical(_loadingDocument, widget.document)) {
      unawaited(_reload());
      return;
    }
    final offset = _themeScrollOffset;
    if (offset != null) {
      _restoringScroll = true;
      try {
        await _controller!.evaluateJavascript(
          source: 'window.scrollTo(${offset.dx}, ${offset.dy})',
        );
      } catch (_) {
        // Keep the readable document if the native view rejects restoration.
      } finally {
        _restoringScroll = false;
      }
      if (!mounted || _failed) return;
      if (!identical(_loadingDocument, widget.document)) {
        unawaited(_reload());
        return;
      }
    }
    _themeScrollOffset = null;
    _loaded = true;
    _notifyReady();
  }

  void _notifyReady() {
    if (!mounted || _failed || _ready || !_loaded || !_attached) return;
    _ready = true;
    final document = widget.document;
    _deadline?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_failed &&
          _ready &&
          identical(document, widget.document)) {
        widget.onReady();
      }
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
    // The plugin creates its platform owner in the Widget constructor, so
    // retaining only a Flutter State/key is insufficient to retain WebView2.
    return _view ??= InAppWebView(
      headlessWebView: _headless,
      webViewEnvironment: _environment,
      initialSettings: _settings,
      initialData: _headless == null
          ? InAppWebViewInitialData(
              data: _loadingDocument ?? widget.document,
              baseUrl: WebUri('about:blank'),
            )
          : null,
      onWebViewCreated: (controller) {
        _controller = controller;
        widget.onController(controller);
        _attached = true;
        if (_loaded &&
            !identical(_loadingDocument, widget.document) &&
            _environment != null) {
          unawaited(_reload());
          return;
        }
        _notifyReady();
      },
      shouldOverrideUrlLoading: _navigation,
      onCreateWindow: (_, _) async => false,
      onPermissionRequest: (_, request) async => PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      ),
      onLoadStop: (_, _) => _loadFinished(),
      onReceivedError: (_, request, _) => _receivedError(request),
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
