import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shiori/data/import/desktop_import_source.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/import_source.dart';
import 'package:shiori/features/import/import_controller.dart';

import '../local/support/epub_fixtures.dart';

class Input extends XFile {
  Input(this.filename, this.declaredSize, this.chunks) : super('unused');
  final String filename;
  final int declaredSize;
  final Stream<Uint8List> Function() chunks;
  int opens = 0;
  @override
  String get name => filename;
  @override
  Future<int> length() async => declaredSize;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    opens++;
    return chunks();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp, inbox;
  late List<DesktopImportSource> sources;
  late List<XFile> selection;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shiori-desktop-import-');
    inbox = Directory(p.join(temp.path, 'inbox'));
    selection = [];
    sources = [];
  });

  tearDown(() async {
    for (final source in sources) {
      await source.close();
    }
    expect(p.equals(temp.parent.path, Directory.systemTemp.path), isTrue);
    await temp.delete(recursive: true);
  });

  DesktopImportSource source({
    Future<List<XFile>> Function()? select,
    int maxFiles = 64,
    int maxFileBytes = 128 * 1024 * 1024,
    int maxBatchBytes = 512 * 1024 * 1024,
  }) {
    final result = DesktopImportSource(
      inbox: inbox,
      selectFiles: select ?? () async => selection,
      maxFiles: maxFiles,
      maxFileBytes: maxFileBytes,
      maxBatchBytes: maxBatchBytes,
    );
    sources.add(result);
    return result;
  }

  Future<XFile> file(String name, List<int> bytes) async {
    final output = File(p.join(temp.path, name));
    await output.writeAsBytes(bytes);
    return XFile(output.path);
  }

  Input input(String name, List<int> bytes, {int? declaredSize}) => Input(
    name,
    declaredSize ?? bytes.length,
    () => Stream.value(Uint8List.fromList(bytes)),
  );
  Matcher problem(ImportProblem value) =>
      isA<ImportSourceException>().having((e) => e.problem, 'problem', value);
  Future<List<int>> read(
    DesktopImportSource source,
    ImportCandidate candidate,
  ) => source.read(candidate).fold(<int>[], (all, chunk) => all..addAll(chunk));

  test('picker dismissal and picker errors publish no receipts', () async {
    final adapter = source();
    final events = <ImportSourceEvent>[];
    final subscription = adapter.changes.listen(events.add);
    await adapter.pick();
    expect(await adapter.pending(), isEmpty);
    expect(events, isEmpty);
    await subscription.cancel();
    final failing = source(
      select: () async => throw StateError('picker failed'),
    );
    await expectLater(
      failing.pick(),
      throwsA(problem(ImportProblem.unreadable)),
    );
    expect(await failing.pending(), isEmpty);
  });

  test(
    'ordered copies survive original changes and reopen; ack is scoped and idempotent',
    () async {
      selection = [
        await file('中文 空格.TXT', [1, 2, 3]),
        await file('book.EPUB', [4, 5]),
      ];
      final adapter = source();
      await adapter.pick();
      final first = await adapter.pending();
      expect(first.map((r) => r.name), ['中文 空格.TXT', 'book.EPUB']);
      expect(first.map((r) => r.size), [3, 2]);
      expect(first.map((r) => r.id).toSet(), hasLength(2));
      await File(selection.first.path).writeAsString('changed');
      await File(selection.last.path).delete();
      await adapter.close();
      final reopened = source();
      final restored = await reopened.pending();
      expect(restored.map((r) => r.id), first.map((r) => r.id));
      expect(await read(reopened, restored.first), [1, 2, 3]);
      expect(await read(reopened, restored.last), [4, 5]);
      await reopened.acknowledge('../中文 空格.TXT');
      await reopened.acknowledge(first.first.id);
      await reopened.acknowledge(first.first.id);
      expect((await reopened.pending()).single.id, first.last.id);
      expect(await File(selection.first.path).readAsString(), 'changed');
      await expectLater(
        read(reopened, first.first),
        throwsA(problem(ImportProblem.unreadable)),
      );
      await reopened.acknowledge(first.last.id);
      expect(await reopened.pending(), isEmpty);
      selection = [
        await file('next.txt', [8]),
      ];
      await reopened.pick();
      expect((await reopened.pending()).single.name, 'next.txt');
    },
  );

  test(
    'pending batch blocks another picker without touching existing data',
    () async {
      var calls = 0;
      final adapter = source(
        select: () async {
          calls++;
          return [
            input('book.txt', [1]),
          ];
        },
      );
      await adapter.pick();
      final id = (await adapter.pending()).single.id;
      await expectLater(adapter.pick(), throwsA(problem(ImportProblem.busy)));
      expect(calls, 1);
      expect((await adapter.pending()).single.id, id);
    },
  );

  test('all metadata is checked before copying any file', () async {
    final first = input('good.txt', [1]);
    final adapter = source(maxFiles: 2, maxFileBytes: 4, maxBatchBytes: 8);
    for (final pair in <(XFile, ImportProblem)>[
      (input('bad.pdf', [2]), ImportProblem.unsupported),
      (input('../escape.txt', [2]), ImportProblem.unsupported),
      (input('large.epub', [2], declaredSize: 5), ImportProblem.tooLarge),
      (input('empty.txt', []), ImportProblem.unreadable),
      (XFile(p.join(temp.path, 'missing.txt')), ImportProblem.unreadable),
    ]) {
      selection = [first, pair.$1];
      await expectLater(adapter.pick(), throwsA(problem(pair.$2)));
      expect(first.opens, 0);
      expect(await adapter.pending(), isEmpty);
      expect(await Directory(p.join(inbox.path, 'working')).exists(), isFalse);
    }
    selection = [first, first, first];
    await expectLater(
      adapter.pick(),
      throwsA(problem(ImportProblem.batchLimit)),
    );
    expect(first.opens, 0);
  });

  test(
    'actual streamed lengths enforce file and batch limits and roll back the whole batch',
    () async {
      final adapter = source(maxFileBytes: 4, maxBatchBytes: 6);
      selection = [
        input('one.txt', [1, 2]),
        input('large.txt', [1, 2, 3, 4, 5], declaredSize: 1),
      ];
      await expectLater(
        adapter.pick(),
        throwsA(problem(ImportProblem.tooLarge)),
      );
      expect(await adapter.pending(), isEmpty);
      selection = [
        input('one.txt', [1, 2, 3]),
        input('two.txt', [1, 2, 3, 4], declaredSize: 1),
      ];
      await expectLater(
        adapter.pick(),
        throwsA(problem(ImportProblem.batchLimit)),
      );
      expect(await adapter.pending(), isEmpty);
      expect(await Directory(p.join(inbox.path, 'working')).exists(), isFalse);
    },
  );

  test(
    'late input failure and empty streams never publish a partial batch',
    () async {
      final adapter = source();
      for (final bad in [
        Input(
          'unreadable.txt',
          1,
          () => Stream.error(const FileSystemException('denied')),
        ),
        Input('empty.txt', 1, () => const Stream.empty()),
      ]) {
        selection = [
          input('first.txt', [1]),
          bad,
        ];
        await expectLater(
          adapter.pick(),
          throwsA(problem(ImportProblem.unreadable)),
        );
        expect(await adapter.pending(), isEmpty);
        expect(
          await Directory(p.join(inbox.path, 'working')).exists(),
          isFalse,
        );
      }
    },
  );

  test(
    'cancel waits for stream closure and staging cleanup even when input stalls',
    () async {
      final listening = Completer<void>(),
          cancelling = Completer<void>(),
          released = Completer<void>();
      final stream = StreamController<Uint8List>(
        onListen: listening.complete,
        onCancel: () {
          cancelling.complete();
          return released.future;
        },
      );
      selection = [Input('slow.txt', 1, () => stream.stream)];
      final adapter = source();
      final picked = expectLater(
        adapter.pick(),
        throwsA(problem(ImportProblem.cancelled)),
      );
      await listening.future;
      var finished = false;
      final stopped = adapter.cancelCopy().then((_) {
        finished = true;
      });
      await cancelling.future;
      expect(finished, isFalse);
      released.complete();
      await stopped;
      await picked;
      expect(await Directory(p.join(inbox.path, 'working')).exists(), isFalse);
      expect(await adapter.pending(), isEmpty);
      await stream.close();
    },
  );

  test(
    'close cancels an outstanding picker and ignores its late selection',
    () async {
      final opened = Completer<void>();
      final dialog = Completer<List<XFile>>();
      final adapter = source(
        select: () {
          opened.complete();
          return dialog.future;
        },
      );
      final picked = expectLater(
        adapter.pick(),
        throwsA(problem(ImportProblem.cancelled)),
      );
      await opened.future;
      await expectLater(adapter.pick(), throwsA(problem(ImportProblem.busy)));
      await adapter.close();
      await picked;
      final late = input('late.txt', [1]);
      dialog.complete([late]);
      expect(await source().pending(), isEmpty);
      expect(late.opens, 0);
      expect(adapter.pick, throwsStateError);
    },
  );

  test(
    'progress accumulates across files and completion follows durable publication',
    () async {
      final adapter = source();
      final events = <ImportSourceEvent>[];
      final subscription = adapter.changes.listen(events.add);
      selection = [
        input('one.txt', Uint8List(1024 * 1024)),
        input('two.txt', Uint8List(1024 * 1024)),
      ];
      await adapter.pick();
      expect(await adapter.pending(), hasLength(2));
      expect(
        events.where((e) => e.copiedBytes != null).map((e) => e.copiedBytes),
        [1024 * 1024, 2 * 1024 * 1024],
      );
      expect(events.last.completed, isTrue);
      await subscription.cancel();
    },
  );

  test(
    'recovery removes interrupted staging and ack tombstones, preserving unknown data',
    () async {
      await Directory(
        p.join(inbox.path, 'working', 'partial'),
      ).create(recursive: true);
      final trash = Directory(
        p.join(inbox.path, 'ack-trash-11111111-1111-4111-8111-111111111111'),
      );
      await trash.create();
      await File(p.join(trash.path, 'payload')).writeAsString('old');
      final unknown = File(p.join(inbox.path, 'keep-me'));
      await unknown.writeAsString('keep');
      await Directory(p.join(inbox.path, 'pending')).create();
      expect(await source().pending(), isEmpty);
      expect(await trash.exists(), isFalse);
      expect(await Directory(p.join(inbox.path, 'working')).exists(), isFalse);
      expect(await unknown.readAsString(), 'keep');
    },
  );

  test('corrupt published metadata is reported and preserved', () async {
    selection = [
      input('book.txt', [1, 2]),
    ];
    final adapter = source();
    await adapter.pick();
    final item = (await Directory(
      p.join(inbox.path, 'pending'),
    ).list().toList()).single;
    final receipt = File(p.join(item.path, 'receipt.json'));
    final original = await receipt.readAsString();
    await receipt.writeAsString('{broken');
    await expectLater(
      adapter.pending(),
      throwsA(problem(ImportProblem.storage)),
    );
    await expectLater(adapter.pick(), throwsA(problem(ImportProblem.storage)));
    expect(await receipt.readAsString(), '{broken');
    await receipt.writeAsString(original);
    final fields = jsonDecode(original) as Map<String, dynamic>;
    await receipt.writeAsString(jsonEncode({...fields, 'size': 100}));
    await expectLater(
      adapter.pending(),
      throwsA(problem(ImportProblem.storage)),
    );
    expect(await File(p.join(item.path, 'payload')).readAsBytes(), [1, 2]);
  });

  test(
    'published symlinks cannot redirect reads or acknowledgement outside the inbox',
    () async {
      selection = [
        input('book.txt', [1]),
      ];
      final adapter = source();
      await adapter.pick();
      final candidate = (await adapter.pending()).single;
      final item = (await Directory(
        p.join(inbox.path, 'pending'),
      ).list().toList()).single;
      final payload = File(p.join(item.path, 'payload'));
      await payload.delete();
      final external = await file('external.txt', [9]);
      await Link(payload.path).create(external.path);
      await expectLater(
        adapter.pending(),
        throwsA(problem(ImportProblem.storage)),
      );
      await expectLater(
        read(adapter, candidate),
        throwsA(problem(ImportProblem.storage)),
      );
      await expectLater(
        adapter.acknowledge(candidate.id),
        throwsA(problem(ImportProblem.storage)),
      );
      expect(await File(external.path).readAsBytes(), [9]);
    },
  );

  test(
    'another Windows adapter cannot recover or ack an active copy',
    () async {
      final listening = Completer<void>();
      final stream = StreamController<Uint8List>(onListen: listening.complete);
      selection = [Input('slow.txt', 1, () => stream.stream)];
      final copying = source(), competing = source();
      final result = expectLater(
        copying.pick(),
        throwsA(problem(ImportProblem.cancelled)),
      );
      await listening.future;
      try {
        await expectLater(
          competing.pending(),
          throwsA(problem(ImportProblem.busy)),
        );
        await expectLater(
          competing.acknowledge('unknown'),
          throwsA(problem(ImportProblem.busy)),
        );
        expect(await Directory(p.join(inbox.path, 'working')).exists(), isTrue);
      } finally {
        await copying.cancelCopy();
        await result;
        await stream.close();
      }
      expect(await competing.pending(), isEmpty);
    },
    skip: !Platform.isWindows,
  ); // POSIX file locks belong to the process.

  test(
    'duplicate receipt identities or orders preserve the published batch',
    () async {
      selection = [
        input('first.txt', [1]),
        input('second.txt', [2]),
      ];
      final adapter = source();
      await adapter.pick();
      final items = await Directory(
        p.join(inbox.path, 'pending'),
      ).list().toList();
      items.sort((a, b) => a.path.compareTo(b.path));
      final first =
          jsonDecode(
                await File(
                  p.join(items.first.path, 'receipt.json'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final secondFile = File(p.join(items.last.path, 'receipt.json'));
      final second =
          jsonDecode(await secondFile.readAsString()) as Map<String, dynamic>;
      for (final key in ['id', 'order']) {
        await secondFile.writeAsString(
          jsonEncode({...second, key: first[key]}),
        );
        await expectLater(
          adapter.pending(),
          throwsA(problem(ImportProblem.storage)),
        );
        await expectLater(
          adapter.acknowledge(first['id'] as String),
          throwsA(problem(ImportProblem.storage)),
        );
        expect(await File(p.join(items.first.path, 'payload')).readAsBytes(), [
          1,
        ]);
        expect(await File(p.join(items.last.path, 'payload')).readAsBytes(), [
          2,
        ]);
      }
    },
  );

  test(
    'selected TXT and EPUB pass through the real controller, parser and managed store',
    () async {
      selection = [
        await file('测试.TXT', utf8.encode('\ufeff第一章\n\n这是桌面导入的离线测试正文。')),
        await file('测试.EPUB', zipFiles(epubFiles())),
      ];
      final paths = AppPaths(
        support: temp,
        temporary: temp,
        environment: StorageEnvironment.development,
      );
      inbox = paths.importInbox;
      final databases =
          ((await LocalDatabases.open(paths)) as Success<LocalDatabases>).value;
      final adapter = source();
      final controller = ImportController(
        source: adapter,
        store: databases.localBooks,
        decoder: const BookDecoder(),
        addToShelf: true,
      );
      try {
        await controller.start();
        await controller.pick();
        expect(controller.items, hasLength(2));
        await controller.submit();
        expect(controller.succeededCount, 2);
        expect(controller.failedCount, 0);
        expect(await adapter.pending(), isEmpty);
        expect(
          await databases.users.customSelect('SELECT * FROM bookshelf').get(),
          hasLength(2),
        );
        expect(await File(selection.first.path).exists(), isTrue);
        expect(await File(selection.last.path).exists(), isTrue);
      } finally {
        await controller.shutdown();
        controller.dispose();
        await databases.close();
      }
    },
  );
}
