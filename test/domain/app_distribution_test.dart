import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/app_updates.dart';
import 'package:shiori/domain/models/release_identity.dart';

void main() {
  test(
    'installation forms describe the application and its update package',
    () {
      const expected = {
        AppInstallationKind.androidApk: (
          AppPlatform.android,
          UpdatePackageFormat.apk,
        ),
        AppInstallationKind.windowsSetup: (
          AppPlatform.windows,
          UpdatePackageFormat.exe,
        ),
        AppInstallationKind.windowsPortable: (
          AppPlatform.windows,
          UpdatePackageFormat.zip,
        ),
        AppInstallationKind.macosApp: (
          AppPlatform.macos,
          UpdatePackageFormat.dmg,
        ),
        AppInstallationKind.iosApp: (AppPlatform.ios, UpdatePackageFormat.ipa),
        AppInstallationKind.unknown: (AppPlatform.unknown, null),
      };
      for (final entry in expected.entries) {
        final installation = AppInstallation(kind: entry.key);
        expect(installation.platform, entry.value.$1);
        expect(installation.updatePackageFormat, entry.value.$2);
      }
      expect(const AppInstallation().distribution, DistributionChannel.unknown);
    },
  );

  test('release track remains independent from installation distribution', () {
    final release = ReleaseIdentity(
      tag: 'v1.4.2',
      version: '1.4.2',
      build: 22,
      commit: 'a' * 40,
    );
    final app = InstalledUpdateApp(
      version: release.version,
      build: release.build,
      release: release,
      availability: UpdateAvailability.unsupported,
      installation: const AppInstallation(
        kind: AppInstallationKind.iosApp,
        distribution: DistributionChannel.testFlight,
      ),
    );
    expect(app.release!.channel, UpdateChannel.stable);
    expect(app.installation.distribution, DistributionChannel.testFlight);
    expect(app.availability, UpdateAvailability.unsupported);
  });

  test(
    'version checks can coexist with updating through the original source',
    () {
      const modes = [
        (
          UpdateCapabilities(method: UpdateMethod.inApp),
          true,
          true,
          true,
          false,
        ),
        (
          UpdateCapabilities(method: UpdateMethod.downloadOnly),
          true,
          true,
          false,
          false,
        ),
        (
          UpdateCapabilities(method: UpdateMethod.checkOnly),
          true,
          false,
          false,
          false,
        ),
        // iOS direct distribution: users update with their chosen signing tool.
        (
          UpdateCapabilities(
            method: UpdateMethod.checkOnly,
            externalTarget: ExternalUpdateTarget.originalSource,
          ),
          true,
          false,
          false,
          true,
        ),
        (
          UpdateCapabilities(
            method: UpdateMethod.external,
            externalTarget: ExternalUpdateTarget.testFlight,
          ),
          false,
          false,
          false,
          true,
        ),
        (
          UpdateCapabilities(
            method: UpdateMethod.external,
            externalTarget: ExternalUpdateTarget.appStore,
          ),
          false,
          false,
          false,
          true,
        ),
        (
          UpdateCapabilities(method: UpdateMethod.unavailable),
          false,
          false,
          false,
          false,
        ),
      ];
      for (final (capabilities, check, download, install, external) in modes) {
        expect(capabilities.canCheck, check);
        expect(capabilities.canDownload, download);
        expect(capabilities.canInstall, install);
        expect(capabilities.canOpenExternal, external);
      }
    },
  );
}
