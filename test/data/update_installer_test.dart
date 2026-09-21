import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/updates/update_installer.dart';
import 'package:shiori/domain/contracts/app_updates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const installer = AndroidUpdateInstaller();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(
      AndroidUpdateInstaller.channel,
      null,
    ),
  );
  test('native permission and cancellation states remain explicit', () async {
    for (final state in UpdateInstallState.values) {
      messenger.setMockMethodCallHandler(
        AndroidUpdateInstaller.channel,
        (_) async => state.name,
      );
      expect(await installer.status(), state);
    }
  });
  test(
    'native rejection maps to verification without exposing diagnostics',
    () async {
      messenger.setMockMethodCallHandler(
        AndroidUpdateInstaller.channel,
        (_) async => throw PlatformException(
          code: 'verification',
          message: 'private path',
        ),
      );
      await expectLater(
        installer.status(),
        throwsA(
          isA<UpdateIssue>().having(
            (e) => e.problem,
            'problem',
            UpdateProblem.verification,
          ),
        ),
      );
    },
  );
  test('unknown native state fails closed', () async {
    messenger.setMockMethodCallHandler(
      AndroidUpdateInstaller.channel,
      (_) async => 'unexpected',
    );
    await expectLater(
      installer.status(),
      throwsA(
        isA<UpdateIssue>().having(
          (e) => e.problem,
          'problem',
          UpdateProblem.installation,
        ),
      ),
    );
  });
}
