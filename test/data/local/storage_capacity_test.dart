import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/files/storage_capacity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.shiori.reader/app');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'capacity is optional, nonnegative, and scoped to the requested volume',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'availableStorage');
        expect(call.arguments, '/volume');
        return 123;
      });
      expect(await availableStorageBytes(Directory('/volume')), 123);
      for (final value in [-1, null]) {
        messenger.setMockMethodCallHandler(channel, (_) async => value);
        expect(await availableStorageBytes(Directory('/volume')), isNull);
      }
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      expect(await availableStorageBytes(Directory('/volume')), isNull);
    },
  );
}
