import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/cache/cache_policy.dart';
import 'package:shiori/data/cache/local_cache_management.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/data/media/persistent_image_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';

void main() {
  test(
    'future cache codec is not offered offline; cache clear preserves user data and files',
    () async {
      final root = await Directory.systemTemp.createTemp('shiori-codec-');
      final paths = AppPaths(
        support: root,
        temporary: root,
        environment: StorageEnvironment.development,
      );
      final db =
          (await LocalDatabases.open(paths) as Success<LocalDatabases>).value;
      final owner = CacheCoordinator();
      final images = PersistentImageRepository(
        network: MemoryImageRepository(
          resolve: (_) => throw StateError('No network in DB003'),
        ),
        db: db.cache,
        paths: paths,
        coordinator: owner,
      );
      try {
        await db.users.customStatement(
          "INSERT INTO bookshelf VALUES('s','n','keep',1,2)",
        );
        await db.users.customStatement(
          "INSERT INTO progress_sessions VALUES('s','n',4,7)",
        );
        await db.users.customStatement(
          'INSERT INTO prefetch_settings VALUES(1,1,0)',
        );
        final original = File('${paths.localBooks.path}/sentinel/original');
        await original.parent.create(recursive: true);
        await original.writeAsString('owned book bytes');
        final store = NovelRecordStore(db.cache);
        final chapter = const FixtureData().content(
          FixtureScenario.shortChapter,
        );
        final token = CancellationSource().token;
        await store.writeChapter(
          chapter,
          fetchedAt: fixtureEpoch,
          parserVersion: 1,
          cancellation: token,
        );
        final cache = LocalCacheManagement(db.cache, owner, images);
        expect(
          (await cache.inspect() as Success<CacheOverview>).value.chapters,
          hasLength(1),
        );
        await db.cache.customStatement(
          'UPDATE chapter_cache SET codec_version=999',
        );
        expect(
          await store.readChapter(chapter.key, cancellation: token),
          isA<Failure>(),
        );
        expect(
          (await cache.inspect() as Success<CacheOverview>).value.chapters,
          isEmpty,
        );
        // Future envelope versions also remain non-readable until cache clearing.
        await db.cache.customStatement(
          'UPDATE chapter_cache SET codec_version=1, payload=?',
          ['{"version":999,"kind":"chapter","payload":{}}'],
        );
        expect(
          (await cache.inspect() as Success<CacheOverview>).value.chapters,
          isEmpty,
        );
        expect(await cache.clear(), isA<Success<void>>());
        expect(
          await db.cache.customSelect('SELECT * FROM chapter_cache').get(),
          isEmpty,
        );
        expect(
          (await db.users
                  .customSelect('SELECT summary_json FROM bookshelf')
                  .getSingle())
              .read<String>('summary_json'),
          'keep',
        );
        expect(
          (await db.users
                  .customSelect('SELECT sequence FROM progress_sessions')
                  .getSingle())
              .read<int>('sequence'),
          7,
        );
        expect(
          (await db.users
                  .customSelect('SELECT next_enabled FROM prefetch_settings')
                  .getSingle())
              .read<int>('next_enabled'),
          0,
        );
        expect(await original.readAsString(), 'owned book bytes');
      } finally {
        await images.close();
        await owner.close();
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );
}
