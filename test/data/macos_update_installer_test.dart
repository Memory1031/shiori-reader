import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/updates/macos_update_installer.dart';
import 'package:shiori/data/updates/update_manifest.dart';
import 'package:shiori/domain/contracts/app_updates.dart';
import '../support/update_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.shiori.reader/update');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final fixtures = UpdateFixtures();
  final manifest = UpdateManifest.verifyAndRead(
    fixtures.bytes('manifest'),
    fixtures.bytes('signature'),
    fixtures.key,
    expectedTag: 'v1.2.1-beta.1',
  );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native verification and handoff precede store shutdown and exit',
    () async {
      final calls = <String>[];
      final installer = MacOSUpdateInstaller(
        prepareExit: () async {
          calls.add('close-stores');
        },
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'start'
            ? 'installing'
            : call.method == 'exit'
            ? null
            : 'idle';
      });
      await installer.install(
        File('/fixture/package.zip'),
        manifest.identity,
        manifest.assets.singleWhere(
          (asset) => asset.platform == 'macos-universal',
        ),
        fixtures.bytes('manifest'),
        fixtures.bytes('signature'),
      );
      expect(calls, ['prepare', 'start', 'close-stores', 'exit']);
    },
  );
  test('rejected package or handoff leaves stores open', () async {
    for (final rejected in ['prepare', 'start']) {
      var closed = false;
      final calls = <String>[];
      final installer = MacOSUpdateInstaller(
        prepareExit: () async {
          closed = true;
        },
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == rejected) {
          throw PlatformException(code: 'verification');
        }
        return 'idle';
      });
      await expectLater(
        installer.install(
          File('/fixture/package.zip'),
          manifest.identity,
          manifest.assets.singleWhere(
            (asset) => asset.platform == 'macos-universal',
          ),
          fixtures.bytes('manifest'),
          fixtures.bytes('signature'),
        ),
        throwsA(isA<UpdateIssue>()),
      );
      expect(closed, isFalse);
      expect(calls, isNot(contains('exit')));
    }
  });
}
