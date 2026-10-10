import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Flutter 3.38's Windows engine requires int64 view IDs, while the standard
/// codec encodes small IDs as int32. Keep announcements intact until the pinned
/// SDK includes https://github.com/flutter/flutter/pull/180071.
/// Instantiate before runApp in both application entry points.
class ShioriWidgetsFlutterBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() {
    final messenger = super.createBinaryMessenger();
    return Platform.isWindows
        ? WindowsAccessibilityMessenger(messenger)
        : messenger;
  }
}

class WindowsAccessibilityMessenger extends BinaryMessenger {
  const WindowsAccessibilityMessenger(this.delegate);

  final BinaryMessenger delegate;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) => delegate.send(
    channel,
    channel == SystemChannels.accessibility.name && message != null
        ? _encodeAnnouncement(message)
        : message,
  );

  ByteData _encodeAnnouncement(ByteData message) {
    const codec = _AnnouncementCodec();
    // Unrelated events and invalid payloads still reach their original handler.
    try {
      final event = codec.decodeMessage(message);
      if (event is! Map || event['type'] != 'announce') return message;
      final data = event['data'];
      if (data is! Map || data['viewId'] is! int) return message;
      return codec.encodeMessage({
        ...event,
        'data': {...data, 'viewId': _ViewId(data['viewId'] as int)},
      })!;
    } on FormatException {
      return message;
    } on RangeError {
      return message;
    }
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      delegate.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) =>
      // Retain the delegate's incoming-message behavior, including in tests.
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(channel, data, callback);
}

class _ViewId {
  const _ViewId(this.value);
  final int value;
}

class _AnnouncementCodec extends StandardMessageCodec {
  const _AnnouncementCodec();

  @override
  void writeValue(WriteBuffer buffer, Object? value) {
    if (value is _ViewId) {
      buffer.putUint8(4); // StandardMessageCodec's int64 type tag.
      buffer.putInt64(value.value);
    } else {
      super.writeValue(buffer, value);
    }
  }
}
