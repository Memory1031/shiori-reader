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
///
/// The workspace is created with an ownership marker written first. A folder
/// of that name without the marker is someone else's: it is never run, used
/// or deleted, and is reported as [UpdateProblem.workspaceConflict].
///
/// Once the updater reports a finished transaction, its result is recorded
/// before any file is deleted, so an interrupted cleanup is resumed instead
/// of being mistaken for a transaction that still needs recovery.
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

  static const _markerName = 'shiori-update-workspace';
  static const _ownership = 'ShioriUpdateWorkspace/1\n';
  static const _closedName = 'shiori-update-closed';
  static const _closedFormat = 'ShioriUpdateClosed/1\n';
  static final _closedRecord = RegExp(r'^ShioriUpdateClosed/1\n(\d{1,3})\n$');

  File get _updater => File('${workspace.path}/shiori-updater.exe');
  File get _marker => File('${workspace.path}/$_markerName');
  File get _closed => File('${workspace.path}/$_closedName');

  /// Listed children are joined with the platform separator.
  String _name(FileSystemEntity entry) =>
      entry.path.substring(workspace.path.length + 1);
  bool _isMarker(FileSystemEntity entry) => _name(entry) == _markerName;

  Future<bool> _owned() async {
    try {
      return await FileSystemEntity.type(workspace.path, followLinks: false) ==
              FileSystemEntityType.directory &&
          await FileSystemEntity.type(_marker.path, followLinks: false) ==
              FileSystemEntityType.file &&
          await _marker.length() == _ownership.length &&
          await _marker.readAsString() == _ownership;
    } on FileSystemException {
      return false;
    }
  }

  /// A transaction record means the updater may still need these files.
  Future<bool> _transaction() async =>
      await File('${workspace.path}/plan.bin').exists() ||
      await Directory('${workspace.path}/backup').exists();

  /// Records that the transaction is over, published atomically. Returns
  /// false when it cannot be written; the updater files are then kept so the
  /// next status asks the updater again.
  Future<bool> _close(int code) async {
    try {
      final temp = File('${_closed.path}.tmp');
      await temp.writeAsString('$_closedFormat$code\n', flush: true);
      await temp.rename(_closed.path);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// The recorded result of a finished transaction, or null when none is
  /// recorded. Unreadable records are ignored so the files stay protected.
  Future<int?> _closedCode() async {
    try {
      if (await FileSystemEntity.type(_closed.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final match = _closedRecord.firstMatch(await _closed.readAsString());
      final code = match == null ? null : int.parse(match[1]!);
      return code != null && (_ended.contains(code) || _refusals.contains(code))
          ? code
          : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Whether [code] from recover proves no transaction needs these files.
  /// Refusals only do when no transaction record exists: with one, they come
  /// from a recovery attempt that stopped. Anything else, including exit
  /// codes of a crashed updater, keeps the workspace.
  Future<bool> _finished(int code) async =>
      _ended.contains(code) ||
      (_refusals.contains(code) && !await _transaction());

  /// Removes a leftover folder only when it is empty, as an interrupted
  /// cleanup leaves it after the marker. The non-recursive delete fails,
  /// keeping everything, if anything is or has since been put inside.
  Future<bool> _removeEmpty() async {
    try {
      if (await FileSystemEntity.type(workspace.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          !await workspace.list(followLinks: false).isEmpty) {
        return false;
      }
      await workspace.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

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

  /// Deletes an owned workspace, removing the result record and then the
  /// marker last so an interrupted cleanup is still recognised and resumed.
  Future<void> _clear() async {
    try {
      if (!await _owned()) return;
      await for (final entry in workspace.list(followLinks: false)) {
        final name = _name(entry);
        if (name != _markerName && name != _closedName) {
          await entry.delete(recursive: true);
        }
      }
      if (await _closed.exists()) await _closed.delete();
      await _marker.delete();
      await workspace.delete();
    } on FileSystemException {
      // A just-exited updater may still hold its image; retried next status.
    }
  }

  /// Undoes a workspace creation that failed before ownership was recorded.
  /// Only an empty folder or one holding just a partial marker is removed.
  Future<void> _abandon() async {
    try {
      final entries = await workspace.list(followLinks: false).toList();
      if (entries.length == 1 &&
          _isMarker(entries.single) &&
          entries.single is File &&
          await _marker.length() <= _ownership.length) {
        await _marker.delete();
      }
      await workspace.delete();
    } on FileSystemException {
      // Left in place; status reports it rather than deleting unknown files.
    }
  }

  /// Results after which no transaction exists.
  static const _ended = {
    WindowsUpdaterCode.installed,
    WindowsUpdaterCode.launchFailed,
    WindowsUpdaterCode.rolledBack,
    WindowsUpdaterCode.none,
  };

  /// Refusals the updater records before starting a transaction.
  static const _refusals = {
    WindowsUpdaterCode.error,
    WindowsUpdaterCode.failed,
    WindowsUpdaterCode.timeout,
    WindowsUpdaterCode.instances,
    WindowsUpdaterCode.storage,
    WindowsUpdaterCode.invalid,
    WindowsUpdaterCode.unsupported,
  };

  static UpdateInstallState _result(int code) => switch (code) {
    WindowsUpdaterCode.installed ||
    WindowsUpdaterCode.launchFailed => UpdateInstallState.installed,
    WindowsUpdaterCode.rolledBack => UpdateInstallState.failed,
    WindowsUpdaterCode.none => UpdateInstallState.idle,
    _ => throw UpdateIssue(_problem(code)),
  };

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
    if (await FileSystemEntity.type(workspace.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return UpdateInstallState.idle;
    }
    if (!await _owned()) {
      if (await _removeEmpty()) return UpdateInstallState.idle;
      throw const UpdateIssue(UpdateProblem.workspaceConflict);
    }
    // A finished transaction whose cleanup was interrupted: whatever is left,
    // plan.bin and backup included, is no longer needed by the updater.
    final closed = await _closedCode();
    if (closed != null) {
      await _clear();
      return _result(closed);
    }
    // Only the updater copy starts transactions; without it nothing is
    // pending unless a transaction record was left for manual recovery.
    if (!await _updater.exists()) {
      if (await _transaction()) return UpdateInstallState.failed;
      await _clear();
      return UpdateInstallState.idle;
    }
    final code = await _run('recover');
    if (code == WindowsUpdaterCode.busy) return UpdateInstallState.installing;
    // An unfinished transaction is kept so the workspace updater copy can
    // still complete recovery; the updater has told the user what to do.
    if (!await _finished(code)) return UpdateInstallState.failed;
    if (await _close(code)) await _clear();
    return _result(code);
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
    if (await FileSystemEntity.type(workspace.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const UpdateIssue(UpdateProblem.installation);
    }
    final installed = File('${installation.path}/shiori-updater.exe');
    if (!await installed.exists()) {
      throw const UpdateIssue(UpdateProblem.location);
    }
    try {
      await workspace.create();
      await _marker.writeAsString(_ownership, flush: true);
    } on FileSystemException {
      await _abandon();
      throw const UpdateIssue(UpdateProblem.storage);
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
