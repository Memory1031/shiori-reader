import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/import_source.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/import/import_controller.dart';
import 'package:shiori/features/import/import_overlay.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

class MemorySource implements ImportSource {
  final events = StreamController<ImportSourceEvent>.broadcast();
  ImportCandidate? input;
  List<int> bytes = utf8.encode('This is an offline book.');
  int acks = 0;
  bool readFails = false;
  Completer<void>? picking;
  @override
  Stream<ImportSourceEvent> get changes => events.stream;
  @override
  Future<void> pick() async {
    await picking?.future;
  }

  @override
  Future<ImportCandidate?> pending() async => input;
  @override
  Stream<List<int>> read(ImportCandidate candidate) async* {
    if (readFails) throw const ImportSourceException(ImportProblem.unreadable);
    // Split magic bytes across chunks to exercise content validation.
    yield bytes.take(2).toList();
    yield bytes.skip(2).toList();
  }

  @override
  Future<void> acknowledge(String id) async {
    acks++;
    if (input?.id == id) input = null;
  }

  @override
  Future<void> cancelCopy() async {
    if (picking != null && !picking!.isCompleted) picking!.complete();
  }

  @override
  Future<void> close() async {
    await cancelCopy();
    await events.close();
  }

  void receive({String id = 'receipt-1', String name = 'Book.txt', int? size}) {
    input = ImportCandidate(id: id, name: name, size: size ?? bytes.length);
    events.add(const ImportSourceEvent());
  }
}

LocalBookContent fakeParser(LocalImportSession session) {
  final key = LocalBookIdentity.chapter(session.key, 'txt:0');
  return LocalBookContent(
    detail: NovelDetail(
      summary: NovelSummary(key: session.key, title: 'Fixture'),
    ),
    catalog: Catalog(
      novelKey: session.key,
      volumes: [
        Volume(
          groupId: 'v',
          chapters: [
            Chapter(key: key, title: 'Body', ordinal: 0, volumeGroupId: 'v'),
          ],
        ),
      ],
    ),
    chapters: [
      ChapterContent(
        key: key,
        title: 'Body',
        blocks: [ParagraphBlock(text: 'Offline fixture')],
      ),
    ],
  );
}

