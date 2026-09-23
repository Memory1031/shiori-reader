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

  void stageWorkspace({bool plan = false}) {
    workspace.createSync();
    File('${workspace.path}/shiori-updater.exe').writeAsStringSync('updater');
    if (plan) File('${workspace.path}/plan.bin').writeAsStringSync('plan');
  }

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
      workspace.createSync();
      expect(await installer().status(), UpdateInstallState.idle);
      expect(workspace.existsSync(), isFalse);
      expect(runs, isEmpty);
    });

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
