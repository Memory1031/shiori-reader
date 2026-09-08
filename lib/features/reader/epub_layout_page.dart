import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  late final WebViewController _controller;
  String? _document;
  Offset? _down;
  Duration? _downTime;
  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              request.url == 'about:blank' ||
                  request.url.startsWith('data:text/html')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              widget.onFailed?.call();
            }
          },
          onPageFinished: (_) {
            if (mounted) widget.onReady();
          },
        ),
      );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(EpubLayoutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurface
        .toARGB32()
        .toRadixString(16)
        .substring(2);
    final document = widget.html.replaceFirst('</head>', '''<style>
html,body{background:transparent!important;color:#$foreground;margin:0!important;}
body{font-size:clamp(12px,5.7vw,20px);padding:8px!important;box-sizing:border-box;display:flow-root;overflow-wrap:break-word;}
img{max-width:100%;height:auto;}
</style></head>''');
    if (document == _document) return;
    _document = document;
    _controller.loadHtmlString(document);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Listener(
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
      child: WebViewWidget(
        controller: _controller,
        gestureRecognizers: {
          Factory<VerticalDragGestureRecognizer>(
            () => VerticalDragGestureRecognizer(),
          ),
        },
      ),
    ),
  );
}
