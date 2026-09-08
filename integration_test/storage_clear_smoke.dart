// TEST-002: isolated temporary storage, no production data or live Source.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shiori/data/cache/cache_policy.dart';
import 'package:shiori/data/cache/local_cache_management.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/data/media/persistent_image_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = await Directory(
    (await getTemporaryDirectory()).path,
  ).createTemp('test002-');
  final report = <String, Object?>{};
  LocalDatabases? db;
  final owner = CacheCoordinator();
  PersistentImageRepository? images;
  void check(bool condition, String step) {
    if (!condition) throw StateError(step);
    report[step] = 'PASS';
  }

  try {
    final paths = AppPaths(
      support: root,
      temporary: root,
      environment: StorageEnvironment.development,
    );
    db = (await LocalDatabases.open(paths) as Success<LocalDatabases>).value;
    await db.users.customStatement(
      "INSERT INTO bookshelf VALUES('s','n','retained',1,2)",
    );
    await db.users.customStatement(
      "INSERT INTO progress_sessions VALUES('s','n',4,7)",
    );
    final original = File('${paths.localBooks.path}/sentinel/original');
    await original.parent.create(recursive: true);
    await original.writeAsString('owned book', flush: true);
    final chapter = const FixtureData().content(FixtureScenario.shortChapter);
    final token = CancellationSource().token;
    check(
      await NovelRecordStore(db.cache).writeChapter(
            chapter,
            fetchedAt: fixtureEpoch,
            parserVersion: 1,
            cancellation: token,
          )
          is Success,
      'seed',
    );
    await db.close();
    db = null;
    db = (await LocalDatabases.open(paths) as Success<LocalDatabases>).value;
    check(
      (await NovelRecordStore(
                    db.cache,
                  ).readChapter(chapter.key, cancellation: token)
                  as Success)
              .value !=
          null,
      'reopen',
    );
    images = PersistentImageRepository(
      network: MemoryImageRepository(
        resolve: (_) => throw StateError('Unexpected network'),
      ),
      db: db.cache,
      paths: paths,
      coordinator: owner,
    );
    final cache = LocalCacheManagement(db.cache, owner, images);
    check(
      (await cache.inspect() as Success<CacheOverview>).value.chapters.length ==
          1,
      'offline_listing',
    );
    check(await cache.clear() is Success, 'clear');
    await images.close();
    images = null;
    await db.close();
    db = null;
    db = (await LocalDatabases.open(paths) as Success<LocalDatabases>).value;
    check(
      (await db.cache.customSelect('SELECT * FROM chapter_cache').get())
          .isEmpty,
      'clear_survives_reopen',
    );
    check(
      (await db.users
                  .customSelect('SELECT summary_json FROM bookshelf')
                  .getSingle())
              .read<String>('summary_json') ==
          'retained',
      'bookshelf_preserved',
    );
    check(
      (await db.users
                  .customSelect('SELECT sequence FROM progress_sessions')
                  .getSingle())
              .read<int>('sequence') ==
          7,
      'progress_preserved',
    );
    check(await original.readAsString() == 'owned book', 'original_preserved');
    report['status'] = 'PASS';
  } catch (error) {
    report['status'] = 'FAIL';
    report['error'] = error.toString();
  } finally {
    await images?.close();
    await owner.close();
    await db?.close();
    await root.delete(recursive: true);
  }
  await File(
    '${(await getApplicationSupportDirectory()).path}/test002-report.json',
  ).writeAsString(jsonEncode(report));
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text('TEST002 ${report['status']}'))),
    ),
  );
}
