import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shiori/app/import_source.dart';
import 'package:shiori/data/import/desktop_import_source.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/import/import_controller.dart';

// Restoring pending receipts must not import or modify the book store.
class _UnusedStore implements LocalBookStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('dev.shiori.reader/import');
  const events = MethodChannel('dev.shiori.reader/import_events');
  const drops = MethodChannel('dev.shiori.reader/file_drop');
  late Directory temp;
  late AppPaths paths;
  late List<String> nativeCalls;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shiori-import-composition-');
    paths = AppPaths(
      support: temp,
      temporary: temp,
      environment: StorageEnvironment.production,
    );
    nativeCalls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add('import:${call.method}');
      return call.method == 'pending' ? [] : null;
    });
    messenger.setMockMethodCallHandler(events, (call) async {
      nativeCalls.add('events:${call.method}');
      return null;
    });
    messenger.setMockMethodCallHandler(drops, (_) async => null);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(drops, null);
    expect(p.equals(temp.parent.path, Directory.systemTemp.path), isTrue);
    await temp.delete(recursive: true);
  });

  for (final platform in ['android', 'ios']) {
    test(
      '$platform retains native pending, picker and shutdown bridge',
      () async {
        final source = createImportSource(paths, operatingSystem: platform);
        final controller = ImportController(
          source: source,
          store: _UnusedStore(),
        );
        try {
          await controller.start();
          await source.pick();
          expect(controller.problem, isNull);
        } finally {
          await controller.shutdown();
          controller.dispose();
        }
        expect(
          nativeCalls,
          containsAll([
            'events:listen',
            'import:pending',
            'import:pick',
            'events:cancel',
            'import:cancel',
          ]),
        );
        expect(await paths.importInbox.exists(), isFalse);
      },
    );
  }

  for (final platform in ['windows', 'macos']) {
    test(
      '$platform restores isolated desktop receipts and closes its source',
      () async {
        final original = await File(
          p.join(temp.path, 'book.txt'),
        ).writeAsString('Desktop book');
        final seed = DesktopImportSource(
          inbox: paths.importInbox,
          selectFiles: () async => [XFile(original.path)],
        );
        try {
          await seed.pick();
        } finally {
          await seed.close();
        }
        final source = createImportSource(paths, operatingSystem: platform);
        final controller = ImportController(
          source: source,
          store: _UnusedStore(),
        );
        final streamClosed = source.changes.drain<void>();
        try {
          await controller.start();
          expect(controller.phase, ImportPhase.ready);
          expect(controller.items.single.candidate.name, 'book.txt');
          expect(controller.problem, isNull);
          final development = createImportSource(
            AppPaths(
              support: temp,
              temporary: temp,
              environment: StorageEnvironment.development,
            ),
            operatingSystem: platform,
          );
          try {
            expect(await development.pending(), isEmpty);
          } finally {
            await development.close();
          }
        } finally {
          await controller.shutdown();
          controller.dispose();
        }
        await streamClosed;
        final reopened = createImportSource(paths, operatingSystem: platform);
        try {
          final receipt = (await reopened.pending()).single;
          expect(
            await reopened.read(receipt).expand((bytes) => bytes).toList(),
            await original.readAsBytes(),
          );
        } finally {
          await reopened.close();
        }
        expect(nativeCalls, isEmpty);
      },
    );
  }

  test('unsupported hosts never fall through to the mobile bridge', () {
    for (final platform in ['linux', 'fuchsia', 'unknown']) {
      expect(
        () => createImportSource(paths, operatingSystem: platform),
        throwsUnsupportedError,
      );
    }
    expect(nativeCalls, isEmpty);
  });
}
