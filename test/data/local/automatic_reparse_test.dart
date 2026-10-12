import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:shiori/data/local/record_codec.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/data/local/local_guard.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import '../../domain/reparse_position_test.dart' as f;
import 'local_reading_test.dart' show ForbiddenOnline;
import 'support/epub_fixtures.dart';

T ok<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}

CancellationToken token() => CancellationSource().token;

class GateDecoder implements LocalBookDecoder {
  final entered = Completer<void>(), resume = Completer<void>();
  final calls = <NovelKey>[];
  bool exited = false;
  Object? failure;
  @override
  Future<LocalBookContent> decode(
    LocalImportSession session, {
    required LocalBookFormat format,
    required String filename,
    required CancellationToken cancellation,
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
  }) async {
    calls.add(session.key);
    if (!entered.isCompleted) {
      entered.complete();
      await Future.any([resume.future, cancellation.whenCancelled]);
    }
    try {
      checkLocalCancellation(cancellation);
      if (failure != null) throw failure!;
      return await const BookDecoder().decode(
        session,
        format: format,
        filename: filename,
        cancellation: cancellation,
        chooseEncoding: chooseEncoding,
        encoding: encoding,
      );
    } finally {
      exited = true;
    }
  }
}

class BudgetClock extends Stopwatch {
  @override
  Duration get elapsed => const Duration(minutes: 3);
}

class FlushLibrary extends LocalLibraryRepository {
  FlushLibrary(super.db);
  final entered = Completer<void>(), finish = Completer<void>();
  @override
  Future<Result<bool>> saveProgress(
    ReadingProgress progress, {
    required ProgressWriteStamp stamp,
    required CancellationToken cancellation,
  }) async {
    if (!entered.isCompleted) entered.complete();
    await finish.future;
    return super.saveProgress(
      progress,
      stamp: stamp,
      cancellation: cancellation,
    );
  }
}

