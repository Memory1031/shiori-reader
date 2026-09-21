import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/local/files/app_paths.dart';
import '../data/updates/github_update_repository.dart';
import '../data/updates/update_http.dart';
import '../data/updates/update_manifest.dart';
import '../data/updates/update_storage.dart';
import '../data/updates/update_installer.dart';
import '../domain/contracts/app_updates.dart';
import '../features/updates/update_controller.dart';

const _channel = MethodChannel('dev.shiori.reader/app');

Future<UpdateController> createUpdateController(
  AppPaths paths, {
  Future<void> Function()? beforeInstall,
}) async {
  var version = '—';
  var build = 0;
  BundledRelease? bundled;
  var availability = UpdateAvailability.invalidIdentity;
  try {
    final info = await _channel.invokeMapMethod<String, dynamic>('info');
    version = info!['version'] as String;
    build = info['build'] as int;
    if (Platform.isAndroid || Platform.isWindows) {
      bundled = BundledRelease.fromJson(
        jsonDecode(
              await rootBundle.loadString('assets/release/build-info.json'),
            )
            as Map<String, dynamic>,
      );
      if (bundled == null ||
          !kReleaseMode ||
          paths.environment == StorageEnvironment.development) {
        availability = UpdateAvailability.development;
      } else {
        bundled.verifyInstalledVersion(version, build);
        availability = UpdateAvailability.enabled;
      }
    } else {
      availability = UpdateAvailability.unsupported;
    }
  } catch (_) {
    /* Update initialization must not block the library. */
  }
  return UpdateController(
    GithubUpdateRepository(
      installed: InstalledUpdateApp(
        version: version,
        build: build,
        availability: availability,
        release: bundled?.identity,
      ),
      platform: Platform.isWindows ? 'windows-x64' : 'android',
      installer: Platform.isAndroid ? const AndroidUpdateInstaller() : null,
      key: bundled?.publicKey,
      http: DioUpdateHttp(),
      storage: UpdateStorage(
        directory: Directory('${paths.disposable.path}/updates'),
        preferencesFile: File('${paths.users.path}/update-preferences.json'),
      ),
    ),
    beforeInstall: beforeInstall,
  );
}

Future<bool> openUpdatePage(Uri page) async {
  if (page.scheme != 'https' ||
      page.host != 'github.com' ||
      page.userInfo.isNotEmpty ||
      !page.path.startsWith('/$updateRepositoryPath/releases/') ||
      page.hasQuery ||
      page.hasFragment) {
    return false;
  }
  try {
    return await _channel.invokeMethod<bool>('openRelease', page.toString()) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
