import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/contracts/app_updates.dart';
import '../../domain/models/release_identity.dart';
import 'update_manifest.dart';

/// Native paths and APK metadata stay inside the data layer.
abstract interface class UpdateInstaller {
  Future<UpdateInstallState> status();
  Future<void> openSettings();
  Future<UpdateInstallState> install(
    File package,
    ReleaseIdentity release,
    UpdateAsset asset,
  );
}

final class AndroidUpdateInstaller implements UpdateInstaller {
  const AndroidUpdateInstaller();
  static const channel = MethodChannel('dev.shiori.reader/update');

  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (error) {
      throw UpdateIssue(switch (error.code) {
        'verification' => UpdateProblem.verification,
        'storage' => UpdateProblem.storage,
        'busy' => UpdateProblem.busy,
        _ => UpdateProblem.installation,
      });
    } on MissingPluginException {
      throw const UpdateIssue(UpdateProblem.installation);
    }
  }

  Future<UpdateInstallState> _state(
    String method, [
    Map<String, Object>? arguments,
  ]) => _call(() async {
    final value = await channel.invokeMethod<String>(method, arguments);
    return UpdateInstallState.values.firstWhere(
      (state) => state.name == value,
      orElse: () => throw const UpdateIssue(UpdateProblem.installation),
    );
  });

  @override
  Future<UpdateInstallState> status() => _state('status');
  @override
  Future<void> openSettings() =>
      _call(() => channel.invokeMethod<void>('settings'));
  @override
  Future<UpdateInstallState> install(
    File package,
    ReleaseIdentity release,
    UpdateAsset asset,
  ) => _state('install', {
    'path': package.path,
    'version': release.version,
    'build': release.build,
    'size': asset.size,
    'sha256': asset.sha256,
    'certificateSha256': asset.certificateSha256!,
  });
}
