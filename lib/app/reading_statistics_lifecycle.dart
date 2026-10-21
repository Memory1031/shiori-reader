import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../domain/contracts/contracts.dart';
import '../features/statistics/reading_statistics_controller.dart';

/// Desktop focus and sleep supplement Flutter's application/view lifecycle.
class ReadingStatisticsLifecycle {
  ReadingStatisticsLifecycle(
    this.controller, {
    MethodChannel? channel,
    bool? desktop,
  }) : channel = channel ?? const MethodChannel('dev.shiori.reader/reading'),
       desktop = desktop ?? (Platform.isWindows || Platform.isMacOS);
  final ReadingStatisticsController controller;
  final MethodChannel channel;
  final bool desktop;
  bool _closed = false;
  Future<void> start() async {
    if (!desktop) return;
    controller.refreshEnvironment = refresh;
    controller.environment(available: false);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'state' && !_closed) _apply(call.arguments);
    });
    await refresh();
  }

  bool _apply(Object? value) {
    if (value is! Map ||
        value['available'] is! bool ||
        value['wake'] is! bool) {
      _failed();
      return false;
    }
    controller.environment(
      available: value['available'] as bool,
      forgetActivity: value['wake'] as bool,
    );
    return true;
  }

  void _failed() {
    if (_closed) return;
    controller.environment(available: false);
    controller.reportPlatformFailure(
      AppFailure(
        kind: FailureKind.unsupported,
        operation: Operation.libraryRead,
      ),
    );
  }

  Future<bool> refresh() async {
    if (_closed) return false;
    try {
      final value = await channel
          .invokeMethod<Object?>('state')
          .timeout(const Duration(seconds: 2));
      return !_closed && _apply(value);
    } on TimeoutException {
      _failed();
      return false;
    } on PlatformException {
      _failed();
      return false;
    } on MissingPluginException {
      _failed();
      return false;
    }
  }

  void close() {
    _closed = true;
    if (desktop) channel.setMethodCallHandler(null);
    controller.refreshEnvironment = null;
  }
}
