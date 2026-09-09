import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/data/local/record_codec.dart';
import 'package:shiori/data/repositories/library_repository.dart';

void seed(File file, String kind, int version) {
  final snapshot =
      jsonDecode(
            File(
              'lib/data/local/database/schemas/$kind/drift_schema_v$version.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final db = sql.sqlite3.open(file.path);
  try {
    for (final entity in snapshot['fixed_sql'] as List) {
      db.execute(
        (entity['sql'] as List).singleWhere(
              (s) => s['dialect'] == 'sqlite',
            )['sql']
            as String,
      );
    }
    db.execute('PRAGMA user_version=$version');
    if (kind == 'user') {
      db.execute(
        "INSERT INTO bookshelf VALUES('s','n','original-summary',123,456)",
      );
      db.execute("INSERT INTO progress_sessions VALUES('s','n',3,8)");
      db.execute(
        "INSERT INTO reading_progress VALUES('s','n','chapter','original-summary',2,'catalog','content','block',17,.25,.75,0,22.5,'layout',1,123,456)",
      );
      final summary = RecordCodec.summary(
        NovelSummary(
          key: NovelKey(sourceId: SourceId('s'), novelId: 'n'),
          title: 'Preserved book',
          authors: ['Author'],
        ),
      );
      db.execute('UPDATE bookshelf SET summary_json=?', [summary]);
      db.execute('UPDATE reading_progress SET summary_json=?', [summary]);
      if (version >= 2) {
        db.execute('INSERT INTO prefetch_settings VALUES(1,0,1)');
      }
    } else {
      db.execute(
        "INSERT INTO chapter_cache VALUES('s','n','c','old-payload',1,1,123,NULL,123,11)",
      );
    }
  } finally {
    db.close();
  }
}

Map<String, Object?> rows(File file) {
  final db = sql.sqlite3.open(file.path);
  try {
    final names = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    return {
      for (final row in names)
        row['name'] as String: db
            .select('SELECT * FROM "${row['name']}"')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
    };
  } finally {
    db.close();
  }
}

class FaultMigrator extends Migrator {
  FaultMigrator(super.database, this.target);
  final String target;
  @override
  Future<void> createTable(TableInfo table) async {
    if (table.actualTableName == target) {
      throw StateError('DB003 injected DDL failure');
    }
    await super.createTable(table);
  }
}

class FaultUsers extends UserDatabase {
  FaultUsers(super.executor);
  @override
  Migrator createMigrator() => FaultMigrator(this, 'local_books');
}

class FaultV4 extends UserDatabase {
  FaultV4(super.executor);
  @override
  Migrator createMigrator() => FaultMigrator(this, 'local_chapter_revisions');
}

class FaultCache extends CacheDatabase {
  FaultCache(super.executor);
  @override
  Migrator createMigrator() => FaultMigrator(this, 'image_owners');
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shiori-migration-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  for (final version in [1, 2, 3]) {
    test(
      'retained user v$version snapshot upgrades and preserves every old field',
      () async {
        final file = File('${root.path}/users.sqlite');
        seed(file, 'user', version);
        final before = rows(file);
        final db = UserDatabase(NativeDatabase(file));
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          4,
        );
        final library = LocalLibraryRepository(db);
        final shelf =
            (await library.watchBookshelf().first
                    as Success<List<BookshelfEntry>>)
                .value;
        expect(shelf.single.snapshot.title, 'Preserved book');
        final progress =
            (await library.getProgress(
                      shelf.single.snapshot.key,
                      cancellation: CancellationSource().token,
                    )
                    as Success<ReadingProgress?>)
                .value!;
        expect(progress.position.blockIndex, 17);
        expect(progress.position.blockFraction, .25);
        expect(progress.snapshot, shelf.single.snapshot);
        await db.close();
        final after = rows(file);
        for (final name in before.keys) {
          expect(after[name], before[name], reason: name);
        }
        expect(after['local_books'], isEmpty);
      },
    );
  }
  test('v3 ALTER operations roll back when v4 table creation fails', () async {
    final file = File('${root.path}/users.sqlite');
    seed(file, 'user', 3);
    final before = rows(file);
    final db = FaultV4(NativeDatabase(file));
    await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
    await db.close();
    expect(rows(file), before);
    final raw = sql.sqlite3.open(file.path);
    expect(raw.userVersion, 3);
    raw.close();
    final retry = UserDatabase(NativeDatabase(file));
    await retry.customSelect('SELECT 1').get();
    await retry.close();
  });
  test('v3 imported row fields survive v4 additions', () async {
    final file = File('${root.path}/users.sqlite');
    seed(file, 'user', 3);
    final raw = sql.sqlite3.open(file.path);
    raw.execute('INSERT INTO local_books VALUES(?,?,?,?,?)', [
      'a' * 64,
      'txt',
      'Kept',
      123,
      'b' * 64,
    ]);
    raw.close();
    final db = UserDatabase(NativeDatabase(file));
    final row = await db.customSelect('SELECT * FROM local_books').getSingle();
    expect(row.read<String>('title'), 'Kept');
    expect(row.read<int>('imported_at'), 123);
    expect(row.readNullable<String>('active_bundle'), isNull);
    expect(row.read<int>('parser_version'), 1);
    expect(row.read<int>('maintenance'), 0);
    await db.close();
  });
  test('retained cache v1 upgrades without replacing old payloads', () async {
    final file = File('${root.path}/cache.sqlite');
    seed(file, 'cache', 1);
    final before = rows(file);
    final db = CacheDatabase(NativeDatabase(file));
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .single,
      2,
    );
    await db.close();
    final after = rows(file);
    for (final name in before.keys) {
      expect(after[name], before[name]);
    }
    expect(after['image_cache'], isEmpty);
  });
  for (final kind in ['user', 'cache']) {
    test(
      '$kind migration failure rolls back tables and schema version',
      () async {
        final file = File('${root.path}/$kind.sqlite');
        seed(file, kind, 1);
        final before = rows(file);
        final db = kind == 'user'
            ? FaultUsers(NativeDatabase(file))
            : FaultCache(NativeDatabase(file));
        await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
        await db.close();
        expect(rows(file), before);
        final check = sql.sqlite3.open(file.path);
        expect(check.userVersion, 1);
        check.close();
        final retry = kind == 'user'
            ? UserDatabase(NativeDatabase(file))
            : CacheDatabase(NativeDatabase(file));
        await retry.customSelect('SELECT 1').get();
        await retry.close();
        for (final name in before.keys) {
          expect(rows(file)[name], before[name]);
        }
      },
    );
  }
  for (final kind in ['user', 'cache']) {
    test(
      '$kind corrupt file and owned book bytes survive failed opening',
      () async {
        final paths = AppPaths(
          support: root,
          temporary: root,
          environment: StorageEnvironment.development,
        );
        await paths.prepare();
        final file = kind == 'user' ? paths.userDatabase : paths.cacheDatabase;
        final bytes = utf8.encode('DB003 deliberately invalid SQLite');
        await file.writeAsBytes(bytes);
        final book = File('${paths.localBooks.path}/owned/original');
        await book.parent.create(recursive: true);
        await book.writeAsString('keep imported original');
        final result = await LocalDatabases.open(paths);
        expect(result, isA<Failure<LocalDatabases>>());
        expect(await file.readAsBytes(), bytes);
        expect(await book.readAsString(), 'keep imported original');
      },
    );
  }
}
