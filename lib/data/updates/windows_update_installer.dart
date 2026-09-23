import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';

import '../../domain/contracts/app_updates.dart';
import '../../domain/models/release_identity.dart';
import 'update_installer.dart';
import 'update_manifest.dart';

/// Exit codes of windows/update/updater_main.cpp.
abstract final class WindowsUpdaterCode {
  static const installed = 0;
  static const rolledBack = 1;
  static const recoveryRequired = 2;
  static const launchFailed = 3;
  static const error = 10;
  static const busy = 20;
  static const none = 21;
  static const failed = 22;
  static const timeout = 23;
  static const instances = 30;
  static const storage = 31;
  static const invalid = 32;
  static const unsupported = 33;
}

/// Stages the verified ZIP in `<install>.update` beside the installation and
/// hands off to the installed updater, which replaces the program files once
/// this process has exited. User data lives elsewhere and is never touched.
final class WindowsUpdateInstaller implements UpdateInstaller {
  WindowsUpdateInstaller({
    required this.installation,
    required this.processId,
    required this.runUpdater,
    required this.startUpdater,
    required this.prepareExit,
    required this.exit,
  }) : workspace = Directory('${installation.path}.update');

  factory WindowsUpdateInstaller.system({
    required Future<void> Function() prepareExit,
  }) {
    const channel = MethodChannel('dev.shiori.reader/app');
    return WindowsUpdateInstaller(
      installation: File(Platform.resolvedExecutable).parent,
      processId: pid,
      runUpdater: (executable, arguments) async =>
          (await Process.run(executable, arguments)).exitCode,
      startUpdater: () async =>
          await channel.invokeMethod<bool>('startUpdater') ?? false,
      prepareExit: prepareExit,
      exit: () => channel.invokeMethod<void>('exit'),
    );
  }

  final Directory installation;
  final Directory workspace;
  final int processId;
  final Future<int> Function(String executable, List<String> arguments)
  runUpdater;
  final Future<bool> Function() startUpdater;

  /// Flushes and closes app stores; the update controller stays alive.
  final Future<void> Function() prepareExit;
  final Future<void> Function() exit;
  bool _handedOff = false;

  File get _updater => File('${workspace.path}/shiori-updater.exe');

  Future<int> _run(String mode, [List<String> extra = const []]) async {
    try {
      return await runUpdater(_updater.path, [
        mode,
        workspace.path,
        installation.path,
        ...extra,
      ]);
    } on ProcessException {
      throw const UpdateIssue(UpdateProblem.installation);
    }
  }

  Future<void> _clear() async {
    try {
      if (await workspace.exists()) await workspace.delete(recursive: true);
    } on FileSystemException {
      // A just-exited updater may still hold its image; retried next status.
    }
  }

  static UpdateProblem _problem(int code) => switch (code) {
    WindowsUpdaterCode.busy => UpdateProblem.busy,
    WindowsUpdaterCode.instances => UpdateProblem.instances,
    WindowsUpdaterCode.storage => UpdateProblem.storage,
    WindowsUpdaterCode.invalid => UpdateProblem.packageInvalid,
    WindowsUpdaterCode.unsupported => UpdateProblem.location,
    _ => UpdateProblem.installation,
  };

  @override
  Future<void> openSettings() async {}

  @override
  Future<UpdateInstallState> status() async {
    if (_handedOff) return UpdateInstallState.installing;
    if (!await workspace.exists()) return UpdateInstallState.idle;
    // Only the updater copy starts transactions; without it nothing is pending.
    if (!await _updater.exists()) {
      await _clear();
      return UpdateInstallState.idle;
    }
    final code = await _run('recover');
    if (code == WindowsUpdaterCode.busy) return UpdateInstallState.installing;
    // An unfinished transaction is kept so the workspace updater copy can
    // still complete recovery; the updater has told the user what to do.
    if (code == WindowsUpdaterCode.recoveryRequired ||
        (code == WindowsUpdaterCode.error &&
            await File('${workspace.path}/plan.bin').exists())) {
      return UpdateInstallState.failed;
    }
    await _clear();
    return switch (code) {
      WindowsUpdaterCode.installed ||
      WindowsUpdaterCode.launchFailed => UpdateInstallState.installed,
      WindowsUpdaterCode.rolledBack => UpdateInstallState.failed,
      WindowsUpdaterCode.none => UpdateInstallState.idle,
      _ => throw UpdateIssue(_problem(code)),
    };
  }

