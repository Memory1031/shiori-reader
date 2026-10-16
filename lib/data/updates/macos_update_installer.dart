import 'dart:io';
import 'package:flutter/services.dart';

import '../../domain/contracts/app_updates.dart';
import '../../domain/models/release_identity.dart';
import 'update_installer.dart';
import 'update_manifest.dart';

/// The installed native helper owns verification, replacement and recovery.
final class MacOSUpdateInstaller implements UpdateInstaller {
  MacOSUpdateInstaller({
    required this.prepareExit,
    this.channel = const MethodChannel('dev.shiori.reader/update'),
  });
  final Future<void> Function() prepareExit;
  final MethodChannel channel;

  Future<UpdateInstallState> _state(String method, [Object? arguments]) async {
    try {
      final value = await channel.invokeMethod<String>(method, arguments);
      return UpdateInstallState.values.byName(value ?? '');
    } on PlatformException catch (error) {
      throw UpdateIssue(switch (error.code) {
        'verification' => UpdateProblem.packageInvalid,
        'location' => UpdateProblem.location,
        'busy' => UpdateProblem.busy,
        'instances' => UpdateProblem.instances,
        'storage' => UpdateProblem.storage,
        'workspaceConflict' => UpdateProblem.workspaceConflict,
        _ => UpdateProblem.installation,
      });
    } on MissingPluginException {
      throw const UpdateIssue(UpdateProblem.installation);
    } on ArgumentError {
      throw const UpdateIssue(UpdateProblem.installation);
    }
  }

  @override
  Future<UpdateInstallState> status() => _state('status');
  @override
  Future<void> openSettings() async {}
  @override
  Future<UpdateInstallState> install(
    File package,
    ReleaseIdentity release,
    UpdateAsset asset,
    Uint8List manifest,
    Uint8List signature,
  ) async {
    // Prepare can fail without closing any reading session or database.
    await _state('prepare', {
      'path': package.path,
      'manifest': manifest,
      'signature': signature,
    });
    // Native launch rechecks the staged archive and waits for this process.
    final state = await _state('start');
    if (state != UpdateInstallState.installing) {
      throw const UpdateIssue(UpdateProblem.installation);
    }
    await prepareExit();
    await channel.invokeMethod<void>('exit');
    return state;
  }
}
