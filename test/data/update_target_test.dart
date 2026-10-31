import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/updates/update_target.dart';
import 'package:shiori/domain/contracts/app_updates.dart';

import '../support/update_fixtures.dart';

void main() {
  test('only direct iOS release builds can check GitHub updates', () {
    for (final source in ['direct', 'testFlight', 'appStore', '', 'other']) {
      for (final availability in UpdateAvailability.values) {
        final app = InstalledUpdateApp(
          version: '1.4.2',
          build: 22,
          availability: availability,
          installation: AppInstallation(
            kind: AppInstallationKind.iosApp,
            distribution: distributionFromBuild(source),
          ),
        );
        final capabilities = app.capabilitiesFor(supportsInstallation: true);
        expect(
          capabilities.canCheck,
          source == 'direct' && availability == UpdateAvailability.enabled,
        );
        expect(capabilities.canDownload, isFalse);
        expect(capabilities.canInstall, isFalse);
      }
    }
  });

  test(
    'supported installation forms select existing signed-manifest targets',
    () {
      final fixture = UpdateFixtures();
      final targets = {
        AppInstallationKind.androidApk: 'android',
        windowsInstallationKind('setup'): 'windows-x64-setup',
        windowsInstallationKind('portable'): 'windows-x64-portable',
        AppInstallationKind.macosApp: 'macos-universal',
      };
      final published = (fixture.manifest['assets'] as List)
          .map((asset) => asset['platform'])
          .toSet();
      for (final entry in targets.entries) {
        expect(updateAssetPlatform(entry.key), entry.value);
        expect(published, contains(entry.value));
      }
      expect(updateAssetPlatform(AppInstallationKind.iosApp), isNull);
      expect(updateAssetPlatform(AppInstallationKind.unknown), isNull);
    },
  );

  test(
    'unrecognized Windows modes never fall back to a portable or Android asset',
    () {
      for (final mode in ['', 'SETUP', 'msix', 'unknown']) {
        expect(() => windowsInstallationKind(mode), throwsFormatException);
      }
    },
  );
}
