import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/updates/github_update_repository.dart';
import 'package:shiori/data/updates/update_installer.dart';
import 'package:shiori/data/updates/update_manifest.dart';
import 'package:shiori/data/updates/update_storage.dart';
import 'package:shiori/domain/contracts/app_updates.dart';
import 'package:shiori/domain/models/release_identity.dart';
import 'package:shiori/features/updates/update_controller.dart';
import 'package:shiori/features/updates/update_screen.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

import '../support/update_fixtures.dart';

class _Installer implements UpdateInstaller {
  int calls = 0;
  @override
  Future<void> openSettings() async {}
  @override
  Future<UpdateInstallState> status() async => UpdateInstallState.idle;
  @override
  Future<UpdateInstallState> install(
    File package,
    ReleaseIdentity release,
    UpdateAsset asset,
  ) async {
    calls++;
    return UpdateInstallState.cancelled;
  }
}

void main() {
  for (final damage in ['missing', 'truncated', 'digest']) {
    testWidgets(
      '$damage package can be downloaded and installed again without restarting',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = UpdateFixtures();
        final installer = _Installer();
        late Directory temp;
        late UpdateStorage storage;
        late UpdateController controller;
        await tester.runAsync(() async {
          temp = await Directory.systemTemp.createTemp(
            'shiori-update-recovery-',
          );
          storage = UpdateStorage(
            directory: Directory('${temp.path}/updates'),
            preferencesFile: File('${temp.path}/preferences.json'),
          );
          final repo = GithubUpdateRepository(
            installed: fixture.installed,
            platform: 'android',
            key: fixture.key,
            http: FixtureUpdateHttp(fixture),
            storage: storage,
            installer: installer,
          );
          controller = UpdateController(repo);
          await controller.initialize();
          await controller.setChannel(UpdateChannel.beta);
          await controller.check();
          await controller.download();
          expect(controller.phase, UpdatePhase.downloaded);
          final package = storage.file('package.bin');
          if (damage == 'missing') {
            await package.delete();
          } else {
            await package.writeAsBytes(
              List.filled(
                damage == 'digest' ? controller.candidate!.bytes : 1,
                0,
              ),
            );
          }
        });
        addTearDown(() async {
          await controller.shutdown();
          controller.dispose();
          await temp.delete(recursive: true);
        });
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: UpdateScreen(
              controller: controller,
              openPage: (_) async => true,
            ),
          ),
        );
        Future<void> press(String key) async {
          final button = find.byKey(ValueKey(key));
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await tester.tap(button);
            final deadline = DateTime.now().add(const Duration(seconds: 10));
            while (controller.busy && DateTime.now().isBefore(deadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            expect(controller.busy, isFalse);
          });
          await tester.pumpAndSettle();
        }

        await tester.pumpAndSettle();
        await press('update-install');
        expect(controller.issue?.problem, UpdateProblem.packageInvalid);
        expect(controller.phase, UpdatePhase.available);
        expect(installer.calls, 0);
        expect(find.byKey(const ValueKey('update-install')), findsNothing);
        await press('update-download');
        expect(controller.phase, UpdatePhase.downloaded);
        await press('update-install');
        expect(installer.calls, 1);
        expect(controller.issue, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
