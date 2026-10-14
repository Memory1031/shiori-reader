import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/record_codec.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/library_controller.dart';
import '../../widgets/bookshelf_test.dart' show RemovalCache;
import 'migrations/schema_upgrade_test.dart' as legacy;

NovelKey book(String id) => NovelKey(sourceId: SourceId('online'), novelId: id);
CancellationToken token() => CancellationSource().token;
T ok<T>(Result<T> result) => (result as Success<T>).value;
Catalog catalog(NovelKey key, {int count = 2}) => Catalog(
  novelKey: key,
  volumes: [
    Volume(
      groupId: 'v',
      chapters: List.generate(
        count,
        (i) => Chapter(
          key: ChapterKey(novelKey: key, chapterId: '$i'),
          title: 'Chapter $i',
          ordinal: i,
          volumeGroupId: 'v',
        ),
      ),
    ),
  ],
);
LoadResult<Catalog> observation(NovelKey key, {int count = 2, int day = 1}) =>
    LoadResult(
      value: catalog(key, count: count),
      origin: LoadOrigin.remote,
      fetchedAt: DateTime.utc(2026, 1, day),
    );
ReadingProgress progress(NovelKey key) {
  final c = catalog(key);
  return ReadingProgress(
    snapshot: NovelSummary(key: key, title: 'Book ${key.novelId}'),
    chapterKey: c.flatChapters.first.key,
    chapterOrdinalSnapshot: 0,
    catalogRevision: c.revision,
    position: ReaderPosition(
      contentRevision: 'content',
      blockKey: 'block',
      blockIndex: 0,
      blockFraction: .4,
      chapterFraction: .4,
    ),
    bookProgress: BookProgressMetrics.online(
      c,
    ).at(c.flatChapters.first.key, .4),
    completed: false,
    lastReadAt: DateTime.utc(2026),
  );
}

Future<int> start(LocalLibraryRepository library, NovelKey key) async =>
    ok(await library.beginProgressSession(key, cancellation: token()));
Future<Result<bool>> save(
  LocalLibraryRepository library,
  NovelKey key,
  int generation, {
  int sequence = 0,
}) => library.saveProgress(
  progress(key),
  stamp: ProgressWriteStamp(generation: generation, sequence: sequence),
  catalog: observation(key),
  cancellation: token(),
);
Future<List<Map<String, dynamic>>> rows(
  UserDatabase db,
  String table,
  NovelKey key,
) async =>
    (await db
            .customSelect(
              "SELECT * FROM $table WHERE source_id='${key.sourceId.value}' AND novel_id='${key.novelId}'",
            )
            .get())
        .map((r) => r.data)
        .toList();

class UnusedLocal implements LocalBookStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected local call');
}

class DelayedCatalog implements NovelRepository {
  final response = Completer<Result<LoadResult<Catalog>>>();
  final updates = StreamController<Result<LoadResult<Catalog>>>.broadcast(
    sync: true,
  );
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => response.future;
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      updates.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected online call');
}

class FailedOwnershipMigration extends UserDatabase {
  FailedOwnershipMigration(super.executor);
  @override
  Future<void> repairOnlineOwnership() async {
    await super.repairOnlineOwnership();
    throw StateError('Injected failure after ownership repair');
  }
}

