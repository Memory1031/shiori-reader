import 'value_model.dart';

enum AppPlatform { android, windows, macos, ios, unknown }

/// Distribution information does not establish package authenticity.
enum DistributionChannel {
  /// Includes iOS IPA distribution using AltStore or other user-selected
  /// signing tools. The signing tool is not a separate distribution channel.
  direct,
  testFlight,
  appStore,
  unknown,
}

enum UpdatePackageFormat { apk, exe, zip, dmg, ipa }

/// The installed application form and its update package are separate facts.
enum AppInstallationKind {
  androidApk(AppPlatform.android, UpdatePackageFormat.apk),
  windowsSetup(AppPlatform.windows, UpdatePackageFormat.exe),
  windowsPortable(AppPlatform.windows, UpdatePackageFormat.zip),
  macosApp(AppPlatform.macos, UpdatePackageFormat.dmg),
  iosApp(AppPlatform.ios, UpdatePackageFormat.ipa),
  unknown(AppPlatform.unknown, null);

  const AppInstallationKind(this.platform, this.updatePackageFormat);
  final AppPlatform platform;
  final UpdatePackageFormat? updatePackageFormat;
}

final class AppInstallation extends ValueModel {
  const AppInstallation({
    this.kind = AppInstallationKind.unknown,
    this.distribution = DistributionChannel.unknown,
  });

  final AppInstallationKind kind;
  final DistributionChannel distribution;
  AppPlatform get platform => kind.platform;
  UpdatePackageFormat? get updatePackageFormat => kind.updatePackageFormat;

  @override
  List<Object?> get values => [kind, distribution];
}
