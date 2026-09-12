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
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/import/import_controller.dart';
import 'package:shiori/features/import/import_overlay.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

/// Fake durable inbox: receipts survive until acknowledged, order is stable.
class MemorySource implements ImportSource {
  final events = StreamController<ImportSourceEvent>.broadcast();
  final inbox = <ImportCandidate>[];
  final files = <String, List<int>>{};
  final acked = <String>[];

  /// Acknowledging these ids fails once, then succeeds on the next attempt.
  final failAckIds = <String>{};
  List<int> bytes = utf8.encode('This is an offline book.');
  bool readFails = false;
  int pickCalls = 0;
  Completer<void>? ackGate;
  Completer<List<ImportCandidate>>? pendingGate;
  Completer<void>? picking;
  @override
  Stream<ImportSourceEvent> get changes => events.stream;
  @override
  Future<void> pick() async {
    pickCalls++;
    await picking?.future;
  }

  @override
  Future<List<ImportCandidate>> pending() async => pendingGate == null
      ? List.unmodifiable(inbox)
      : await pendingGate!.future;
  @override
  Stream<List<int>> read(ImportCandidate candidate) async* {
    if (readFails) throw const ImportSourceException(ImportProblem.unreadable);
    final data = files[candidate.id] ?? bytes;
    // Split magic bytes across chunks to exercise content validation.
    yield data.take(2).toList();
    yield data.skip(2).toList();
  }

  @override
  Future<void> acknowledge(String id) async {
    await ackGate?.future;
    if (failAckIds.remove(id)) {
      throw const ImportSourceException(ImportProblem.storage);
    }
    if (!acked.contains(id)) acked.add(id);
    inbox.removeWhere((candidate) => candidate.id == id);
  }

  @override
  Future<void> cancelCopy() async {
    if (picking != null && !picking!.isCompleted) picking!.complete();
  }

  @override
  Future<void> close() async {
    // Mirrors PlatformImportSource: the broadcast stream stays reusable for a
    // later controller relaunching against the same durable inbox.
    await cancelCopy();
  }

  void receive({
    String id = 'receipt-1',
    String name = 'Book.txt',
    int? size,
    List<int>? content,
    ImportProblem? error,
  }) {
    final data = content ?? files[id] ?? bytes;
    files[id] = data;
    inbox.add(
      ImportCandidate(
        id: id,
        name: name,
        size: size ?? data.length,
        error: error,
      ),
    );
    events.add(const ImportSourceEvent());
  }
}

/// Decoder double that pauses on chosen filenames to exercise the encoding
/// confirmation callback in the middle of a batch.
class PreviewDecoder implements LocalBookDecoder {
  final names = <String>[];
  final encodings = <TxtEncoding?>[];
  final Set<String> pauseOn;
  PreviewDecoder([this.pauseOn = const {}]);
  @override
  Future<LocalBookContent> decode(
    LocalImportSession session, {
    required LocalBookFormat format,
    required String filename,
    required CancellationToken cancellation,
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
  }) async {
    names.add(filename);
    encodings.add(encoding);
    if (pauseOn.contains(filename)) {
      await chooseEncoding(
        TxtEncodingPreview(const {TxtEncoding.gb18030: '中文样本'}),
      );
    }
    return fakeParser(session);
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

Future<void> untilImport(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), true);
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
  Future<int> committed() async =>
      (await db.customSelect('SELECT * FROM local_books').get()).length;

  test('empty pending inbox leaves the controller idle', () async {
    await controller.start();
    expect(controller.phase, ImportPhase.idle);
    expect(controller.items, isEmpty);
    expect(controller.candidate, isNull);
    expect(controller.problem, isNull);
  });

  test(
    'discard releases a wrong selection and allows picking after restart',
    () async {
      source.receive();
      await controller.start();
      await controller.discard();
      expect(source.inbox, isEmpty);
      expect(controller.items, isEmpty);
      expect(parses, 0);
      await controller.pick();
      expect(source.pickCalls, 1);
      final reopened = ImportController(source: source, store: store);
      try {
        await reopened.start();
        expect(reopened.items, isEmpty);
        expect(reopened.phase, ImportPhase.idle);
      } finally {
        await reopened.shutdown();
        reopened.dispose();
      }
    },
  );

  test('discard keeps committed books and releases failed receipts', () async {
    source.receive(id: 'good', name: 'good.txt');
    source.receive(
      id: 'bad',
      name: 'bad.epub',
      content: utf8.encode('invalid'),
    );
    await controller.start();
    await controller.submit();
    expect(await committed(), 1);
    await controller.discard();
    expect(await committed(), 1);
    expect(source.inbox, isEmpty);
    expect(controller.items, isEmpty);
    expect(controller.phase, ImportPhase.idle);
  });

  test(
    'partial discard failure retains unconfirmed items and can retry',
    () async {
      for (final id in ['a', 'b', 'c']) {
        source.receive(id: id);
      }
      await controller.start();
      source.failAckIds.add('b');
      await controller.discard();
      expect(source.inbox.map((item) => item.id), ['b', 'c']);
      expect(controller.items.map((item) => item.candidate.id), ['b', 'c']);
      expect(controller.batchProblem, ImportProblem.storage);
      expect(controller.panelOpen, true);
      await controller.pick();
      expect(source.pickCalls, 0);
      await controller.discard();
      expect(source.inbox, isEmpty);
      expect(controller.batchProblem, isNull);
    },
  );

