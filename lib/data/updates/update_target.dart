import '../../domain/models/app_distribution.dart';

DistributionChannel distributionFromBuild(String value) => switch (value) {
  'direct' => DistributionChannel.direct,
  'testFlight' => DistributionChannel.testFlight,
  'appStore' => DistributionChannel.appStore,
  _ => DistributionChannel.unknown,
};

AppInstallationKind windowsInstallationKind(String mode) => switch (mode) {
  'setup' => AppInstallationKind.windowsSetup,
  'portable' => AppInstallationKind.windowsPortable,
  _ => throw const FormatException('Invalid Windows installation identity'),
};

/// Manifest wire identifiers stay in the data layer. iOS has no in-app asset.
String? updateAssetPlatform(AppInstallationKind kind) => switch (kind) {
  AppInstallationKind.androidApk => 'android',
  AppInstallationKind.windowsSetup => 'windows-x64-setup',
  AppInstallationKind.windowsPortable => 'windows-x64-portable',
  AppInstallationKind.macosApp => 'macos-universal',
  AppInstallationKind.iosApp || AppInstallationKind.unknown => null,
};
