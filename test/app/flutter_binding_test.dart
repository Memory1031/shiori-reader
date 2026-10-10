import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/flutter_binding.dart';

const standardCodec = StandardMessageCodec();

/// Preserve the wire type, as Windows' native standard codec does.
class WireInt {
  WireInt(this.value, this.bits);
  final int value, bits;
}

class NativeCodec extends StandardMessageCodec {
  const NativeCodec();

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) => switch (type) {
    3 => WireInt(buffer.getInt32(), 32),
    4 => WireInt(buffer.getInt64(), 64),
    _ => super.readValueOfType(type, buffer),
  };
}

class RecordingMessenger extends BinaryMessenger {
  final sent = <({String channel, ByteData? data})>[];
  final handlers = <String, MessageHandler?>{};
  final response = standardCodec.encodeMessage(null);

  @override
  Future<ByteData?> send(String channel, ByteData? message) async {
    sent.add((channel: channel, data: message));
    return response;
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      handlers[channel] = handler;

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async => callback?.call(await handlers[channel]?.call(data));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Windows announcements preserve values and encode only viewId as int64',
    () async {
      for (final id in [0, 7, 0x80000000]) {
        final native = RecordingMessenger();
        final message = {
          'type': 'announce',
          'data': {
            'viewId': id,
            'message': '已展开 — Expanded',
            'textDirection': 1,
            'assertiveness': 0,
          },
        };
        final reply = await WindowsAccessibilityMessenger(native).send(
          SystemChannels.accessibility.name,
          standardCodec.encodeMessage(message),
        );
        final payload = native.sent.single.data;
        expect(standardCodec.decodeMessage(payload), message);
        final data =
            (const NativeCodec().decodeMessage(payload) as Map)['data'] as Map;
        expect((data['viewId'] as WireInt).bits, 64);
        expect((data['viewId'] as WireInt).value, id);
        expect((data['textDirection'] as WireInt).bits, 32);
        expect((data['assertiveness'] as WireInt).bits, 32);
        expect(reply, same(native.response));
      }
    },
  );

  test('other messages and incoming handlers are passed through', () async {
    final native = RecordingMessenger();
    final messenger = WindowsAccessibilityMessenger(native);
    final tooltip = standardCodec.encodeMessage({
      'type': 'tooltip',
      'data': {'message': 'Help'},
    });
    final missingView = standardCodec.encodeMessage({
      'type': 'announce',
      'data': {'message': 'Help'},
    });
    final invalid = ByteData(1)..setUint8(0, 255);
    for (final data in [tooltip, missingView, invalid, null]) {
      await messenger.send(SystemChannels.accessibility.name, data);
      expect(native.sent.last.data, same(data));
    }
    await messenger.send('other/channel', missingView);
    expect(native.sent.last.channel, 'other/channel');
    expect(native.sent.last.data, same(missingView));
    Future<ByteData?> handler(ByteData? data) async => data;
    messenger.setMessageHandler('incoming', handler);
    expect(native.handlers['incoming'], same(handler));
    ByteData? response;
    await messenger.handlePlatformMessage(
      'incoming',
      tooltip,
      (data) => response = data,
    );
    expect(response, same(tooltip));
    messenger.setMessageHandler('incoming', null);
    expect(native.handlers['incoming'], isNull);
  });

  testWidgets(
    'real ExpansionTile expand and collapse retain announcements',
    (tester) async {
      final native = RecordingMessenger();
      final messenger = WindowsAccessibilityMessenger(native);
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        SystemChannels.accessibility.name,
        (message) => messenger.send(SystemChannels.accessibility.name, message),
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          SystemChannels.accessibility.name,
          null,
        );
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExpansionTile(
              title: Text('Completed books'),
              children: [Text('Book details')],
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(ExpansionTile));
      final localizations = MaterialLocalizations.of(context);
      for (final hint in [
        localizations.collapsedHint,
        localizations.expandedHint,
      ]) {
        await tester.tap(find.text('Completed books'));
        await tester.pumpAndSettle();
        final data =
            (const NativeCodec().decodeMessage(native.sent.last.data)
                    as Map)['data']
                as Map;
        expect((data['viewId'] as WireInt).bits, 64);
        expect((data['viewId'] as WireInt).value, tester.view.viewId);
        expect(data['message'], hint);
      }
      final announcements = native.sent.where(
        (event) =>
            (standardCodec.decodeMessage(event.data) as Map)['type'] ==
            'announce',
      );
      expect(announcements, hasLength(2));
      expect(tester.takeException(), isNull);
      await SemanticsService.sendAnnouncement(
        tester.view,
        '直接播报',
        TextDirection.rtl,
        assertiveness: Assertiveness.assertive,
      );
      final event = standardCodec.decodeMessage(native.sent.last.data) as Map;
      expect(event['data'], {
        'viewId': tester.view.viewId,
        'message': '直接播报',
        'textDirection': TextDirection.rtl.index,
        'assertiveness': Assertiveness.assertive.index,
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
