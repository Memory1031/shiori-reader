import 'dart:io';
import 'package:flutter/services.dart';

/// Null means unavailable; bounded writes and rollback remain authoritative.
Future<int?> availableStorageBytes(Directory directory) async {
  try {
    final bytes = await const MethodChannel(
      'dev.shiori.reader/app',
    ).invokeMethod<int>('availableStorage', directory.path);
    return bytes != null && bytes >= 0 ? bytes : null;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
