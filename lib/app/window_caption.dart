import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme/shiori_theme.dart';

const _channel = MethodChannel('dev.shiori.reader/app');

/// Keeps the Windows title bar in the app's paper colour and brightness.
///
/// The system still draws the title bar, so dragging, snapping and the
/// system menu work as in any window. A system without caption colours, or
/// a failed call, leaves the frame as the system drew it.
class WindowCaptionSync extends StatefulWidget {
  const WindowCaptionSync({super.key, required this.child});
  final Widget child;

  @override
  State<WindowCaptionSync> createState() => _WindowCaptionSyncState();
}

class _WindowCaptionSyncState extends State<WindowCaptionSync> {
  (Color, Brightness)? _sent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final caption = (
      theme.extension<ShioriPalette>()?.paper ?? theme.scaffoldBackgroundColor,
      theme.brightness,
    );
    if (caption == _sent) return;
    _sent = caption;
    unawaited(_send(caption));
  }

  Future<void> _send((Color, Brightness) caption) async {
    try {
      await _channel.invokeMethod<bool>('setCaption', {
        'color': caption.$1.toARGB32(),
        'dark': caption.$2 == Brightness.dark,
      });
    } on PlatformException {
      // The frame keeps the system's colours.
    } on MissingPluginException {
      // A runner without the method, e.g. an older build.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