  @override
  Future<UpdateInstallState> install(
    File package,
    ReleaseIdentity release,
    UpdateAsset asset,
    Uint8List manifest,
    Uint8List signature,
  ) async {
    if (_handedOff) throw const UpdateIssue(UpdateProblem.busy);
    final previous = await status();
    if (previous == UpdateInstallState.installing) {
      throw const UpdateIssue(UpdateProblem.busy);
    }
    if (await workspace.exists()) {
      throw const UpdateIssue(UpdateProblem.installation);
    }
    final installed = File('${installation.path}/shiori-updater.exe');
    if (!await installed.exists()) {
      throw const UpdateIssue(UpdateProblem.location);
    }
    try {
      final payload = Directory('${workspace.path}/payload');
      await payload.create(recursive: true);
      final files = {for (final file in asset.files) file.path: file.size};
      final packagePath = package.path;
      final payloadPath = payload.path;
      await Isolate.run(
        () => extractWindowsUpdate(packagePath, payloadPath, files),
      );
      await File(
        '${workspace.path}/update-manifest.json',
      ).writeAsBytes(manifest, flush: true);
      await File(
        '${workspace.path}/update-manifest.sig',
      ).writeAsBytes(signature, flush: true);
      // The installed updater, whose embedded key and build define trust.
      await installed.copy(_updater.path);
      final code = await _run('check', ['$processId']);
      if (code != WindowsUpdaterCode.installed) {
        throw UpdateIssue(_problem(code));
      }
      if (!await startUpdater()) {
        throw const UpdateIssue(UpdateProblem.installation);
      }
    } on FormatException {
      await _clear();
      throw const UpdateIssue(UpdateProblem.packageInvalid);
    } on FileSystemException {
      await _clear();
      throw const UpdateIssue(UpdateProblem.storage);
    } on UpdateIssue {
      await _clear();
      rethrow;
    } on PlatformException {
      await _clear();
      throw const UpdateIssue(UpdateProblem.installation);
    } on MissingPluginException {
      await _clear();
      throw const UpdateIssue(UpdateProblem.installation);
    }
    _handedOff = true;
    // The updater is already waiting; exit even if closing a store fails.
    try {
      await prepareExit();
    } catch (_) {}
    await exit();
    return UpdateInstallState.installing;
  }
}

/// Extracts exactly the signed files. Sizes are checked here; the updater
/// re-verifies every SHA-256 against the signed manifest before applying.
void extractWindowsUpdate(
  String package,
  String payload,
  Map<String, int> files,
) {
  final input = InputFileStream(package);
  try {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } catch (_) {
      throw const FormatException('Unreadable update archive');
    }
    final seen = <String>{};
    for (final entry in archive.files) {
      final size = files[entry.name];
      if (size == null ||
          !entry.isFile ||
          entry.isSymbolicLink ||
          !seen.add(entry.name) ||
          entry.size != size) {
        throw const FormatException('Unsigned or mismatched archive entry');
      }
      final target = File('$payload/${entry.name}');
      target.parent.createSync(recursive: true);
      final output = OutputFileStream(target.path);
      try {
        entry.writeContent(output);
      } on FileSystemException {
        rethrow;
      } catch (_) {
        throw const FormatException('Corrupt archive entry');
      } finally {
        output.closeSync();
      }
      if (target.lengthSync() != size) {
        throw const FormatException('Archive entry size mismatch');
      }
    }
    if (seen.length != files.length) {
      throw const FormatException('Archive is missing signed files');
    }
  } finally {
    input.closeSync();
  }
}
