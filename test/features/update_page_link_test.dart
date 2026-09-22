import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/update_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.shiori.reader/app');
  test(
    'project and release links use the platform opener; other URLs do not',
    () async {
      final opened = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'openRelease');
            opened.add(call.arguments as String);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      for (final path in ['', '/releases/tag/v1.2.2']) {
        expect(
          await openUpdatePage(
            Uri.parse('https://github.com/Memory1031/shiori-reader$path'),
          ),
          isTrue,
        );
      }
      for (final url in [
        'http://github.com/Memory1031/shiori-reader',
        'https://github.com:444/Memory1031/shiori-reader',
        'https://user@github.com/Memory1031/shiori-reader',
        'https://github.com/Memory1031/shiori-reader-other',
        'https://github.com/Memory1031/shiori-reader?next=elsewhere',
        'https://github.com/Memory1031/shiori-reader#fragment',
        'https://example.com/Memory1031/shiori-reader',
      ]) {
        expect(await openUpdatePage(Uri.parse(url)), isFalse);
      }
      expect(opened, hasLength(2));
    },
  );
}