void main() {
  late Directory temp;
  late UserDatabase db;
  late ManagedLocalBooks store;
  late MemorySource source;
  late ImportController controller;
  var parses = 0;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local002-');
    final paths = AppPaths(
      support: Directory('${temp.path}/support'),
      temporary: temp,
      environment: StorageEnvironment.development,
    );
    await paths.prepare();
    db = UserDatabase(NativeDatabase(paths.userDatabase));
    store =
        (await ManagedLocalBooks.open(paths, db) as Success<ManagedLocalBooks>)
            .value;
    source = MemorySource();
    parses = 0;
    controller = ImportController(
      source: source,
      store: store,
      parsers: {
        LocalBookFormat.txt: (session) async {
          parses++;
          return fakeParser(session);
        },
        LocalBookFormat.epub: (session) async {
          parses++;
          return fakeParser(session);
        },
      },
    );
  });
  tearDown(() async {
    await controller.shutdown();
    controller.dispose();
    await store.close();
    await db.close();
    await temp.delete(recursive: true);
  });
  test(
    'cold receipt waits for confirmation and repeated delivery deduplicates commit',
    () async {
      source.receive();
      await controller.start();
      expect(controller.phase, ImportPhase.ready);
      expect(parses, 0);
      expect(controller.panelOpen, false);
      await controller.submit();
      final first = controller.result!;
      expect(source.acks, 1);
      await controller.finish();
      source.receive(id: 'receipt-2');
      await controller.refresh();
      await controller.submit();
      expect(
        controller.result!.content.detail.summary.key,
        first.content.detail.summary.key,
      );
      expect(parses, 1);
    },
  );
  test(
    'external copy waits for completion across resume and remains cancellable',
    () async {
      await controller.start();
      source.events.add(const ImportSourceEvent(copiedBytes: 65536));
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, ImportPhase.receiving);
      source.receive();
      await controller.refresh();
      expect(controller.candidate, isNull);
      source.events.add(const ImportSourceEvent(completed: true));
      await Future<void>.delayed(Duration.zero);
      expect(controller.candidate?.id, 'receipt-1');
      expect(controller.phase, ImportPhase.ready);
      await controller.cancel();
      expect(source.input, isNull);
      expect(controller.phase, ImportPhase.idle);
    },
  );

  test(
    'multiple-file rejection is visible and next receipt can recover',
    () async {
      await controller.start();
      source.events.add(
        const ImportSourceEvent(problem: ImportProblem.multiple),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.problem, ImportProblem.multiple);
      source.receive();
      await Future<void>.delayed(Duration.zero);
      expect(controller.problem, isNull);
      await controller.submit();
      expect(controller.phase, ImportPhase.succeeded);
    },
  );

  test('picker cancellation is silent and leaves no receipt', () async {
    await controller.start();
    await controller.pick();
    expect(controller.problem, null);
    expect(controller.candidate, null);
  });
  test('read failure can retry the staged copy without original URI', () async {
    source.receive();
    await controller.start();
    source.readFails = true;
    await controller.submit();
    expect(controller.phase, ImportPhase.failed);
    expect(source.acks, 0);
    source.readFails = false;
    await controller.submit();
    expect(controller.phase, ImportPhase.succeeded);
  });
  test(
    'reject spoofed format, empty files and metadata size overflow before parser',
    () async {
      source.bytes = [0x50, 0x4b, 3, 4, 0, 0];
      source.receive();
      await controller.start();
      await controller.submit();
      expect(controller.problem, ImportProblem.invalidContent);
      expect(parses, 0);
      await controller.cancel();
      source.receive(size: ImportController.maxBytes + 1);
      await controller.refresh();
      await controller.submit();
      expect(controller.problem, ImportProblem.tooLarge);
      await controller.cancel();
      source.receive(size: 0);
      await controller.refresh();
      await controller.submit();
      expect(controller.problem, ImportProblem.invalidContent);
    },
  );
  test(
    'epub magic is verified across stream chunks; arbitrary binary is rejected',
    () async {
      source.bytes = utf8.encode('not a zip');
      source.receive(name: 'a.epub');
      await controller.start();
      await controller.submit();
      expect(controller.problem, ImportProblem.invalidContent);
      expect(parses, 0);
      await controller.cancel();
      source.bytes = [0x50, 0x4b, 3, 4, 5];
      source.receive(name: 'a.epub');
      await controller.refresh();
      await controller.submit();
      expect(parses, 1);
    },
  );
  test(
    'parser not registered never writes fake content into production',
    () async {
      await controller.shutdown();
      controller.dispose();
      source = MemorySource();
      controller = ImportController(
        source: source,
        store: store,
        parsers: const {},
      );
      source.receive();
      await controller.start();
      await controller.submit();
      expect(controller.problem, ImportProblem.parserUnavailable);
      expect(source.acks, 0);
      expect(await db.customSelect('SELECT * FROM local_books').get(), isEmpty);
    },
  );
  test(
    'cancel while parser awaits rejects late success and removes only the receipt',
    () async {
      await controller.shutdown();
      controller.dispose();
      source = MemorySource();
      final entered = Completer<void>();
      final resume = Completer<void>();
      controller = ImportController(
        source: source,
        store: store,
        parsers: {
          LocalBookFormat.txt: (session) async {
            entered.complete();
            await resume.future;
            return fakeParser(session);
          },
        },
      );
      source.receive();
      await controller.start();
      final work = controller.submit();
      await entered.future;
      final cancel = controller.cancel();
      resume.complete();
      await work;
      await cancel;
      expect(controller.result, null);
      expect(controller.phase, ImportPhase.idle);
      expect(await db.customSelect('SELECT * FROM local_books').get(), isEmpty);
      expect(source.acks, 1);
    },
  );
  testWidgets(
    'incoming banner preserves route, later snoozes, retry/cancel fit large Chinese text',
    (tester) async {
      await controller.start();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: ImportOverlay(controller: controller, child: child!),
          ),
          home: const Scaffold(body: Text('Reader position unchanged')),
        ),
      );
      source.receive();
      await tester.pumpAndSettle();
      expect(find.text('Reader position unchanged'), findsOneWidget);
      expect(find.text('有文件等待导入'), findsOneWidget);
      await tester.tap(find.text('稍后处理'));
      await tester.pumpAndSettle();
      expect(find.text('有文件等待导入'), findsNothing);
      controller.open();
      await tester.pumpAndSettle();
      source.readFails = true;
      await tester.runAsync(() async {
        await tester.tap(find.text('导入'));
        while (controller.busy) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('取消'));
        while (controller.candidate != null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.candidate, null);
      expect(tester.takeException(), null);
    },
  );
}