  test(
    'discard blocks duplicate actions and rejects stale pending refresh',
    () async {
      source.receive();
      await controller.start();
      final stale = List<ImportCandidate>.of(source.inbox);
      source.pendingGate = Completer<List<ImportCandidate>>();
      final refresh = controller.refresh();
      source.ackGate = Completer<void>();
      final discard = controller.discard();
      expect(controller.discarding, true);
      await controller.discard();
      await controller.pick();
      await controller.submit();
      expect(source.pickCalls, 0);
      expect(parses, 0);
      source.ackGate!.complete();
      await discard;
      final pendingGate = source.pendingGate!;
      source.pendingGate = null;
      pendingGate.complete(stale);
      await refresh;
      await controller.refresh();
      expect(controller.items, isEmpty);
      expect(source.acked, ['receipt-1']);
    },
  );

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
      expect(source.acked, ['receipt-1']);
      await controller.finish();
      source.receive(id: 'receipt-2');
      await controller.refresh();
      await controller.submit();
      expect(
        controller.result!.content.detail.summary.key,
        first.content.detail.summary.key,
      );
      expect(parses, 1);
      expect(source.acked, ['receipt-1', 'receipt-2']);
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
      // Cancellation keeps the durable receipt instead of deleting input.
      expect(source.inbox.map((c) => c.id), ['receipt-1']);
      expect(source.acked, isEmpty);
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
    expect(controller.items.single.phase, ImportItemPhase.failed);
    expect(source.acked, isEmpty);
    source.readFails = false;
    await controller.submit();
    expect(controller.phase, ImportPhase.succeeded);
    expect(source.acked, ['receipt-1']);
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
      source.inbox.clear();
      await controller.finish();
      source.receive(size: ImportController.maxBytes + 1);
      await controller.refresh();
      await controller.submit();
      expect(controller.problem, ImportProblem.tooLarge);
      expect(parses, 0);
      source.inbox.clear();
      await controller.finish();
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
      source.inbox.clear();
      await controller.finish();
      source.receive(name: 'a.epub', content: [0x50, 0x4b, 3, 4, 5]);
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
      expect(source.acked, isEmpty);
      expect(await db.customSelect('SELECT * FROM local_books').get(), isEmpty);
    },
  );
  test(
    'cancel while parser awaits rejects late success and keeps the receipt pending',
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
      final stop = controller.cancel();
      resume.complete();
      await work;
      await stop;
      expect(controller.result, null);
      expect(controller.phase, ImportPhase.idle);
      expect(await db.customSelect('SELECT * FROM local_books').get(), isEmpty);
      expect(source.acked, isEmpty);
      expect(source.inbox.map((c) => c.id), ['receipt-1']);
    },
  );

  group('batch', () {
    test(
      'three candidates all succeed serially and acknowledge in order',
      () async {
        for (var i = 1; i <= 3; i++) {
          source.receive(
            id: 'r$i',
            name: 'Book$i.txt',
            content: utf8.encode('Offline book number $i.'),
          );
        }
        await controller.start();
        expect(controller.items.map((i) => i.candidate.id), ['r1', 'r2', 'r3']);
        await controller.submit();
        expect(controller.items.map((i) => i.phase).toSet(), {
          ImportItemPhase.succeeded,
        });
        expect(source.acked, ['r1', 'r2', 'r3']);
        expect(source.inbox, isEmpty);
        expect(parses, 3);
        expect(await committed(), 3);
        expect(controller.phase, ImportPhase.succeeded);
      },
    );

    test(
      'success then failure then success still processes the last item',
      () async {
        source.receive(id: 'a', name: 'a.txt', content: utf8.encode('alpha'));
        source.receive(
          id: 'b',
          name: 'broken.epub',
          content: utf8.encode('not a zip'),
        );
        source.receive(id: 'c', name: 'c.txt', content: utf8.encode('gamma'));
        await controller.start();
        await controller.submit();
        expect(controller.items.map((i) => i.phase), [
          ImportItemPhase.succeeded,
          ImportItemPhase.failed,
          ImportItemPhase.succeeded,
        ]);
        expect(controller.items[1].problem, ImportProblem.invalidContent);
        expect(source.acked, ['a', 'c']);
        expect(parses, 2);
        expect(await committed(), 2);
        expect(controller.phase, ImportPhase.failed);
        // The failed receipt stays pending; repairing and retrying commits it.
        source.files['b'] = [0x50, 0x4b, 3, 4, 5];
        await controller.submit();
        expect(controller.items.map((i) => i.phase).toSet(), {
          ImportItemPhase.succeeded,
        });
        expect(source.acked, ['a', 'c', 'b']);
        expect(source.inbox, isEmpty);
        expect(await committed(), 3);
      },
    );

    test(
      'successful candidate is acknowledged independently of failures',
      () async {
        source.receive(id: 'a', name: 'a.txt', content: utf8.encode('alpha'));
        source.receive(
          id: 'bad',
          name: 'bad.epub',
          content: utf8.encode('not a zip'),
        );
        await controller.start();
        await controller.submit();
        expect(source.acked, ['a']);
        expect(source.inbox.map((c) => c.id), ['bad']);
        expect(controller.items.first.phase, ImportItemPhase.succeeded);
        expect(controller.items.last.phase, ImportItemPhase.failed);
      },
    );

    test(
      'duplicate content succeeds for both receipts via SHA-256 dedup',
      () async {
        final shared = utf8.encode('byte-identical offline book');
        source.receive(id: 'a', name: 'a.txt', content: shared);
        source.receive(id: 'b', name: 'copy.txt', content: shared);
        await controller.start();
        await controller.submit();
        expect(controller.items.map((i) => i.phase).toSet(), {
          ImportItemPhase.succeeded,
        });
        expect(parses, 1);
        expect(source.acked, ['a', 'b']);
        expect(await committed(), 1);
        expect(
          controller.items[0].result!.content.detail.summary.key,
          controller.items[1].result!.content.detail.summary.key,
        );
      },
    );

    test(
      'cancel on item two of five keeps the first commit and later receipts',
      () async {
        await controller.shutdown();
        controller.dispose();
        var entries = 0;
        final entered = Completer<void>();
        final resume = Completer<void>();
        controller = ImportController(
          source: source,
          store: store,
          parsers: {
            LocalBookFormat.txt: (session) async {
              if (++entries == 2) {
                entered.complete();
                await resume.future;
              }
              return fakeParser(session);
            },
            LocalBookFormat.epub: (session) async => fakeParser(session),
          },
        );
        for (var i = 1; i <= 5; i++) {
          source.receive(
            id: 'r$i',
            name: 'Book$i.txt',
            content: utf8.encode('Offline book number $i.'),
          );
        }
        await controller.start();
        final run = controller.submit();
        await entered.future;
        final stop = controller.cancel();
        resume.complete();
        await run;
        await stop;
        expect(source.acked, ['r1']);
        expect(source.inbox.map((c) => c.id), ['r2', 'r3', 'r4', 'r5']);
        expect(controller.items.map((i) => i.phase), [
          ImportItemPhase.succeeded,
          ImportItemPhase.ready,
          ImportItemPhase.ready,
          ImportItemPhase.ready,
          ImportItemPhase.ready,
        ]);
        expect(entries, 2); // r3..r5 never start.
        expect(await committed(), 1);
        expect(controller.phase, ImportPhase.idle);
        expect(controller.result, isNull);
      },
    );

    test(
      'ambiguous TXT mid-batch pauses per item and never leaks encoding choice',
      () async {
        await controller.shutdown();
        controller.dispose();
        final decoder = PreviewDecoder({'a.txt', 'b.txt'});
        controller = ImportController(
          source: source,
          store: store,
          decoder: decoder,
        );
        source.receive(id: 'a', name: 'a.txt', content: utf8.encode('alpha'));
        source.receive(id: 'b', name: 'b.txt', content: utf8.encode('beta'));
        source.receive(id: 'c', name: 'c.txt', content: utf8.encode('gamma'));
        await controller.start();
        controller.setEncoding(TxtEncoding.utf16le);
        final run = controller.submit();
        await untilImport(() => controller.choosingEncoding);
        expect(decoder.names, ['a.txt']); // Batch pauses on the current item.
        controller.confirmEncoding(TxtEncoding.gb18030);
        await untilImport(() => controller.choosingEncoding);
        expect(decoder.names, ['a.txt', 'b.txt']); // Remaining items wait.
        controller.confirmEncoding(TxtEncoding.gb18030);
        await run;
        expect(decoder.names, ['a.txt', 'b.txt', 'c.txt']);
        // Manual override applies only to its own item; confirmations and
        // overrides never carry into the next TXT.
        expect(decoder.encodings, [TxtEncoding.utf16le, null, null]);
        expect(controller.items.map((i) => i.phase).toSet(), {
          ImportItemPhase.succeeded,
        });
        expect(source.acked, ['a', 'b', 'c']);
      },
    );

    test('fatal storage failure stops remaining items', () async {
      source.receive(id: 'a', name: 'a.txt', content: utf8.encode('alpha'));
      source.receive(id: 'b', name: 'b.txt', content: utf8.encode('beta'));
      await controller.start();
      await store.close();
      await controller.submit();
      expect(controller.items[0].phase, ImportItemPhase.failed);
      expect(controller.items[0].problem, ImportProblem.storage);
      expect(controller.items[1].phase, ImportItemPhase.ready);
      expect(source.acked, isEmpty);
      expect(parses, 0);
      expect(controller.problem, ImportProblem.storage);
      expect(controller.phase, ImportPhase.failed);
    });

    test('parser unavailable stops remaining items', () async {
      await controller.shutdown();
      controller.dispose();
      source = MemorySource();
      controller = ImportController(source: source, store: store);
      source.receive(id: 'a', name: 'a.txt');
      source.receive(id: 'b', name: 'b.txt');
      await controller.start();
      await controller.submit();
      expect(controller.items[0].phase, ImportItemPhase.failed);
      expect(controller.items[0].problem, ImportProblem.parserUnavailable);
      expect(controller.items[1].phase, ImportItemPhase.ready);
      expect(source.acked, isEmpty);
      expect(parses, 0);
      expect(controller.problem, ImportProblem.parserUnavailable);
      expect(controller.phase, ImportPhase.failed);
    });

    test('candidate fatal error stops remaining items', () async {
      source.receive(id: 'a', name: 'a.txt', error: ImportProblem.storage);
      source.receive(id: 'b', name: 'b.txt', content: utf8.encode('beta'));
      await controller.start();
      await controller.submit();
      expect(controller.items[0].phase, ImportItemPhase.failed);
      expect(controller.items[0].problem, ImportProblem.storage);
      expect(controller.items[1].phase, ImportItemPhase.ready);
      expect(parses, 0); // B's parser never runs.
      expect(source.acked, isEmpty);
      expect(controller.problem, ImportProblem.storage);
      expect(controller.phase, ImportPhase.failed);
      expect(await committed(), 0);
    });

    test(
      'storage failure after a non-fatal failure still stops the batch',
      () async {
        await controller.shutdown();
        controller.dispose();
        var entries = 0;
        controller = ImportController(
          source: source,
          store: store,
          parsers: {
            // The txt parse fails with an unexpected storage-layer error.
            LocalBookFormat.txt: (session) async {
              if (++entries == 1) throw StateError('storage layer broke');
              return fakeParser(session);
            },
            LocalBookFormat.epub: (session) async => fakeParser(session),
          },
        );
        // A fails non-fatally first; focus stays on A while B fails fatally.
        source.receive(
          id: 'a',
          name: 'broken.epub',
          content: utf8.encode('not a zip'),
        );
        source.receive(id: 'b', name: 'b.txt', content: utf8.encode('beta'));
        source.receive(id: 'c', name: 'c.txt', content: utf8.encode('gamma'));
        await controller.start();
        await controller.submit();
        expect(controller.items.map((i) => i.phase), [
          ImportItemPhase.failed, // a: invalidContent, non-fatal → continue
          ImportItemPhase.failed, // b: storage, fatal → stop
          ImportItemPhase.ready, // c: never started
        ]);
        expect(controller.items[0].problem, ImportProblem.invalidContent);
        expect(controller.items[1].problem, ImportProblem.storage);
        expect(entries, 1); // C's parser never runs.
        expect(source.acked, isEmpty);
        expect(controller.problem, ImportProblem.storage);
        expect(controller.phase, ImportPhase.failed);
        expect(await committed(), 0);
      },
    );

    test(
      'failed ack keeps the receipt durable; relaunch deduplicates and acks',
      () async {
        source.receive(id: 'a', name: 'a.txt', content: utf8.encode('alpha'));
        source.failAckIds.add('a');
        await controller.start();
        await controller.submit();
        // The commit stays authoritative; only the inbox cleanup failed.
        expect(controller.items.single.phase, ImportItemPhase.succeeded);
        expect(await committed(), 1);
        expect(source.acked, isEmpty);
        expect(source.inbox.map((c) => c.id), ['a']);
        await controller.shutdown();
        controller.dispose();
        var secondParses = 0;
        controller = ImportController(
          source: source,
          store: store,
          parsers: {
            LocalBookFormat.txt: (session) async {
              secondParses++;
              return fakeParser(session);
            },
            LocalBookFormat.epub: (session) async {
              secondParses++;
              return fakeParser(session);
            },
          },
        );
        await controller.start();
        expect(controller.items.map((i) => i.candidate.id), ['a']);
        await controller.submit();
        // SHA-256 dedup short-circuits before the parser: the relaunch never
        // parses and only retries the inbox cleanup.
        expect(secondParses, 0);
        expect(await committed(), 1);
        expect(source.acked, ['a']);
        expect(source.inbox, isEmpty);
      },
    );

    test(
      'controller shutdown during batch keeps committed and pending work',
      () async {
        await controller.shutdown();
        controller.dispose();
        var entries = 0;
        final entered = Completer<void>();
        final resume = Completer<void>();
        controller = ImportController(
          source: source,
          store: store,
          parsers: {
            LocalBookFormat.txt: (session) async {
              if (++entries == 2) {
                entered.complete();
                await resume.future;
              }
              return fakeParser(session);
            },
            LocalBookFormat.epub: (session) async => fakeParser(session),
          },
        );
        for (var i = 1; i <= 3; i++) {
          source.receive(
            id: 'r$i',
            name: 'Book$i.txt',
            content: utf8.encode('Offline book number $i.'),
          );
        }
        await controller.start();
        final run = controller.submit();
        await entered.future;
        final down = controller.shutdown();
        resume.complete();
        await run;
        await down;
        expect(source.acked, ['r1']);
        expect(source.inbox.map((c) => c.id), ['r2', 'r3']);
        expect(controller.items.map((i) => i.phase), [
          ImportItemPhase.succeeded,
          ImportItemPhase.ready,
          ImportItemPhase.ready,
        ]);
        expect(entries, 2);
        expect(await committed(), 1);
      },
    );

    test('refresh while importing does not overwrite batch state', () async {
      await controller.shutdown();
      controller.dispose();
      var entries = 0;
      final entered = Completer<void>();
      final resume = Completer<void>();
      controller = ImportController(
        source: source,
        store: store,
        parsers: {
          LocalBookFormat.txt: (session) async {
            if (++entries == 1) {
              entered.complete();
              await resume.future;
            }
            return fakeParser(session);
          },
          LocalBookFormat.epub: (session) async => fakeParser(session),
        },
      );
      source.receive(id: 'r1', name: 'a.txt', content: utf8.encode('alpha'));
      source.receive(id: 'r2', name: 'b.txt', content: utf8.encode('beta'));
      await controller.start();
      final run = controller.submit();
      await entered.future;
      await controller.refresh();
      expect(controller.items.length, 2);
      expect(controller.items[0].phase, ImportItemPhase.importing);
      expect(controller.items[1].phase, ImportItemPhase.ready);
      resume.complete();
      await run;
      expect(source.acked, ['r1', 'r2']);
    });

    test(
      'restart recovers remaining pending candidates with stable identities',
      () async {
        await controller.shutdown();
        controller.dispose();
        var entries = 0;
        final entered = Completer<void>();
        final resume = Completer<void>();
        controller = ImportController(
          source: source,
          store: store,
          parsers: {
            LocalBookFormat.txt: (session) async {
              if (++entries == 2) {
                entered.complete();
                await resume.future;
              }
              return fakeParser(session);
            },
            LocalBookFormat.epub: (session) async => fakeParser(session),
          },
        );
        for (var i = 1; i <= 3; i++) {
          source.receive(
            id: 'r$i',
            name: 'Book$i.txt',
            content: utf8.encode('Offline book number $i.'),
          );
        }
        await controller.start();
        final run = controller.submit();
        await entered.future;
        final stop = controller.cancel();
        resume.complete();
        await run;
        await stop;
        await controller.shutdown();
        controller.dispose();
        // Simulated relaunch: same durable inbox and store, fresh controller.
        controller = ImportController(
          source: source,
          store: store,
          parsers: {
            LocalBookFormat.txt: (session) async => fakeParser(session),
            LocalBookFormat.epub: (session) async => fakeParser(session),
          },
        );
        await controller.start();
        expect(controller.items.map((i) => i.candidate.id), ['r2', 'r3']);
        expect(controller.items.map((i) => i.phase).toSet(), {
          ImportItemPhase.ready,
        });
        await controller.submit();
        expect(source.acked, ['r1', 'r2', 'r3']);
        expect(await committed(), 3);
      },
    );
  });

  Future<void> pumpImportPanel(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
    double scale = 1.0,
    ValueChanged<NovelKey>? onRead,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: ImportOverlay(
          controller: controller,
          onRead: onRead,
          child: child!,
        ),
      ),
      home: const Scaffold(body: Text('Reader position unchanged')),
    ),
  );

  testWidgets(
    'incoming banner cancellation releases receipts and preserves route at large Chinese text',
    (tester) async {
      await controller.start();
      await pumpImportPanel(tester, scale: 1.6);
      source.receive();
      await tester.pumpAndSettle();
      expect(find.text('Reader position unchanged'), findsOneWidget);
      expect(find.text('有文件等待导入'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('有文件等待导入'), findsNothing);
      expect(source.inbox, isEmpty);
      expect(controller.items, isEmpty);
      source.receive(id: 'replacement', error: ImportProblem.unreadable);
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(controller.phase, ImportPhase.idle);
      expect(source.inbox, isEmpty);
      expect(find.text('有文件等待导入'), findsNothing);
      expect(tester.takeException(), null);
    },
  );

  group('overlay batch', () {
    for (final count in [1, 3]) {
      testWidgets('cancel $count selected files allows a fresh selection', (
        tester,
      ) async {
        for (var i = 0; i < count; i++) {
          source.receive(id: 'cancel-$i');
        }
        await controller.start();
        controller.open();
        await pumpImportPanel(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(source.inbox, isEmpty);
        expect(controller.items, isEmpty);
        expect(controller.panelOpen, false);
        controller.open();
        await tester.pumpAndSettle();
        expect(find.text('选择文件'), findsOneWidget);
        expect(find.text('Reader position unchanged'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
    for (final expanded in [false, true]) {
      for (final rejection in [ImportProblem.busy, ImportProblem.batchLimit]) {
        testWidgets(
          'external $rejection is visible with expanded=$expanded and preserves ready receipts',
          (tester) async {
            source.receive(
              id: 'a',
              name: 'a.txt',
              content: utf8.encode('alpha'),
            );
            source.receive(
              id: 'b',
              name: 'b.txt',
              content: utf8.encode('beta'),
            );
            await controller.start();
            final originalItems = List<ImportItemState>.of(controller.items);
            final originalReceipts = List<ImportCandidate>.of(source.inbox);
            if (expanded) controller.open();
            await pumpImportPanel(tester);
            await tester.pumpAndSettle();

            source.events.add(const ImportSourceEvent(copiedBytes: 0));
            await tester.pump();
            source.events.add(ImportSourceEvent(problem: rejection));
            await tester.pump();
            source.events.add(const ImportSourceEvent(completed: true));
            await tester.pumpAndSettle();

            final l = AppLocalizations.of(
              tester.element(find.byType(Scaffold)),
            );
            expect(
              find.text(
                rejection == ImportProblem.busy
                    ? l.importBusy
                    : l.importBatchLimit,
              ),
              findsOneWidget,
            );
            expect(controller.batchProblem, rejection);
            expect(controller.busy, false);
            expect(controller.items, originalItems);
            expect(
              controller.items.map((item) => item.candidate),
              originalReceipts,
            );
            expect(controller.items.map((item) => item.phase), [
              ImportItemPhase.ready,
              ImportItemPhase.ready,
            ]);
            expect(
              controller.items.every(
                (item) => item.problem == null && item.result == null,
              ),
              true,
            );
            expect(source.inbox, originalReceipts);
            expect(source.acked, isEmpty);
            expect(parses, 0);
            expect(controller.panelOpen, expanded);
            expect(find.text('Reader position unchanged'), findsOneWidget);
            expect(tester.takeException(), null);
          },
        );
      }

      testWidgets(
        'focus item error is not a batch error with expanded=$expanded',
        (tester) async {
          source.receive(
            id: 'bad',
            name: 'bad.txt',
            error: ImportProblem.unsupported,
          );
          source.receive(id: 'ready', name: 'ready.txt');
          await controller.start();
          if (expanded) controller.open();
          await pumpImportPanel(tester);
          await tester.pumpAndSettle();
          final l = AppLocalizations.of(tester.element(find.byType(Scaffold)));
          expect(controller.problem, ImportProblem.unsupported);
          expect(controller.batchProblem, null);
          expect(find.byKey(const ValueKey('import-error')), findsNothing);
          expect(
            find.text(l.importUnsupported),
            expanded ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), null);
        },
      );
    }

    testWidgets('single item keeps the compact flow with read-now', (
      tester,
    ) async {
      source.receive();
      await controller.start();
      await pumpImportPanel(tester, onRead: (_) {});
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      expect(find.text('Book.txt'), findsOneWidget);
      expect(find.text('导入'), findsOneWidget);
      expect(find.text('导入全部'), findsNothing);
      await tester.runAsync(() => controller.submit());
      await tester.pumpAndSettle();
      expect(find.text('立即阅读'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('Reader position unchanged'), findsOneWidget);
      expect(tester.takeException(), null);
    });

    testWidgets('three ready items list filenames in order with one action', (
      tester,
    ) async {
      for (var i = 1; i <= 3; i++) {
        source.receive(
          id: 'r$i',
          name: 'book0$i.txt',
          content: utf8.encode('Offline book number $i.'),
        );
      }
      await controller.start();
      await pumpImportPanel(tester);
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      expect(find.text('准备导入 3 本书'), findsOneWidget);
      for (var i = 1; i <= 3; i++) {
        expect(find.text('book0$i.txt'), findsOneWidget);
      }
      expect(find.text('导入全部'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      final first = tester.getTopLeft(find.text('book01.txt')).dy;
      final second = tester.getTopLeft(find.text('book02.txt')).dy;
      final third = tester.getTopLeft(find.text('book03.txt')).dy;
      expect(first < second, true);
      expect(second < third, true);
      expect(tester.takeException(), null);
    });

    testWidgets('importing batch shows position, statuses and stop', (
      tester,
    ) async {
      await controller.shutdown();
      controller.dispose();
      var entries = 0;
      late Completer<void> entered;
      late Completer<void> resume;
      // These futures are awaited by real file I/O in runAsync. Creating them
      // in the fake test zone can strand their completion microtasks there.
      await tester.runAsync(() async {
        entered = Completer<void>();
        resume = Completer<void>();
      });
      controller = ImportController(
        source: source,
        store: store,
        parsers: {
          LocalBookFormat.txt: (session) async {
            if (++entries == 2) {
              entered.complete();
              await resume.future;
            }
            return fakeParser(session);
          },
          LocalBookFormat.epub: (session) async => fakeParser(session),
        },
      );
      source.receive(id: 'a', name: 'a.txt', content: utf8.encode('alpha'));
      source.receive(id: 'b', name: 'b.txt', content: utf8.encode('beta'));
      source.receive(id: 'c', name: 'c.txt', content: utf8.encode('gamma'));
      await controller.start();
      await pumpImportPanel(tester);
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      Future<void>? run;
      try {
        await tester.runAsync(() async {
          run = controller.submit();
          // The importing phase starts before parsing. Wait for the actual
          // pause so disk speed cannot decide whether the gate is exercised.
          await entered.future.timeout(const Duration(seconds: 10));
        });
        await tester.pump();
        expect(find.text('正在导入 2 / 3'), findsOneWidget);
        expect(find.text('已导入'), findsOneWidget); // a
        expect(find.text('正在导入'), findsOneWidget); // b row status
        expect(find.text('等待导入'), findsOneWidget); // c
        expect(find.text('停止导入'), findsOneWidget);
        expect(tester.takeException(), null);
      } finally {
        // A failed UI assertion must not leave shutdown waiting on our gate.
        await tester.runAsync(() async {
          resume.complete();
          await run?.timeout(const Duration(seconds: 10));
        });
      }
      await tester.pumpAndSettle();
      expect(find.text('已导入 3 本书'), findsOneWidget);
    });

    testWidgets('partial failure shows summary and retry entry', (
      tester,
    ) async {
      source.receive(id: 'a', name: 'a.txt', content: utf8.encode('alpha'));
      source.receive(
        id: 'b',
        name: 'broken.epub',
        content: utf8.encode('not a zip'),
      );
      source.receive(id: 'c', name: 'c.txt', content: utf8.encode('gamma'));
      await controller.start();
      await pumpImportPanel(tester);
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      await tester.runAsync(() => controller.submit());
      await tester.pumpAndSettle();
      expect(find.text('导入完成'), findsOneWidget);
      expect(find.textContaining('成功 2 本'), findsOneWidget);
      expect(find.textContaining('失败 1 本'), findsOneWidget);
      expect(find.textContaining('内容与格式不符'), findsOneWidget);
      expect(find.text('重试失败项'), findsOneWidget);
      expect(tester.takeException(), null);
    });

    testWidgets('retry failed commits the remaining receipt only', (
      tester,
    ) async {
      source.receive(id: 'a', name: 'a.txt', content: utf8.encode('alpha'));
      source.receive(
        id: 'b',
        name: 'broken.epub',
        content: utf8.encode('not a zip'),
      );
      source.receive(id: 'c', name: 'c.txt', content: utf8.encode('gamma'));
      await controller.start();
      await pumpImportPanel(tester);
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      await tester.runAsync(() => controller.submit());
      await tester.pumpAndSettle();
      source.files['b'] = [0x50, 0x4b, 3, 4, 5];
      await tester.runAsync(() async {
        await tester.tap(find.text('重试失败项'));
        while (controller.busy) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('已导入 3 本书'), findsOneWidget);
      expect(source.acked, ['a', 'c', 'b']);
      expect(parses, 3); // Committed items never re-parse.
      expect(tester.takeException(), null);
    });

    testWidgets('fatal stop reason outranks the earlier item failure', (
      tester,
    ) async {
      await controller.shutdown();
      controller.dispose();
      var entries = 0;
      controller = ImportController(
        source: source,
        store: store,
        parsers: {
          LocalBookFormat.txt: (session) async {
            if (++entries == 1) throw StateError('storage layer broke');
            return fakeParser(session);
          },
          LocalBookFormat.epub: (session) async => fakeParser(session),
        },
      );
      source.receive(
        id: 'a',
        name: 'broken.epub',
        content: utf8.encode('not a zip'),
      );
      source.receive(id: 'b', name: 'b.txt', content: utf8.encode('beta'));
      source.receive(id: 'c', name: 'c.txt', content: utf8.encode('gamma'));
      await controller.start();
      await pumpImportPanel(tester);
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      await tester.runAsync(() => controller.submit());
      await tester.pumpAndSettle();
      expect(find.text('导入已停止'), findsOneWidget);
      // The batch-level stop reason is shown once at the top; the failing
      // item's own row also shows the same storage message.
      expect(find.byKey(const ValueKey('import-error')), findsOneWidget);
      expect(find.text('无法保存文件，请检查可用空间后重试。'), findsWidgets);
      expect(find.textContaining('剩余 1 本未处理'), findsOneWidget);
      expect(find.text('等待导入'), findsOneWidget); // c never started
      expect(find.textContaining('内容与格式不符'), findsOneWidget); // a's own row
      expect(find.text('导入完成'), findsNothing);
      expect(tester.takeException(), null);
    });

    testWidgets('encoding chooser names the current TXT and resumes', (
      tester,
    ) async {
      await controller.shutdown();
      controller.dispose();
      final decoder = PreviewDecoder({'a.txt'});
      controller = ImportController(
        source: source,
        store: store,
        decoder: decoder,
      );
      source.receive(id: 'a', name: 'a.txt', content: utf8.encode('alpha'));
      source.receive(id: 'b', name: 'b.txt', content: utf8.encode('beta'));
      await controller.start();
      await pumpImportPanel(tester);
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      late Future<void> run;
      await tester.runAsync(() async {
        run = controller.submit();
        await untilImport(() => controller.choosingEncoding);
      });
      await tester.pump();
      expect(find.text('a.txt'), findsOneWidget); // The paused TXT itself.
      expect(find.text('请检查预览，选择文字显示正确的编码后继续。'), findsOneWidget);
      expect(find.text('中文样本'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('GB18030 / GBK'));
        await run;
      });
      await tester.pumpAndSettle();
      expect(find.text('已导入 2 本书'), findsOneWidget);
      expect(source.acked, ['a', 'b']);
    });

    testWidgets('stop during encoding confirmation keeps every receipt', (
      tester,
    ) async {
      await controller.shutdown();
      controller.dispose();
      final decoder = PreviewDecoder({'a.txt'});
      controller = ImportController(
        source: source,
        store: store,
        decoder: decoder,
      );
      source.receive(id: 'a', name: 'a.txt', content: utf8.encode('alpha'));
      source.receive(id: 'b', name: 'b.txt', content: utf8.encode('beta'));
      source.receive(id: 'c', name: 'c.txt', content: utf8.encode('gamma'));
      await controller.start();
      await pumpImportPanel(tester);
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      Future<void>? run;
      try {
        await tester.runAsync(() async {
          run = controller.submit();
          await untilImport(() => controller.choosingEncoding);
        });
        await tester.pump();
        expect(find.text('停止导入'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('停止导入'));
        });
      } finally {
        await tester.runAsync(() async {
          await run?.timeout(const Duration(seconds: 10));
        });
      }
      await tester.runAsync(() => untilImport(() => !controller.busy));
      await tester.pumpAndSettle();
      expect(controller.busy, false);
      expect(controller.phase, ImportPhase.idle);
      expect(decoder.names, ['a.txt']); // b and c never start.
      expect(source.acked, isEmpty); // Nothing is acknowledged.
      expect(source.inbox.map((c) => c.id), ['a', 'b', 'c']);
      expect(tester.takeException(), null);
    });

    testWidgets('stop importing keeps commits and pending receipts', (
      tester,
    ) async {
      await controller.shutdown();
      controller.dispose();
      var entries = 0;
      late Completer<void> entered;
      late Completer<void> resume;
      // Keep the parser's pause and completion in the real async zone.
      await tester.runAsync(() async {
        entered = Completer<void>();
        resume = Completer<void>();
      });
      controller = ImportController(
        source: source,
        store: store,
        parsers: {
          LocalBookFormat.txt: (session) async {
            if (++entries == 2) {
              entered.complete();
              await resume.future;
            }
            return fakeParser(session);
          },
          LocalBookFormat.epub: (session) async => fakeParser(session),
        },
      );
      source.receive(id: 'a', name: 'a.txt', content: utf8.encode('alpha'));
      source.receive(id: 'b', name: 'b.txt', content: utf8.encode('beta'));
      source.receive(id: 'c', name: 'c.txt', content: utf8.encode('gamma'));
      await controller.start();
      await pumpImportPanel(tester);
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      Future<void>? run;
      try {
        await tester.runAsync(() async {
          run = controller.submit();
          await entered.future.timeout(const Duration(seconds: 10));
        });
        await tester.pump();
        await tester.runAsync(() async {
          await tester.tap(find.text('停止导入'));
        });
      } finally {
        await tester.runAsync(() async {
          resume.complete();
          await run?.timeout(const Duration(seconds: 10));
        });
      }
      await tester.runAsync(() => untilImport(() => !controller.busy));
      await tester.pumpAndSettle();
      expect(controller.phase, ImportPhase.idle);
      expect(source.acked, ['a']); // Committed item survives the stop.
      expect(source.inbox.map((c) => c.id), ['b', 'c']);
      expect(find.text('导入全部'), findsNothing); // Snoozed, nothing deleted.
      expect(find.text('有文件等待导入'), findsNothing);
      expect(tester.takeException(), null);
    });

    testWidgets('64 items stay scrollable at Chinese text scale 1.6', (
      tester,
    ) async {
      for (var i = 1; i <= 64; i++) {
        source.receive(
          id: 'r$i',
          name: 'book$i.txt',
          content: utf8.encode('Offline book number $i.'),
        );
      }
      await controller.start();
      await pumpImportPanel(tester, scale: 1.6);
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      expect(find.text('准备导入 64 本书'), findsOneWidget);
      expect(find.text('导入全部'), findsOneWidget);
      final actionPosition = tester.getRect(find.text('导入全部'));
      await tester.scrollUntilVisible(find.text('book64.txt'), 200);
      expect(find.text('book64.txt').hitTestable(), findsOneWidget);
      expect(find.text('导入全部').hitTestable(), findsOneWidget);
      expect(tester.getRect(find.text('导入全部')), actionPosition);
      expect(tester.takeException(), null);
    });

    testWidgets('long filenames and long errors do not overflow', (
      tester,
    ) async {
      final longName = '${'超长书名测试' * 30}.txt';
      source.receive(id: 'a', name: longName, content: utf8.encode('alpha'));
      source.receive(
        id: 'b',
        name: 'bad.epub',
        content: utf8.encode('not a zip'),
      );
      source.receive(id: 'c', name: 'c.txt', error: ImportProblem.parseLimit);
      await controller.start();
      await pumpImportPanel(tester, scale: 1.6);
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      await tester.runAsync(() => controller.submit());
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      expect(find.text(longName), findsOneWidget);
      expect(find.textContaining('解析限制'), findsOneWidget);
      expect(find.text('Reader position unchanged'), findsOneWidget);
    });
  });
}
