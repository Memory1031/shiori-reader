import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/updates/update_manifest.dart';
import 'package:shiori/data/updates/windows_update_installer.dart';
import 'package:shiori/domain/contracts/app_updates.dart';

import '../support/update_fixtures.dart';

void main() {
  final fixtures = UpdateFixtures();
  final manifestBytes = fixtures.bytes('manifest');
  final signature = fixtures.bytes('signature');
  final manifest = UpdateManifest.verifyAndRead(
    manifestBytes,
    signature,
    fixtures.key,
    expectedTag: fixtures.manifest['tag'] as String,
  );
  final asset = manifest.assets.singleWhere((a) => a.platform == 'windows-x64');
  final signed = {for (final file in asset.files) file.path: file.size};
  late Directory root;
  late Directory installation;
  late Directory workspace;
  late File package;
  late List<List<String>> runs;
  late List<String> events;
  late int Function(String mode) code;
  late bool started;

  WindowsUpdateInstaller installer({Future<void> Function()? prepareExit}) =>
      WindowsUpdateInstaller(
        installation: installation,
        processId: 4242,
        runUpdater: (executable, arguments) async {
          expect(executable, '${workspace.path}/shiori-updater.exe');
          expect(File(executable).existsSync(), isTrue);
          runs.add(arguments);
          return code(arguments.first);
        },
        startUpdater: () async {
          events.add('start');
          return started;
        },
        prepareExit:
            prepareExit ??
            () async {
              events.add('prepare');
            },
        exit: () async {
          events.add('exit');
        },
      );

  const ownership = 'ShioriUpdateWorkspace/1\n';
  File marker() => File('${workspace.path}/shiori-update-workspace');

  void ownWorkspace() {
    workspace.createSync();
    marker().writeAsStringSync(ownership);
  }

  void stageWorkspace({bool plan = false}) {
    ownWorkspace();
    File('${workspace.path}/shiori-updater.exe').writeAsStringSync('updater');
    if (plan) File('${workspace.path}/plan.bin').writeAsStringSync('plan');
  }

  File closed() => File('${workspace.path}/shiori-update-closed');
  void closeWorkspace(int result) =>
      closed().writeAsStringSync('ShioriUpdateClosed/1\n$result\n');

  /// A committed transaction as the updater leaves it before cleanup.
  void stageFinished() {
    stageWorkspace(plan: true);
    File('${workspace.path}/state').writeAsStringSync('committed');
    File('${workspace.path}/backup/shiori.exe')
      ..createSync(recursive: true)
      ..writeAsStringSync('old');
    File('${workspace.path}/payload/shiori.exe')
      ..createSync(recursive: true)
      ..writeAsStringSync('new');
  }

  /// Every file below [directory] with its bytes, for exact comparison.
  Map<String, List<int>> contents(Directory directory) => {
    for (final file in directory.listSync(recursive: true).whereType<File>())
      file.path.substring(directory.path.length): file.readAsBytesSync(),
  };

  Uint8List zip(
    Map<String, List<int>> entries, {
    List<String> dirs = const [],
  }) {
    final archive = Archive();
    for (final dir in dirs) {
      archive.add(ArchiveFile.directory(dir));
    }
    for (final entry in entries.entries) {
      archive.add(ArchiveFile.bytes(entry.key, entry.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Matcher problem(UpdateProblem value) =>
      throwsA(isA<UpdateIssue>().having((e) => e.problem, 'problem', value));

  setUp(() {
    root = Directory.systemTemp.createTempSync('shiori-windows-update-');
    installation = Directory('${root.path}/Shiori')..createSync();
    workspace = Directory('${installation.path}.update');
    File(
      '${installation.path}/shiori-updater.exe',
    ).writeAsStringSync('installed updater');
    package = File('${root.path}/package.zip')
      ..writeAsBytesSync(fixtures.package('windows-x64'));
    runs = [];
    events = [];
    code = (_) => WindowsUpdaterCode.installed;
    started = true;
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('extraction', () {
    test('writes exactly the signed files', () {
      final payload = '${root.path}/payload';
      extractWindowsUpdate(package.path, payload, signed);
      final source = ZipDecoder().decodeBytes(package.readAsBytesSync());
      for (final entry in source.files) {
        expect(
          File('$payload/${entry.name}').readAsBytesSync(),
          entry.content,
          reason: entry.name,
        );
      }
      final written = Directory(payload)
          .listSync(recursive: true)
          .whereType<File>()
          .map(
            (f) => f.path.substring(payload.length + 1).replaceAll('\\', '/'),
          )
          .toSet();
      expect(written, signed.keys.toSet());
    });

    for (final (name, bytes, files) in [
      (
        'unsigned entry',
        zip({
          'shiori.exe': List.filled(13, 1),
          'extra.dll': [1],
        }),
        {'shiori.exe': 13},
      ),
      (
        'wrong size',
        zip({'shiori.exe': List.filled(12, 1)}),
        {'shiori.exe': 13},
      ),
      (
        'missing signed file',
        zip({'shiori.exe': List.filled(13, 1)}),
        {'shiori.exe': 13, 'data/app.so': 13},
      ),
      (
        'directory entry',
        zip({'data/app.so': List.filled(13, 1)}, dirs: ['data/']),
        {'data/app.so': 13},
      ),
      (
        'case-changed name',
        zip({'Shiori.exe': List.filled(13, 1)}),
        {'shiori.exe': 13},
      ),
      ('not a zip', Uint8List.fromList(List.filled(64, 7)), {'shiori.exe': 13}),
    ]) {
      test('rejects $name', () {
        final source = File('${root.path}/bad.zip')..writeAsBytesSync(bytes);
        expect(
          () => extractWindowsUpdate(source.path, '${root.path}/out', files),
          throwsFormatException,
        );
      });
    }
  });

  group('status', () {
    test('nothing staged is idle without running the updater', () async {
      expect(await installer().status(), UpdateInstallState.idle);
      ownWorkspace();
      File('${workspace.path}/payload/shiori.exe')
        ..createSync(recursive: true)
        ..writeAsStringSync('partial');
      expect(await installer().status(), UpdateInstallState.idle);
      expect(workspace.existsSync(), isFalse);
      expect(runs, isEmpty);
    });

    for (final (name, prepare) in <(String, void Function())>[
      ('an unmarked folder', () {}),
      (
        'a folder with a foreign marker',
        () {
          marker().writeAsStringSync('mine');
        },
      ),
      (
        'an unmarked folder holding an updater',
        () {
          File('${workspace.path}/shiori-updater.exe').writeAsStringSync('x');
          File('${workspace.path}/plan.bin').writeAsStringSync('not ours');
        },
      ),
      (
        'an unmarked folder with a finished record',
        () {
          closeWorkspace(WindowsUpdaterCode.installed);
        },
      ),
    ]) {
      test('$name is a conflict and stays untouched', () async {
        File('${workspace.path}/notes/draft.txt')
          ..createSync(recursive: true)
          ..writeAsBytesSync([0, 1, 2, 255]);
        prepare();
        final before = contents(workspace);
        await expectLater(
          installer().status(),
          problem(UpdateProblem.workspaceConflict),
        );
        await expectLater(
          installer().install(
            package,
            manifest.identity,
            asset,
            manifestBytes,
            signature,
          ),
          problem(UpdateProblem.workspaceConflict),
        );
        expect(contents(workspace), before);
        expect(runs, isEmpty);
      });
    }

    test('a file with the workspace name is a conflict', () async {
      File(workspace.path).writeAsStringSync('user file');
      await expectLater(
        installer().status(),
        problem(UpdateProblem.workspaceConflict),
      );
      expect(File(workspace.path).readAsStringSync(), 'user file');
    });

    for (final record in ['plan.bin', 'backup/shiori.exe']) {
      test('a transaction record without the updater is kept', () async {
        ownWorkspace();
        File('${workspace.path}/$record')
          ..createSync(recursive: true)
          ..writeAsStringSync('record');
        final before = contents(workspace);
        expect(await installer().status(), UpdateInstallState.failed);
        expect(contents(workspace), before);
        expect(runs, isEmpty);
      });
    }

    for (final (result, state, kept) in [
      (WindowsUpdaterCode.installed, UpdateInstallState.installed, false),
      (WindowsUpdaterCode.launchFailed, UpdateInstallState.installed, false),
      (WindowsUpdaterCode.rolledBack, UpdateInstallState.failed, false),
      (WindowsUpdaterCode.none, UpdateInstallState.idle, false),
      (WindowsUpdaterCode.busy, UpdateInstallState.installing, true),
      (WindowsUpdaterCode.recoveryRequired, UpdateInstallState.failed, true),
    ]) {
      test('recover code $result is ${state.name}', () async {
        stageWorkspace();
        code = (_) => result;
        expect(await installer().status(), state);
        expect(runs.single, ['recover', workspace.path, installation.path]);
        expect(workspace.existsSync(), kept);
      });
    }

    for (final (name, interrupt) in <(String, void Function())>[
      (
        'the updater deleted but plan and backup left',
        () {
          File('${workspace.path}/shiori-updater.exe').deleteSync();
        },
      ),
      (
        'the state deleted but plan left',
        () {
          File('${workspace.path}/state').deleteSync();
          Directory('${workspace.path}/payload').deleteSync(recursive: true);
        },
      ),
      (
        'only the record left',
        () {
          for (final entry in workspace.listSync()) {
            final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
            if (name != 'shiori-update-closed' &&
                name != 'shiori-update-workspace') {
              entry.deleteSync(recursive: true);
            }
          }
        },
      ),
    ]) {
      test('cleanup interrupted with $name resumes', () async {
        stageFinished();
        closeWorkspace(WindowsUpdaterCode.installed);
        interrupt();
        expect(await installer().status(), UpdateInstallState.installed);
        expect(workspace.existsSync(), isFalse);
        expect(runs, isEmpty);
        expect(
          await installer().install(
            package,
            manifest.identity,
            asset,
            manifestBytes,
            signature,
          ),
          UpdateInstallState.installing,
        );
        expect(runs.map((r) => r.first), ['check']);
      });
    }

    test('a finished record keeps reporting its own result', () async {
      stageFinished();
      closeWorkspace(WindowsUpdaterCode.rolledBack);
      expect(await installer().status(), UpdateInstallState.failed);
      expect(workspace.existsSync(), isFalse);
      stageFinished();
      closeWorkspace(WindowsUpdaterCode.storage);
      await expectLater(installer().status(), problem(UpdateProblem.storage));
      expect(workspace.existsSync(), isFalse);
      expect(await installer().status(), UpdateInstallState.idle);
      expect(runs, isEmpty);
    });

    for (final (name, record) in [
      ('an unfinished code', 'ShioriUpdateClosed/1\n2\n'),
      ('a malformed record', 'ShioriUpdateClosed/1\ninstalled\n'),
      ('a foreign record', 'done'),
    ]) {
      test('$name does not end the transaction', () async {
        stageFinished();
        File('${workspace.path}/shiori-updater.exe').deleteSync();
        closed().writeAsStringSync(record);
        final before = contents(workspace);
        expect(await installer().status(), UpdateInstallState.failed);
        expect(contents(workspace), before);
      });
    }

    test('an unpublished record leaves recovery to the updater', () async {
      stageFinished();
      File('${closed().path}.tmp').writeAsStringSync('ShioriUpd');
      expect(await installer().status(), UpdateInstallState.installed);
      expect(runs.single.first, 'recover');
      expect(workspace.existsSync(), isFalse);
    });

    test('a record that cannot be written keeps the transaction', () async {
      stageFinished();
      Directory('${closed().path}.tmp').createSync();
      final before = contents(workspace);
      expect(await installer().status(), UpdateInstallState.installed);
      expect(contents(workspace), before);
      Directory('${closed().path}.tmp').deleteSync();
      expect(await installer().status(), UpdateInstallState.installed);
      expect(runs.map((r) => r.first), ['recover', 'recover']);
      expect(workspace.existsSync(), isFalse);
    });

    test(
      'cleanup stopped by a locked file resumes without the updater',
      () async {
        stageFinished();
        final held = File(
          '${workspace.path}/backup/shiori.exe',
        ).openSync(mode: FileMode.append);
        try {
          expect(await installer().status(), UpdateInstallState.installed);
          expect(closed().existsSync(), isTrue);
        } finally {
          held.closeSync();
        }
        expect(await installer().status(), UpdateInstallState.installed);
        expect(workspace.existsSync(), isFalse);
        expect(runs, hasLength(1));
      },
      skip: Platform.isWindows ? false : 'Needs Windows file locking',
    );

    test('an error keeps an unfinished transaction for recovery', () async {
      stageWorkspace(plan: true);
      code = (_) => WindowsUpdaterCode.error;
      expect(await installer().status(), UpdateInstallState.failed);
      expect(workspace.existsSync(), isTrue);
    });

    for (final (result, expected) in [
      (WindowsUpdaterCode.error, UpdateProblem.installation),
      (WindowsUpdaterCode.timeout, UpdateProblem.installation),
      (WindowsUpdaterCode.instances, UpdateProblem.instances),
      (WindowsUpdaterCode.storage, UpdateProblem.storage),
      (WindowsUpdaterCode.invalid, UpdateProblem.packageInvalid),
      (WindowsUpdaterCode.unsupported, UpdateProblem.location),
    ]) {
      test('recorded code $result reports ${expected.name} once', () async {
        stageWorkspace();
        code = (_) => result;
        await expectLater(installer().status(), problem(expected));
        expect(workspace.existsSync(), isFalse);
        expect(await installer().status(), UpdateInstallState.idle);
      });
    }
  });

  group('install', () {
    Future<UpdateInstallState> run(WindowsUpdateInstaller target) => target
        .install(package, manifest.identity, asset, manifestBytes, signature);

    test('stages, checks and hands off before exiting', () async {
      final target = installer();
      expect(await run(target), UpdateInstallState.installing);
      expect(runs, [
        ['check', workspace.path, installation.path, '4242'],
      ]);
      expect(events, ['start', 'prepare', 'exit']);
      expect(
        File('${workspace.path}/update-manifest.json').readAsBytesSync(),
        manifestBytes,
      );
      expect(
        File('${workspace.path}/update-manifest.sig').readAsBytesSync(),
        signature,
      );
      expect(
        File('${workspace.path}/shiori-updater.exe').readAsStringSync(),
        'installed updater',
      );
      expect(marker().readAsStringSync(), ownership);
      for (final file in asset.files) {
        expect(
          File('${workspace.path}/payload/${file.path}').lengthSync(),
          file.size,
        );
      }
      expect(await target.status(), UpdateInstallState.installing);
      await expectLater(run(target), problem(UpdateProblem.busy));
      expect(runs, hasLength(1));
    });

    test('exits even when closing stores fails', () async {
      final target = installer(prepareExit: () async => throw StateError('x'));
      expect(await run(target), UpdateInstallState.installing);
      expect(events, ['start', 'exit']);
    });

    for (final (result, expected) in [
      (WindowsUpdaterCode.instances, UpdateProblem.instances),
      (WindowsUpdaterCode.storage, UpdateProblem.storage),
      (WindowsUpdaterCode.invalid, UpdateProblem.packageInvalid),
      (WindowsUpdaterCode.unsupported, UpdateProblem.location),
      (WindowsUpdaterCode.busy, UpdateProblem.busy),
      (WindowsUpdaterCode.error, UpdateProblem.installation),
    ]) {
      test('check code $result stops as ${expected.name}', () async {
        code = (_) => result;
        await expectLater(run(installer()), problem(expected));
        expect(workspace.existsSync(), isFalse);
        expect(events, isEmpty);
      });
    }

    test('an updater that cannot start leaves nothing staged', () async {
      started = false;
      await expectLater(run(installer()), problem(UpdateProblem.installation));
      expect(workspace.existsSync(), isFalse);
      expect(events, ['start']);
    });

    test('a package that does not match the manifest is invalid', () async {
      package.writeAsBytesSync(zip({'shiori.exe': List.filled(13, 1)}));
      await expectLater(
        run(installer()),
        problem(UpdateProblem.packageInvalid),
      );
      expect(workspace.existsSync(), isFalse);
      expect(runs, isEmpty);
    });

    test('an installation without the updater cannot update itself', () async {
      File('${installation.path}/shiori-updater.exe').deleteSync();
      await expectLater(run(installer()), problem(UpdateProblem.location));
      expect(workspace.existsSync(), isFalse);
    });

    test('an unfinished transaction blocks a new one', () async {
      stageWorkspace(plan: true);
      code = (_) => WindowsUpdaterCode.recoveryRequired;
      await expectLater(run(installer()), problem(UpdateProblem.installation));
      expect(workspace.existsSync(), isTrue);
      expect(runs.map((r) => r.first), ['recover']);
    });
  });
}