void main() {
  late Directory temp;
  late AppPaths paths;
  late UserDatabase db;
  late ManagedLocalBooks store;
  late LocalLibraryRepository library;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('auto-reparse-');
    paths = AppPaths(
      support: Directory('${temp.path}/s'),
      temporary: temp,
      environment: StorageEnvironment.development,
    );
    await paths.prepare();
    db = UserDatabase(NativeDatabase(paths.userDatabase));
    store = ok(await ManagedLocalBooks.open(paths, db));
    library = LocalLibraryRepository(db);
  });
  tearDown(() async {
    await store.close();
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<LocalBookRecord> add(
    String text, {
    bool shelf = false,
    bool epub = false,
  }) async {
    final format = epub ? LocalBookFormat.epub : LocalBookFormat.txt;
    final result = ok(
      await store.importBook(
        bytes: Stream.value(epub ? zipFiles(epubFiles()) : utf8.encode(text)),
        format: format,
        addToShelf: shelf,
        cancellation: token(),
        parse: (s) => const BookDecoder().decode(
          s,
          format: format,
          filename: '$text.${format.name}',
          cancellation: token(),
          chooseEncoding: (_) async => TxtEncoding.utf8,
        ),
      ),
    );
    await db.customStatement(
      'UPDATE local_books SET parser_version=25 WHERE digest=?',
      [result.content.detail.summary.key.novelId],
    );
    return result;
  }

  Future<void> save(
    LocalBookRecord book, {
    int sequence = 0,
    int? generation,
    double fraction = .5,
  }) async {
    final key = book.content.detail.summary.key;
    generation ??= ok(
      await library.beginProgressSession(key, cancellation: token()),
    );
    expect(
      ok(
        await library.saveProgress(
          f.progress(book.content, fraction: fraction),
          stamp: ProgressWriteStamp(
            generation: generation!,
            sequence: sequence,
          ),
          cancellation: token(),
        ),
      ),
      isTrue,
    );
  }

  Future<Map<String, Object?>> row(NovelKey key) async =>
      (await db
              .customSelect(
                'SELECT * FROM local_books WHERE digest=?',
                variables: [Variable(key.novelId)],
              )
              .getSingle())
          .data;
  Future<void> start({
    LocalBookDecoder decoder = const BookDecoder(),
    int maxBooks = 15,
    Future<void> Function(String)? checkpoint,
    Future<int?> Function(Directory)? freeSpace,
    Stopwatch Function() clock = Stopwatch.new,
    DateTime Function()? now,
  }) async {
    store.automaticReparseActivity(resumed: true);
    store.startAutomaticReparse(
      initialDelay: Duration.zero,
      decoder: decoder,
      maxBooks: maxBooks,
      checkpoint: checkpoint,
      freeSpace: freeSpace,
      prepareClock: clock,
      now: now,
    );
    await Future<void>.delayed(
      Duration.zero,
    ); // Deliver the initial scheduling timer.
  }

  Future<void> idle() => store.automaticReparseIdle;
  Future<List<Map<String, Object?>>> attempts() async =>
      (await db.customSelect('SELECT * FROM local_reparse_attempts').get())
          .map((r) => r.data)
          .toList();

  test('initial ten-second delay does not launch while backgrounded', () async {
    final a = await add('initial delay');
    final key = a.content.detail.summary.key;
    store.automaticReparseActivity(resumed: true);
    fakeAsync((clock) {
      store.startAutomaticReparse();
      clock.elapse(const Duration(seconds: 9));
      store.automaticReparseActivity(resumed: false, cancelPrepare: true);
      clock.elapse(const Duration(seconds: 1));
    });
    expect((await row(key))['active_bundle'], isNull);
    store.automaticReparseActivity(resumed: true);
    await idle();
    expect((await row(key))['parser_version'], BookDecoder.parserVersion);
  });
  test(
    'deterministic shelf, reading time, import time and digest priority',
    () async {
      final recentShelf = await add('recent shelf', shelf: true),
          oldShelf = await add('old shelf', shelf: true),
          read = await add('unshelved recent read'),
          unread = await add('unread import'),
          tie = await add('same import');
      await save(recentShelf);
      await save(oldShelf);
      await save(read);
      await db.customStatement('UPDATE local_books SET imported_at=100');
      await db.customStatement(
        'UPDATE local_books SET imported_at=200 WHERE digest=?',
        [unread.content.detail.summary.key.novelId],
      );
      await db.customStatement('UPDATE reading_progress SET last_read_at=1');
      await db.customStatement(
        'UPDATE reading_progress SET last_read_at=2 WHERE novel_id=?',
        [recentShelf.content.detail.summary.key.novelId],
      );
      await db.customStatement(
        'UPDATE reading_progress SET last_read_at=3 WHERE novel_id=?',
        [read.content.detail.summary.key.novelId],
      );
      final gate = GateDecoder()..resume.complete();
      await start(decoder: gate);
      await idle();
      expect(
        gate.calls,
        [
          recentShelf,
          oldShelf,
          read,
          unread,
          tie,
        ].map((b) => b.content.detail.summary.key).toList(),
      );
    },
  );
  test('time budget alone stops new preparation across resumed', () async {
    await add('time first');
    await add('time second');
    final gate = GateDecoder()..resume.complete();
    await start(decoder: gate, clock: BudgetClock.new);
    await idle();
    store.automaticReparseActivity(resumed: true);
    await idle();
    expect(gate.calls.length, 1);
  });
  test(
    'an actual in-flight final flush retains the Reader lease until SQL succeeds',
    () async {
      final a = await add('in-flight flush');
      final key = a.content.detail.summary.key;
      final flush = FlushLibrary(db);
      final controller = ReaderController(
        repository: LocalReadingRepository(
          local: store,
          online: ForbiddenOnline(),
        ),
        chapter: a.content.chapters.first.key,
        library: flush,
      );
      await controller.load();
      await controller.retryProgress();
      controller.sampleProgress(f.progress(a.content).position, true);
      controller.onDelete();
      final closed = controller.closeReader();
      await flush.entered.future;
      await start();
      await idle();
      expect((await row(key))['active_bundle'], isNull);
      flush.finish.complete();
      await closed;
      await idle();
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
      expect(
        ok(
          await library.getProgress(key, cancellation: token()),
        )!.position.blockFraction,
        .5,
      );
    },
  );
  test(
    'approximate skip survives manual failure and restart; manual success clears it',
    () async {
      final a = await add('original new text');
      final key = a.content.detail.summary.key;
      final file = File(
        '${paths.localBooks.path}/${key.novelId}/manifest.json',
      );
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final chapter = a.content.chapters.first;
      map['chapters'] = [
        RecordCodec.chapter(
          ChapterContent(
            key: chapter.key,
            title: chapter.title,
            blocks: [ParagraphBlock(text: 'legacy unrelated text')],
          ),
        ),
      ];
      final bytes = utf8.encode(jsonEncode(map));
      await file.writeAsBytes(bytes);
      await db.customStatement(
        'UPDATE local_books SET manifest_hash=? WHERE digest=?',
        [sha256.convert(bytes).toString(), key.novelId],
      );
      final old = ok(await store.read(key, cancellation: token()))!;
      await save(old);
      final before = ok(await library.getProgress(key, cancellation: token()));
      final decoder = GateDecoder()..resume.complete();
      await start(decoder: decoder);
      await idle();
      expect((await attempts()).single['outcome'], 'approximatePosition');
      expect(ok(await library.getProgress(key, cancellation: token())), before);
      final skipped = (await attempts()).single;
      decoder.failure = const FileSystemException(
        'Injected write failure',
        '',
        OSError('Disk full', 28),
      );
      expect(
        await store.reparseBook(
          key,
          cancellation: token(),
          chooseEncoding: (_) async => TxtEncoding.utf8,
        ),
        isA<Failure<LocalReparseResult>>(),
      );
      expect((await attempts()).single, skipped);
      expect(
        ok(await store.watchBooks().first).single.autoReparseIssue,
        LocalAutoReparseIssue.approximatePosition,
      );
      expect(ok(await library.getProgress(key, cancellation: token())), before);
      await store.close();
      store = ok(await ManagedLocalBooks.open(paths, db));
      decoder.failure = null;
      final calls = decoder.calls.length;
      await start(decoder: decoder);
      await idle();
      expect(decoder.calls.length, calls);
      expect((await row(key))['parser_version'], 25);
      expect((await attempts()).single, skipped);
      ok(
        await store.reparseBook(
          key,
          cancellation: token(),
          chooseEncoding: (_) async => TxtEncoding.utf8,
        ),
      );
      expect(await attempts(), isEmpty);
    },
  );
  for (final reason in ['ambiguousEncoding', 'originalCorrupt']) {
    test('manual failure preserves terminal $reason', () async {
      final a = await add('manual terminal $reason');
      final key = a.content.detail.summary.key;
      await db.customStatement(
        'INSERT INTO local_reparse_attempts VALUES(?,?,?,?,?,?)',
        [key.novelId, BookDecoder.parserVersion, reason, 0, null, 1],
      );
      final decoder = GateDecoder()
        ..resume.complete()
        ..failure = const LocalParseException(LocalParseProblem.timeout);
      await start(decoder: decoder);
      await idle();
      expect(decoder.calls, isEmpty);
      final skipped = (await attempts()).single;
      expect(
        await store.reparseBook(
          key,
          cancellation: token(),
          chooseEncoding: (_) async => TxtEncoding.utf8,
        ),
        isA<Failure<LocalReparseResult>>(),
      );
      expect((await attempts()).single, skipped);
    });
  }
  test('manual failures preserve automatic retry history and counts', () async {
    final a = await add('manual storage failure');
    final key = a.content.detail.summary.key;
    final decoder = GateDecoder()
      ..resume.complete()
      ..failure = const LocalParseException(LocalParseProblem.timeout);
    await start(decoder: decoder);
    await idle();
    final previous = (await attempts()).single;
    decoder.failure = const FileSystemException(
      'Injected write failure',
      '',
      OSError('Permission denied', 13),
    );
    for (var i = 0; i < 5; i++) {
      expect(
        await store.reparseBook(
          key,
          cancellation: token(),
          chooseEncoding: (_) async => TxtEncoding.utf8,
        ),
        isA<Failure<LocalReparseResult>>(),
      );
      expect((await attempts()).single, previous);
    }
    store.automaticReparseActivity(resumed: true);
    await idle();
    expect(decoder.calls.length, 6);
    expect((await row(key))['parser_version'], 25);
  });
  test(
    'five manual failures cannot create automatic failure records or exclude an old book',
    () async {
      final a = await add('manual failure without automatic history');
      final key = a.content.detail.summary.key;
      final original = File('${paths.localBooks.path}/${key.novelId}/original');
      final bytes = await original.readAsBytes();
      await original.writeAsString('Injected corruption');
      for (var i = 0; i < 5; i++) {
        final result = await store.reparseBook(
          key,
          cancellation: token(),
          chooseEncoding: (_) async => TxtEncoding.utf8,
        );
        expect(result, isA<Failure<LocalReparseResult>>());
        expect((result as Failure).failure.kind, FailureKind.parse);
        expect(await attempts(), isEmpty);
      }
      await original.writeAsBytes(bytes);
      await start();
      await idle();
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
    },
  );
  test(
    'known terminal semantics cannot be cleared by an exact catalog migration',
    () async {
      final a = await add('terminal semantics');
      final key = a.content.detail.summary.key;
      final progress = f.progress(a.content, fraction: 1);
      final generation = ok(
        await library.beginProgressSession(key, cancellation: token()),
      );
      final completed = progress.withBookProgress(
        a.content.progressMetrics.at(
          progress.chapterKey,
          1,
          terminal: BookTerminalState.finished,
        ),
      );
      ok(
        await library.saveProgress(
          completed,
          stamp: ProgressWriteStamp(generation: generation, sequence: 0),
          cancellation: token(),
        ),
      );
      final file = File(
        '${paths.localBooks.path}/${key.novelId}/manifest.json',
      );
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final catalog = a.content.catalog;
      final modified = Catalog(
        novelKey: key,
        volumes: [
          Volume(
            groupId: 'changed',
            chapters: [
              Chapter(
                key: progress.chapterKey,
                title: 'Different title',
                ordinal: 0,
                volumeGroupId: 'changed',
              ),
            ],
          ),
        ],
      );
      map['catalog'] = RecordCodec.catalog(modified);
      final bytes = utf8.encode(jsonEncode(map));
      await file.writeAsBytes(bytes);
      await db.customStatement(
        'UPDATE local_books SET manifest_hash=? WHERE digest=?',
        [sha256.convert(bytes).toString(), key.novelId],
      );
      final saved = completed.withBookProgress(
        completed.bookProgress,
        revision: modified.revision,
      );
      await db.customStatement(
        'UPDATE reading_progress SET catalog_revision=?',
        [modified.revision],
      );
      expect(catalog.revision, isNot(modified.revision));
      await start();
      await idle();
      expect((await row(key))['active_bundle'], isNull);
      expect((await attempts()).single['outcome'], 'approximatePosition');
      expect(
        ok(
          await library.getProgress(key, cancellation: token()),
        )!.bookProgress!.terminal,
        saved.bookProgress!.terminal,
      );
    },
  );
  test(
    'failure backoff does not consume book quota; target version increase reevaluates',
    () async {
      final failed = await add('failed quota', shelf: true),
          eligible = await add('eligible quota');
      await db.customStatement(
        'INSERT INTO local_reparse_attempts VALUES(?,?,?,?,?,?)',
        [
          failed.content.detail.summary.key.novelId,
          BookDecoder.parserVersion,
          'other',
          1,
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
          1,
        ],
      );
      await start(maxBooks: 1);
      await idle();
      expect(
        (await row(eligible.content.detail.summary.key))['parser_version'],
        BookDecoder.parserVersion,
      );
      expect(
        (await row(failed.content.detail.summary.key))['parser_version'],
        25,
      );
      await store.close();
      store = ok(await ManagedLocalBooks.open(paths, db));
      await db.customStatement(
        'UPDATE local_reparse_attempts SET target_parser_version=28,next_retry_at=NULL,outcome=?',
        ['ambiguousEncoding'],
      );
      await start();
      await idle();
      expect(
        (await row(failed.content.detail.summary.key))['parser_version'],
        BookDecoder.parserVersion,
      );
    },
  );

  test(
    'failed Reader initialization releases its use before disposal',
    () async {
      final a = await add('initialization failure');
      final key = a.content.detail.summary.key;
      final controller = ReaderController(
        repository: LocalReadingRepository(
          local: store,
          online: ForbiddenOnline(),
        ),
        chapter: LocalBookIdentity.chapter(key, 'missing'),
      );
      await controller.load();
      expect(controller.status, ReaderStatus.error);
      await start();
      await idle();
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
      controller.onDelete();
      await controller.closeReader();
    },
  );
  test(
    'saved TXT encoding conflicting with BOM is an ordinary failure',
    () async {
      final a = await add('\ufeffBOM text');
      final key = a.content.detail.summary.key;
      final file = File(
        '${paths.localBooks.path}/${key.novelId}/manifest.json',
      );
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      map['txtEncoding'] = 'gb18030';
      final bytes = utf8.encode(jsonEncode(map));
      await file.writeAsBytes(bytes);
      await db.customStatement(
        'UPDATE local_books SET manifest_hash=? WHERE digest=?',
        [sha256.convert(bytes).toString(), key.novelId],
      );
      await start();
      await idle();
      expect((await attempts()).single['outcome'], 'other');
      expect((await attempts()).single['failure_count'], 1);
      expect((await attempts()).single['next_retry_at'], isNotNull);
      expect((await row(key))['active_bundle'], isNull);
    },
  );
  test(
    'an older layered Reader failing after a newer clean close still defers',
    () async {
      final a = await add('layered final failure');
      final key = a.content.detail.summary.key;
      final older = (await store.acquireBookUse(key, cancellation: token()))!;
      final newer = (await store.acquireBookUse(key, cancellation: token()))!;
      await start();
      await idle();
      await save(a);
      await newer.release(progressSaved: true);
      await older.release(progressSaved: false);
      await idle();
      expect((await row(key))['active_bundle'], isNull);
      final retry = (await store.acquireBookUse(key, cancellation: token()))!;
      await save(a);
      await retry.release(progressSaved: true);
      await idle();
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
    },
  );
  test('manual priority can cancel a stalled native capacity query', () async {
    final a = await add('capacity cancellation');
    final key = a.content.detail.summary.key;
    final entered = Completer<void>(), capacity = Completer<int?>();
    await start(
      freeSpace: (_) {
        entered.complete();
        return capacity.future;
      },
    );
    await entered.future;
    ok(
      await store.reparseBook(
        key,
        cancellation: token(),
        chooseEncoding: (_) async => TxtEncoding.utf8,
      ),
    );
    expect((await row(key))['parser_version'], BookDecoder.parserVersion);
    capacity.complete(1000000000);
    expect(await attempts(), isEmpty);
  });
  test(
    'publication permission is released even if maintenance rollback fails',
    () async {
      final a = await add('rollback permission');
      final key = a.content.detail.summary.key;
      await db.customStatement(
        "CREATE TRIGGER fail_maintenance BEFORE UPDATE OF maintenance ON local_books WHEN NEW.maintenance=0 BEGIN SELECT RAISE(ABORT,'failure'); END",
      );
      await start();
      await idle();
      final use = (await store.acquireBookUse(key, cancellation: token()))!;
      expect(ok(await store.read(key, cancellation: token())), isNotNull);
      await use.release();
      await db.customStatement('DROP TRIGGER fail_maintenance');
      await store.close();
      store = ok(await ManagedLocalBooks.open(paths, db));
      expect((await row(key))['maintenance'], 0);
    },
  );
  test(
    'uncertain COMMIT cannot retain an old rendition cache in this process',
    () async {
      final a = await add('lost acknowledgement', epub: true);
      final key = a.content.detail.summary.key;
      final chapter = a.content.chapters.first.key;
      final root = '${paths.localBooks.path}/${key.novelId}';
      final oldHtml = utf8.encode(
        jsonEncode({
          chapter.chapterId: '<html><body>Legacy presentation</body></html>',
        }),
      );
      await File('$root/presentations.json').writeAsBytes(oldHtml);
      final manifest = File('$root/manifest.json');
      final map =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      map['presentationHash'] = sha256.convert(oldHtml).toString();
      final bytes = utf8.encode(jsonEncode(map));
      await manifest.writeAsBytes(bytes);
      await db.customStatement(
        'UPDATE local_books SET manifest_hash=? WHERE digest=?',
        [sha256.convert(bytes).toString(), key.novelId],
      );
      expect(
        ok(await store.loadPagePresentation(chapter, cancellation: token())),
        contains('Legacy presentation'),
      );
      final changes = <NovelKey>[];
      final sub = store.changes.listen(changes.add);
      await start(
        checkpoint: (phase) async {
          if (phase == 'afterCommit') throw StateError('lost acknowledgement');
        },
      );
      await idle();
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
      expect(
        ok(await store.loadPagePresentation(chapter, cancellation: token())),
        isNull,
      );
      expect(changes, contains(key));
      await sub.cancel();
    },
  );
  test('empty/current/future versions are not prepared', () async {
    final current = await add('current'), future = await add('future');
    await db.customStatement('UPDATE local_books SET parser_version=?', [
      BookDecoder.parserVersion,
    ]);
    await db.customStatement(
      'UPDATE local_books SET parser_version=100 WHERE digest=?',
      [future.content.detail.summary.key.novelId],
    );
    await start();
    await idle();
    expect(
      (await row(current.content.detail.summary.key))['active_bundle'],
      isNull,
    );
    expect(
      (await row(future.content.detail.summary.key))['parser_version'],
      100,
    );
    expect(await attempts(), isEmpty);
  });
  test(
    'prepare allows both progress APIs and another book read; reader A does not block B',
    () async {
      final a = await add('Reader A long unique text', shelf: true),
          b = await add('Book B');
      final key = a.content.detail.summary.key;
      final lease = (await store.acquireBookUse(key, cancellation: token()))!;
      final invalidations = <NovelKey>[];
      final sub = store.invalidations.listen(invalidations.add);
      final gate = GateDecoder();
      await start(decoder: gate);
      await gate.entered.future;
      expect((await row(key))['maintenance'], 0);
      final generation = ok(
        await library.beginProgressSession(key, cancellation: token()),
      );
      await save(a, generation: generation);
      expect(
        ok(
          await store.read(b.content.detail.summary.key, cancellation: token()),
        ),
        isNotNull,
      );
      gate.resume.complete();
      await idle();
      expect((await row(key))['active_bundle'], isNull);
      expect(
        (await row(b.content.detail.summary.key))['parser_version'],
        BookDecoder.parserVersion,
      );
      expect(invalidations, isEmpty);
      await lease.release(progressSaved: true);
      await idle();
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
      final saved = ok(await library.getProgress(key, cancellation: token()))!;
      expect(saved.completed, isTrue);
      expect(saved.lastReadAt, DateTime.utc(2025));
      expect(saved.position.blockFraction, .5);
      await sub.cancel();
    },
  );
  test(
    'failed final flush defers; clean later session unblocks and repeated release is safe',
    () async {
      final a = await add('failed flush');
      final key = a.content.detail.summary.key;
      final lease = (await store.acquireBookUse(key, cancellation: token()))!;
      await start();
      await idle();
      await lease.release(progressSaved: false);
      await lease.release(progressSaved: true);
      await idle();
      expect((await row(key))['active_bundle'], isNull);
      final noSample = (await store.acquireBookUse(
        key,
        cancellation: token(),
      ))!;
      await noSample.release();
      await idle();
      expect((await row(key))['active_bundle'], isNull);
      final later = (await store.acquireBookUse(key, cancellation: token()))!;
      await save(a);
      await later.release(progressSaved: true);
      await idle();
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
    },
  );
  test(
    'prepared Reader A survives hidden cancellation and upgrades in the same process',
    () async {
      final a = await add('pending Reader A');
      final key = a.content.detail.summary.key;
      final controller = ReaderController(
        repository: LocalReadingRepository(
          local: store,
          online: ForbiddenOnline(),
        ),
        chapter: a.content.chapters.first.key,
        library: library,
      );
      final decoder = GateDecoder()..resume.complete();
      try {
        await controller.load();
        await controller.retryProgress();
        controller.sampleProgress(f.progress(a.content).position, true);
        await start(decoder: decoder, maxBooks: 2);
        await idle();
        expect((await attempts()).single['outcome'], 'preparedWaiting');
        expect(await paths.localImportStaging.list().length, 1);
        store.automaticReparseActivity(resumed: false, cancelPrepare: true);
        await idle();
        expect(await paths.localImportStaging.list().length, 0);
        expect((await attempts()).single['outcome'], 'cancelled');
        store.automaticReparseActivity(resumed: true);
        await idle();
        expect(decoder.calls.length, 2);
        expect((await row(key))['active_bundle'], isNull);
      } finally {
        controller.onDelete();
        await controller.closeReader();
      }
      await idle();
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
      expect(await attempts(), isEmpty);
      expect(
        ok(
          await library.getProgress(key, cancellation: token()),
        )!.position.blockFraction,
        .5,
      );
    },
  );
  test(
    'discarding a pending candidate does not replenish the book budget',
    () async {
      final a = await add('pending exhausted quota');
      final key = a.content.detail.summary.key;
      final lease = (await store.acquireBookUse(key, cancellation: token()))!;
      final decoder = GateDecoder()..resume.complete();
      try {
        await start(decoder: decoder, maxBooks: 1);
        await idle();
        store.automaticReparseActivity(resumed: false, cancelPrepare: true);
        await idle();
        store.automaticReparseActivity(resumed: true);
        await idle();
      } finally {
        await lease.release();
      }
      await idle();
      expect(decoder.calls.length, 1);
      expect((await row(key))['parser_version'], 25);
      expect(await paths.localImportStaging.list().length, 0);
    },
  );
  test(
    'global import discards pending A but does not suppress its retry',
    () async {
      final a = await add('pending import A');
      final key = a.content.detail.summary.key;
      final lease = (await store.acquireBookUse(key, cancellation: token()))!;
      final decoder = GateDecoder()..resume.complete();
      try {
        await start(decoder: decoder, maxBooks: 2);
        await idle();
        ok(
          await store.importBook(
            bytes: Stream.value(utf8.encode('import B')),
            format: LocalBookFormat.txt,
            cancellation: token(),
            parse: (s) => const BookDecoder().decode(
              s,
              format: LocalBookFormat.txt,
              filename: 'B.txt',
              cancellation: token(),
              chooseEncoding: (_) async => TxtEncoding.utf8,
            ),
          ),
        );
        await idle();
        expect(decoder.calls, [key, key]);
      } finally {
        await lease.release();
      }
      await idle();
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
    },
  );
  test(
    'manual reparse of B retains the prepared candidate for Reader A',
    () async {
      final a = await add('pending unrelated A'),
          b = await add('manual unrelated B');
      final key = a.content.detail.summary.key,
          other = b.content.detail.summary.key;
      await db.customStatement(
        'UPDATE local_books SET parser_version=? WHERE digest=?',
        [BookDecoder.parserVersion, other.novelId],
      );
      final lease = (await store.acquireBookUse(key, cancellation: token()))!;
      final decoder = GateDecoder()..resume.complete();
      try {
        await start(decoder: decoder);
        await idle();
        final stage =
            (await paths.localImportStaging.list().toList()).single.path;
        ok(
          await store.reparseBook(
            other,
            chooseEncoding: (_) async => TxtEncoding.utf8,
            cancellation: token(),
          ),
        );
        await idle();
        expect(
          (await paths.localImportStaging.list().toList()).single.path,
          stage,
        );
        expect((await attempts()).single['outcome'], 'preparedWaiting');
        expect(decoder.calls, [key, other]);
      } finally {
        await lease.release();
      }
      await idle();
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
      expect(decoder.calls, [key, other]);
    },
  );
  test(
    'manual reparse cancels and joins prepare before taking maintenance',
    () async {
      final a = await add('manual preemption');
      final key = a.content.detail.summary.key;
      final gate = GateDecoder();
      await start(decoder: gate);
      await gate.entered.future;
      final result = await store.reparseBook(
        key,
        cancellation: token(),
        chooseEncoding: (_) async => TxtEncoding.utf8,
      );
      expect(gate.exited, isTrue);
      ok(result);
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
      expect(await paths.localImportStaging.list().toList(), isEmpty);
      expect(await attempts(), isEmpty);
    },
  );
  test(
    'delete cancels prepare and cannot resurrect the book or its attempt',
    () async {
      final a = await add('delete preemption');
      final key = a.content.detail.summary.key;
      final gate = GateDecoder();
      await start(decoder: gate);
      await gate.entered.future;
      ok(await store.deleteBook(key, cancellation: token()));
      expect(gate.exited, isTrue);
      expect(ok(await store.read(key, cancellation: token())), isNull);
      expect(await attempts(), isEmpty);
      expect(await paths.localImportStaging.list().toList(), isEmpty);
    },
  );
  test('import cancels prepare and preserves both originals', () async {
    final a = await add('before import');
    final gate = GateDecoder();
    await start(decoder: gate);
    await gate.entered.future;
    await add('active user import');
    await idle();
    expect(gate.exited, isTrue);
    expect(
      ok(await store.read(a.content.detail.summary.key, cancellation: token())),
      isNotNull,
    );
    expect(
      (await store.watchBooks().first as Success<List<LocalBookInfo>>)
          .value
          .length,
      2,
    );
  });
  test(
    'new Reader and manual operation wait for an entered publication',
    () async {
      final a = await add('entered publication');
      final key = a.content.detail.summary.key;
      final entered = Completer<void>(), finish = Completer<void>();
      var blocked = false;
      await start(
        checkpoint: (phase) async {
          if (phase == 'beforeRename' && !blocked) {
            blocked = true;
            entered.complete();
            await finish.future;
          }
        },
      );
      await entered.future;
      var readerAcquired = false, manualFinished = false;
      final use = store.acquireBookUse(key, cancellation: token()).then((
        value,
      ) {
        readerAcquired = true;
        return value;
      });
      final manual = store
          .reparseBook(
            key,
            cancellation: token(),
            chooseEncoding: (_) async => TxtEncoding.utf8,
          )
          .then((value) {
            manualFinished = true;
            return value;
          });
      expect(readerAcquired, isFalse);
      expect(manualFinished, isFalse);
      finish.complete();
      final lease = (await use)!;
      await lease.release();
      ok(await manual);
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
    },
  );
  test(
    'history cleared after migration is not resurrected by final SQL CAS',
    () async {
      final a = await add('CAS history');
      final key = a.content.detail.summary.key;
      await save(a);
      await start(
        checkpoint: (phase) async {
          if (phase == 'afterRename') {
            ok(await library.clearHistory(key, cancellation: token()));
          }
        },
      );
      await idle();
      expect(ok(await library.getProgress(key, cancellation: token())), isNull);
      expect((await row(key))['active_bundle'], isNull);
      expect((await row(key))['maintenance'], 0);
    },
  );
  test(
    'migration is outside publication; a Reader can acquire while it is held',
    () async {
      final a = await add('migration outside lock');
      final key = a.content.detail.summary.key;
      final entered = Completer<void>(), finish = Completer<void>();
      var once = false;
      await start(
        checkpoint: (phase) async {
          if (phase == 'migration' && !once) {
            once = true;
            entered.complete();
            await finish.future;
          }
        },
      );
      await entered.future;
      final lease = (await store.acquireBookUse(key, cancellation: token()))!;
      await save(a, fraction: .7);
      finish.complete();
      await idle();
      expect((await row(key))['active_bundle'], isNull);
      await lease.release(progressSaved: true);
      await idle();
      expect(
        ok(
          await library.getProgress(key, cancellation: token()),
        )!.position.blockFraction,
        .7,
      );
    },
  );
  test(
    'count/time budgets remain exhausted across resumed; next launch continues',
    () async {
      await add('first');
      await add('second');
      await add('third');
      await start(maxBooks: 1, clock: BudgetClock.new);
      await idle();
      store.automaticReparseActivity(resumed: false);
      store.automaticReparseActivity(resumed: true);
      await idle();
      expect(
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM local_books WHERE parser_version=?',
                  variables: [Variable(BookDecoder.parserVersion)],
                )
                .getSingle())
            .read<int>('n'),
        1,
      );
      await store.close();
      store = ok(await ManagedLocalBooks.open(paths, db));
      await start();
      await idle();
      expect(
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM local_books WHERE parser_version=25',
                )
                .getSingle())
            .read<int>('n'),
        0,
      );
    },
  );
  test(
    'inactive retains Worker; paused cancels without a failed attempt',
    () async {
      final a = await add('lifecycle');
      final key = a.content.detail.summary.key;
      final gate = GateDecoder();
      await start(decoder: gate);
      await gate.entered.future;
      store.automaticReparseActivity(resumed: false);
      expect(gate.exited, isFalse);
      store.automaticReparseActivity(resumed: true);
      expect(gate.calls.length, 1);
      store.automaticReparseActivity(resumed: false, cancelPrepare: true);
      await idle();
      expect(gate.exited, isTrue);
      expect((await row(key))['active_bundle'], isNull);
      expect((await attempts()).single['failure_count'], 0);
      expect((await attempts()).single['outcome'], 'cancelled');
    },
  );
  test(
    'inactive completion keeps the prepared bundle without a second decode',
    () async {
      final a = await add('inactive completed prepare');
      final key = a.content.detail.summary.key;
      final decoder = GateDecoder();
      await start(decoder: decoder);
      await decoder.entered.future;
      store.automaticReparseActivity(resumed: false);
      decoder.resume.complete();
      await idle();
      expect((await row(key))['active_bundle'], isNull);
      expect((await attempts()).single['outcome'], 'preparedWaiting');
      final stage =
          (await paths.localImportStaging.list().toList()).single.path;
      store.automaticReparseActivity(resumed: true);
      await idle();
      expect(decoder.calls, [key]);
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
      expect(await Directory(stage).exists(), isFalse);
    },
  );
  test(
    'low capacity pauses the scan without spending a book slot; cooldown can retry',
    () async {
      final a = await add('low capacity A', shelf: true);
      await add('low capacity B');
      await add('low capacity C');
      final key = a.content.detail.summary.key;
      var now = DateTime.now();
      var free = 1, probes = 0;
      final decoder = GateDecoder()..resume.complete();
      await start(
        decoder: decoder,
        maxBooks: 1,
        now: () => now,
        freeSpace: (_) async {
          probes++;
          return free;
        },
      );
      await idle();
      expect(probes, 1);
      expect(decoder.calls, isEmpty);
      expect((await attempts()).single['digest'], key.novelId);
      expect((await attempts()).single['outcome'], 'lowStorage');
      expect((await attempts()).single['failure_count'], 0);
      store.automaticReparseActivity(resumed: true);
      await idle();
      expect(probes, 1);
      free = 1 << 31;
      now = now.add(const Duration(hours: 1));
      store.automaticReparseActivity(resumed: true);
      await idle();
      expect(probes, 2);
      expect(decoder.calls, [key]);
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
      expect(await attempts(), isEmpty);
    },
  );
  test(
    'store close joins prepare and startup classifies only unfinished attempts',
    () async {
      final a = await add('shutdown');
      final key = a.content.detail.summary.key;
      final gate = GateDecoder();
      await start(decoder: gate);
      await gate.entered.future;
      await store.close();
      expect(gate.exited, isTrue);
      expect(await paths.localImportStaging.list().toList(), isEmpty);
      await db.customStatement(
        "UPDATE local_reparse_attempts SET outcome='running'",
      );
      store = ok(await ManagedLocalBooks.open(paths, db));
      expect((await attempts()).single['outcome'], 'interrupted');
      await start();
      await idle();
      expect((await row(key))['active_bundle'], isNull);
    },
  );
  for (final shutdown in ['close', 'stop', 'hiddenThenClose']) {
    test(
      'lifecycle callbacks during $shutdown do not race pending cleanup',
      () async {
        final a = await add('shutdown pending $shutdown');
        final key = a.content.detail.summary.key;
        final lease = (await store.acquireBookUse(key, cancellation: token()))!;
        Future<void>? stopping;
        try {
          await start();
          await idle();
          expect((await attempts()).single['outcome'], 'preparedWaiting');
          if (shutdown == 'hiddenThenClose') {
            store.automaticReparseActivity(resumed: false, cancelPrepare: true);
          }
          stopping = shutdown == 'stop'
              ? store.stopAutomaticReparse()
              : store.close();
          store.automaticReparseActivity(resumed: false, cancelPrepare: true);
          store.automaticReparseActivity(resumed: false, cancelPrepare: true);
        } finally {
          await lease.release();
          await stopping;
        }
        await store.close();
        expect(await paths.localImportStaging.list().length, 0);
        expect((await attempts()).single['outcome'], 'cancelled');
        expect((await attempts()).single['failure_count'], 0);
        store = ok(await ManagedLocalBooks.open(paths, db));
        expect(ok(await store.read(key, cancellation: token())), isNotNull);
      },
    );
  }
  test(
    'strict saved TXT chooser succeeds; ambiguous missing encoding is terminal',
    () async {
      final a = await add('中文正文用于编码预览');
      final key = a.content.detail.summary.key;
      final file = File(
        '${paths.localBooks.path}/${key.novelId}/manifest.json',
      );
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      map.remove('txtEncoding');
      final bytes = utf8.encode(jsonEncode(map));
      await file.writeAsBytes(bytes);
      await db.customStatement(
        'UPDATE local_books SET manifest_hash=? WHERE digest=?',
        [sha256.convert(bytes).toString(), key.novelId],
      );
      await start();
      await idle();
      expect((await attempts()).single['outcome'], 'ambiguousEncoding');
      expect((await row(key))['active_bundle'], isNull);
    },
  );
  test(
    'corrupt original is terminal; timeout is ordinary bounded backoff',
    () async {
      final a = await add('bad original');
      final key = a.content.detail.summary.key;
      await File(
        '${paths.localBooks.path}/${key.novelId}/original',
      ).writeAsString('damaged');
      await start();
      await idle();
      expect((await attempts()).single['outcome'], 'originalCorrupt');
      store.automaticReparseActivity(resumed: true);
      await idle();
      expect((await attempts()).single['failure_count'], 0);
    },
  );
  test('timeout and low storage have retry dates and no publication', () async {
    final a = await add('timeout');
    final key = a.content.detail.summary.key;
    final decoder = GateDecoder()
      ..failure = const LocalParseException(LocalParseProblem.timeout)
      ..resume.complete();
    await start(decoder: decoder);
    await idle();
    expect((await attempts()).single['outcome'], 'timeout');
    expect((await attempts()).single['failure_count'], 1);
    expect((await attempts()).single['next_retry_at'], isNotNull);
    await store.close();
    store = ok(await ManagedLocalBooks.open(paths, db));
    await db.customStatement('DELETE FROM local_reparse_attempts');
    await start(freeSpace: (_) async => 1);
    await idle();
    expect((await attempts()).single['outcome'], 'lowStorage');
    expect((await row(key))['active_bundle'], isNull);
  });
  for (final phase in [
    'beforeRename',
    'afterRename',
    'transaction',
    'afterCommit',
    'cleanup',
  ]) {
    test(
      'fault at $phase preserves a complete durable version on reopen',
      () async {
        final a = await add('fault $phase', epub: true);
        final key = a.content.detail.summary.key;
        await save(a);
        await start(
          checkpoint: (at) async {
            if (at == phase) throw StateError('injected');
          },
        );
        await idle();
        final before = await row(key);
        final committed = phase == 'afterCommit' || phase == 'cleanup';
        expect(
          before['parser_version'],
          committed ? BookDecoder.parserVersion : 25,
        );
        expect(before['maintenance'], 0);
        await store.close();
        store = ok(await ManagedLocalBooks.open(paths, db));
        expect(ok(await store.read(key, cancellation: token())), isNotNull);
        expect(
          ok(
            await store.readMedia(
              a.content.chapters.first.blocks
                  .whereType<ImageBlock>()
                  .first
                  .media,
              cancellation: token(),
            ),
          ),
          tinyPng,
        );
        expect(
          ok(await library.getProgress(key, cancellation: token()))!.lastReadAt,
          DateTime.utc(2025),
        );
      },
    );
  }
  test(
    'Reader closing barrier retains lease through an actual failed final write',
    () async {
      final a = await add('controller closing');
      final key = a.content.detail.summary.key;
      final repo = LocalReadingRepository(
        local: store,
        online: ForbiddenOnline(),
      );
      final controller = ReaderController(
        repository: repo,
        chapter: a.content.chapters.first.key,
        library: library,
      );
      await controller.load();
      await controller.retryProgress();
      controller.sampleProgress(f.progress(a.content).position, true);
      await db.customStatement(
        "CREATE TRIGGER fail_save BEFORE INSERT ON reading_progress BEGIN SELECT RAISE(ABORT,'failure'); END",
      );
      controller.onDelete();
      await controller.closeReader();
      await start();
      await idle();
      expect((await row(key))['active_bundle'], isNull);
      await db.customStatement('DROP TRIGGER fail_save');
      final clean = ReaderController(
        repository: repo,
        chapter: a.content.chapters.first.key,
        library: library,
      );
      await clean.load();
      await clean.retryProgress();
      clean.sampleProgress(f.progress(a.content).position, true);
      clean.onDelete();
      await clean.closeReader();
      await idle();
      expect((await row(key))['parser_version'], BookDecoder.parserVersion);
    },
  );
}
