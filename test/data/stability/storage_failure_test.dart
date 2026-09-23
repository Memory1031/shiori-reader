import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/repositories/novel_repository.dart';
import 'package:shiori/data/sources/source_registry.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/app_logger.dart';
import '../repositories/novel_repository_test.dart' show Source;

void main() {
  test(
    'SQLITE_FULL preserves old content and user rows; explicit retry recovers',
    () async {
      final root = await Directory.systemTemp.createTemp('shiori-full-');
      final paths = AppPaths(
        support: root,
        temporary: root,
        environment: StorageEnvironment.development,
      );
      final db =
          (await LocalDatabases.open(paths) as Success<LocalDatabases>).value;
      final source = Source();
      final logger = AppLogger();
      final repo = createNovelRepository(
        sources: SourceRegistry([source]),
        cache: db.cache,
        logger: logger,
      );
      final records = NovelRecordStore(db.cache);
      final token = CancellationSource().token;
      final key = ChapterKey(novelKey: source.novel, chapterId: 'chapter');
      try {
        await db.users.customStatement(
          "INSERT INTO bookshelf VALUES('s','n','retained',1,2)",
        );
        expect(
          await records.writeChapter(
            ChapterContent(
              key: key,
              title: 'old',
              blocks: [ParagraphBlock(text: 'old')],
            ),
            fetchedAt: DateTime.utc(2026),
            parserVersion: 1,
            cancellation: token,
          ),
          isA<Success>(),
        );
        final pages =
            (await db.cache.customSelect('PRAGMA page_count').getSingle())
                .data
                .values
                .single;
        await db.cache.customSelect('PRAGMA max_page_count=$pages').getSingle();
        // Force an actual SQLite allocation failure without filling the host disk.
        await expectLater(
          db.cache.customStatement(
            'CREATE TABLE full_probe AS SELECT zeroblob(1048576) AS bytes',
          ),
          throwsA(
            predicate<Object>(
              (e) => e.toString().contains('database or disk is full'),
            ),
          ),
        );
        final large = _LargeSource(source.id);
        final fullRepo = createNovelRepository(
          sources: SourceRegistry([large]),
          cache: db.cache,
          logger: logger,
        );
        try {
          final loaded = await fullRepo.loadChapter(
            key,
            mode: ReadMode.refresh,
            cancellation: token,
          );
          expect(loaded, isA<Success<LoadResult<ChapterContent>>>());
          expect(large.chapterCalls, 1);
          expect(logger.events.last.fields['context'], 'cacheWriteFailed');
          final offline =
              (await repo.loadChapter(
                        key,
                        mode: ReadMode.cacheOnly,
                        cancellation: token,
                      )
                      as Success<LoadResult<ChapterContent>>)
                  .value;
          expect(offline.value.title, 'old');
          expect(
            (await db.users
                    .customSelect('SELECT summary_json FROM bookshelf')
                    .getSingle())
                .read<String>('summary_json'),
            'retained',
          );
          await db.cache
              .customSelect('PRAGMA max_page_count=10000')
              .getSingle();
          expect(
            await fullRepo.loadChapter(
              key,
              mode: ReadMode.refresh,
              cancellation: token,
            ),
            isA<Success>(),
          );
          expect(large.chapterCalls, 2);
          expect(
            (await records.readChapter(key, cancellation: token)
                    as Success<StoredRecord<ChapterContent>?>)
                .value!
                .value
                .title,
            'large',
          );
        } finally {
          await fullRepo.close();
        }
      } finally {
        await repo.close();
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'parser change keeps offline data stale and refreshes once to current version',
    () async {
      final root = await Directory.systemTemp.createTemp('shiori-parser-');
      final paths = AppPaths(
        support: root,
        temporary: root,
        environment: StorageEnvironment.development,
      );
      final db =
          (await LocalDatabases.open(paths) as Success<LocalDatabases>).value;
      final source = Source();
      final repo = createNovelRepository(
        sources: SourceRegistry([source]),
        cache: db.cache,
        now: () => DateTime.utc(2026),
      );
      final records = NovelRecordStore(db.cache);
      final token = CancellationSource().token;
      final key = ChapterKey(novelKey: source.novel, chapterId: 'chapter');
      try {
        expect(
          await records.writeChapter(
            ChapterContent(
              key: key,
              title: 'old',
              blocks: [ParagraphBlock(text: 'old')],
            ),
            fetchedAt: DateTime.utc(2026),
            parserVersion: 1,
            cancellation: token,
          ),
          isA<Success>(),
        );
        final offline =
            (await repo.loadChapter(
                      key,
                      mode: ReadMode.cacheOnly,
                      cancellation: token,
                    )
                    as Success<LoadResult<ChapterContent>>)
                .value;
        expect(offline.isStale, true);
        expect(source.chapterCalls, 0);
        final update = repo.chapterUpdates(key).first;
        final cached =
            (await repo.loadChapter(
                      key,
                      mode: ReadMode.cacheFirst,
                      cancellation: token,
                    )
                    as Success<LoadResult<ChapterContent>>)
                .value;
        expect(cached.value.title, 'old');
        expect(cached.isStale, true);
        expect(
          (await update.timeout(const Duration(seconds: 5))
                  as Success<LoadResult<ChapterContent>>)
              .value
              .origin,
          LoadOrigin.remote,
        );
        expect(source.chapterCalls, 1);
        expect(
          (await records.readChapter(key, cancellation: token)
                  as Success<StoredRecord<ChapterContent>?>)
              .value!
              .parserVersion,
          2,
        );
      } finally {
        await repo.close();
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );
}

class _LargeSource extends Source {
  _LargeSource(super.id);
  @override
  Future<Result<ChapterContent>> getChapter(
    ChapterKey key, {
    required CancellationToken cancellation,
  }) async {
    chapterCalls++;
    return Success(
      ChapterContent(
        key: key,
        title: 'large',
        blocks: [ParagraphBlock(text: 'x' * 1048576)],
      ),
    );
  }
}