void main() {
  late UserDatabase db;
  late LocalLibraryRepository library;
  final a = book('a'), b = book('b');
  setUp(() {
    db = UserDatabase(NativeDatabase.memory());
    library = LocalLibraryRepository(db, now: () => DateTime.utc(2026, 2));
  });
  tearDown(() async {
    await db.close();
  });

  test(
    'browsing and session preparation create no owned progress or catalog',
    () async {
      ok(await library.reconcileCatalog(observation(a)));
      await start(library, a);
      for (final table in [
        'bookshelf',
        'reading_progress',
        'progress_catalogs',
        'prefetch_choices',
      ]) {
        expect(await rows(db, table, a), isEmpty);
      }
      expect(await rows(db, 'progress_sessions', a), hasLength(1));
    },
  );
  test(
    'first saved position owns shelf and catalog atomically; addedAt stays unchanged',
    () async {
      final generation = await start(library, a);
      expect(ok(await save(library, a, generation)), isTrue);
      expect(await rows(db, 'bookshelf', a), hasLength(1));
      expect(
        ok(await library.getProgress(a, cancellation: token())),
        progress(a),
      );
      expect(await rows(db, 'progress_catalogs', a), hasLength(1));
      final original = (await rows(db, 'bookshelf', a)).single['added_at'];
      expect(ok(await save(library, a, generation, sequence: 1)), isTrue);
      expect((await rows(db, 'bookshelf', a)).single['added_at'], original);
      ok(
        await library.putBookshelf(
          BookshelfEntry(
            snapshot: progress(b).snapshot,
            addedAt: DateTime.utc(2020),
          ),
          cancellation: token(),
        ),
      );
      expect(ok(await save(library, b, await start(library, b))), isTrue);
      expect(
        (await rows(db, 'bookshelf', b)).single['added_at'],
        DateTime.utc(2020).millisecondsSinceEpoch,
      );
    },
  );
  for (final table in ['bookshelf', 'reading_progress', 'progress_catalogs']) {
    test(
      'first $table write failure leaves no partial ownership and is retryable',
      () async {
        final generation = await start(library, a);
        await db.customStatement(
          "CREATE TRIGGER fail_write BEFORE INSERT ON $table BEGIN SELECT RAISE(ABORT, 'injected'); END",
        );
        expect(await save(library, a, generation), isA<Failure<bool>>());
        for (final t in [
          'bookshelf',
          'reading_progress',
          'progress_catalogs',
        ]) {
          expect(await rows(db, t, a), isEmpty);
        }
        expect((await rows(db, 'progress_sessions', a)).single['sequence'], -1);
        await db.customStatement('DROP TRIGGER fail_write');
        expect(ok(await save(library, a, generation)), isTrue);
      },
    );
  }
  test(
    'removal clears only the target and tombstones old writers, while fresh readers may rejoin',
    () async {
      final old = await start(library, a);
      ok(await save(library, a, old));
      ok(await save(library, b, await start(library, b)));
      await db.customStatement(
        "INSERT INTO prefetch_choices VALUES('online','a','0','1'),('online','b','0','1')",
      );
      final beforeB = {
        for (final table in [
          'bookshelf',
          'reading_progress',
          'progress_catalogs',
          'prefetch_choices',
          'progress_sessions',
        ])
          table: await rows(db, table, b),
      };
      final removed = library.removedBooks.first;
      ok(await library.removeOnlineBook(a, cancellation: token()));
      expect(await removed, a);
      for (final table in [
        'bookshelf',
        'reading_progress',
        'progress_catalogs',
        'prefetch_choices',
      ]) {
        expect(await rows(db, table, a), isEmpty);
      }
      expect(ok(await save(library, a, old, sequence: 99)), isFalse);
      expect(
        (await rows(db, 'progress_sessions', a)).single['generation'],
        greaterThan(old),
      );
      for (final table in beforeB.keys) {
        expect(await rows(db, table, b), beforeB[table]);
      }
      final fresh = await start(library, a);
      expect(ok(await save(library, a, fresh)), isTrue);
      expect(ok(await save(library, a, old, sequence: 100)), isFalse);
    },
  );
  for (final table in [
    'bookshelf',
    'reading_progress',
    'progress_catalogs',
    'prefetch_choices',
    'progress_sessions',
  ]) {
    test(
      '$table removal failure preserves the complete user state after cache cleared',
      () async {
        ok(await save(library, a, await start(library, a)));
        await db.customStatement(
          "INSERT INTO prefetch_choices VALUES('online','a','0','1')",
        );
        final before = {
          for (final t in [
            'bookshelf',
            'reading_progress',
            'progress_catalogs',
            'prefetch_choices',
            'progress_sessions',
          ])
            t: await rows(db, t, a),
        };
        final action = table == 'progress_sessions' ? 'UPDATE' : 'DELETE';
        await db.customStatement(
          "CREATE TRIGGER fail_remove BEFORE $action ON $table BEGIN SELECT RAISE(ABORT, 'injected'); END",
        );
        final cache = RemovalCache();
        final controller = LibraryController(library, cache: cache)..onStart();
        final events = <NovelKey>[];
        final subscription = library.removedBooks.listen(events.add);
        expect(await controller.remove(a), isFalse);
        expect(cache.cleared, [a]);
        expect(events, isEmpty);
        for (final t in before.keys) {
          expect(await rows(db, t, a), before[t]);
        }
        await db.customStatement('DROP TRIGGER fail_remove');
        expect(await controller.remove(a), isTrue);
        expect(events, [a]);
        controller.onDelete();
        await controller.resourcesReleased;
        controller.dispose();
        await subscription.cancel();
      },
    );
  }
  test('cache failure prevents any user-data removal', () async {
    ok(await save(library, a, await start(library, a)));
    final before = <String, List<Map<String, Object?>>>{};
    for (final table in [
      'bookshelf',
      'reading_progress',
      'progress_catalogs',
      'progress_sessions',
    ]) {
      before[table] = await rows(db, table, a);
    }
    final cache = RemovalCache();
    cache.pending = Completer<Result<void>>()
      ..complete(
        Failure(
          AppFailure(
            kind: FailureKind.cache,
            operation: Operation.libraryWrite,
          ),
        ),
      );
    final controller = LibraryController(library, cache: cache)..onStart();
    expect(await controller.remove(a), isFalse);
    for (final table in before.keys) {
      expect(await rows(db, table, a), before[table]);
    }
    controller.onDelete();
    await controller.resourcesReleased;
    controller.dispose();
  });

  for (final order in ['save-first', 'remove-first']) {
    test('concurrent $order never leaves progress without its shelf', () async {
      final generation = await start(library, a);
      final Future<Result<bool>> writing;
      final Future<Result<BookshelfEntry?>> removing;
      if (order == 'save-first') {
        writing = save(library, a, generation);
        removing = library.removeOnlineBook(a, cancellation: token());
      } else {
        removing = library.removeOnlineBook(a, cancellation: token());
        writing = save(library, a, generation);
      }
      await Future.wait([writing, removing]);
      for (final table in [
        'bookshelf',
        'reading_progress',
        'progress_catalogs',
      ]) {
        expect(await rows(db, table, a), isEmpty);
      }
    });
  }
  for (final stream in [false, true]) {
    test(
      'late ${stream ? 'subscription' : 'load'} cannot restore catalog after remove and new ownership',
      () async {
        ok(await save(library, a, await start(library, a)));
        final online = DelayedCatalog();
        final reader = LocalReadingRepository(
          local: UnusedLocal(),
          online: online,
          bindOnlineCatalog: library.bindCatalog,
        );
        final response = stream
            ? reader.catalogUpdates(a).first
            : reader.loadCatalog(
                a,
                mode: ReadMode.refresh,
                cancellation: token(),
              );
        ok(await library.removeOnlineBook(a, cancellation: token()));
        ok(await save(library, a, await start(library, a)));
        final newer = Success(observation(a, count: 10, day: 10));
        if (stream) {
          online.updates.add(newer);
        } else {
          online.response.complete(newer);
        }
        expect(await response, isA<Failure<LoadResult<Catalog>>>());
        final persisted = RecordCodec.readCatalog(
          (await rows(db, 'progress_catalogs', a)).single['catalog_json']
              as String,
        );
        expect(persisted.revision, catalog(a).revision);
        await online.updates.close();
      },
    );
  }
  test(
    'cancelled owned catalog response does not replace its durable basis',
    () async {
      ok(await save(library, a, await start(library, a)));
      final request = CancellationSource();
      final resolve = await library.bindCatalog(a, request.token);
      request.cancel();
      expect(
        await resolve(Success(observation(a, count: 10))),
        isA<Failure<LoadResult<Catalog>>>(),
      );
      expect(
        RecordCodec.readCatalog(
          (await rows(db, 'progress_catalogs', a)).single['catalog_json']
              as String,
        ).revision,
        catalog(a).revision,
      );
    },
  );
  for (final fail in [false, true]) {
    test(
      'v7 ownership repair preserves anchors and times; rollback=$fail; repeated open is idempotent',
      () async {
        await db.close();
        final dir = await Directory.systemTemp.createTemp('online-ownership-');
        addTearDown(() async {
          // Test-local cleanup runs before the outer database teardown.
          await db.close();
          await dir.delete(recursive: true);
        });
        final file = File('${dir.path}/users.sqlite');
        legacy.seed(file, 'user', 7);
        final raw = sql.sqlite3.open(file.path);
        final data = progress(a);
        raw.execute(
          "INSERT INTO reading_progress SELECT 'online','a',chapter_id,?,chapter_ordinal,catalog_revision,content_revision,block_key,block_index,block_fraction,chapter_fraction,?,?,pixel_offset,layout_key,position_version,last_read_at,updated_at FROM reading_progress WHERE source_id='s' AND novel_id='n'",
          [RecordCodec.summary(data.snapshot), null, 0],
        );
        raw.execute('INSERT INTO progress_catalogs VALUES(?,?,?,?,?)', [
          'online',
          'a',
          RecordCodec.catalog(catalog(a)),
          1,
          'remote',
        ]);
        raw.execute('INSERT INTO progress_catalogs VALUES(?,?,?,?,?)', [
          'online',
          'browse',
          RecordCodec.catalog(catalog(book('browse'))),
          1,
          'remote',
        ]);
        raw.execute(
          "INSERT INTO prefetch_choices VALUES('online','browse','0','1'),('online','a','0','1')",
        );
        raw.execute(
          "INSERT INTO progress_sessions(source_id,novel_id,generation,sequence) VALUES('online','browse',41,9)",
        );
        final oldProgress = raw
            .select(
              "SELECT * FROM reading_progress WHERE source_id='online' AND novel_id='a'",
            )
            .single;
        final original = Map<String, Object?>.from(oldProgress);
        raw.close();
        final before = legacy.rows(file);
        if (fail) {
          final failing = FailedOwnershipMigration(NativeDatabase(file));
          await expectLater(
            failing.customSelect('SELECT 1').get(),
            throwsA(anything),
          );
          await failing.close();
          expect(legacy.rows(file), before);
          final check = sql.sqlite3.open(file.path);
          expect(check.userVersion, 7);
          check.close();
        }
        db = UserDatabase(NativeDatabase(file));
        library = LocalLibraryRepository(db);
        expect(await rows(db, 'reading_progress', a), [original]);
        expect(
          (await rows(db, 'bookshelf', a)).single['added_at'],
          original['last_read_at'],
        );
        expect(
          (await db
                  .customSelect(
                    "SELECT added_at FROM bookshelf WHERE source_id='s' AND novel_id='n'",
                  )
                  .getSingle())
              .read<int>('added_at'),
          123,
        );
        expect(await rows(db, 'bookshelf', book('browse')), isEmpty);
        expect(await rows(db, 'progress_catalogs', book('browse')), isEmpty);
        expect(await rows(db, 'prefetch_choices', book('browse')), isEmpty);
        expect(
          (await rows(
            db,
            'progress_sessions',
            book('browse'),
          )).single['generation'],
          41,
        );
        expect(await rows(db, 'progress_catalogs', a), hasLength(1));
        expect(await rows(db, 'prefetch_choices', a), hasLength(1));
        final after = legacy.rows(file);
        await db.close();
        db = UserDatabase(NativeDatabase(file));
        await db.customSelect('SELECT 1').get();
        expect(legacy.rows(file), after);
      },
    );
  }
}
