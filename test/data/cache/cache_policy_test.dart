import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/cache/cache_policy.dart';
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/repositories/novel_repository.dart';
import 'package:shiori/data/sources/source_registry.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import '../repositories/novel_repository_test.dart' show Source;

void main() {
  test('production TTL differs and chapter has no hard expiry', () async {
    final now = DateTime.utc(2026);
    final db = CacheDatabase(NativeDatabase.memory());
    final owner = CacheCoordinator(now: () => now);
    final source = Source();
    final repo = createNovelRepository(
      sources: SourceRegistry([source]),
      cache: db,
      coordinator: owner,
      now: () => now,
    );
    final token = CancellationSource().token;
    await repo.loadDetail(
      source.novel,
      mode: ReadMode.cacheFirst,
      cancellation: token,
    );
    await repo.loadCatalog(
      source.novel,
      mode: ReadMode.cacheFirst,
      cancellation: token,
    );
    await repo.loadChapter(
      ChapterKey(novelKey: source.novel, chapterId: 'chapter'),
      mode: ReadMode.cacheFirst,
      cancellation: token,
    );
    final detail = await db
        .customSelect('SELECT expires_at-fetched_at AS ttl FROM novel_cache')
        .getSingle();
    final catalog = await db
        .customSelect('SELECT expires_at-fetched_at AS ttl FROM catalog_cache')
        .getSingle();
    expect(detail.read<int>('ttl'), const Duration(hours: 24).inMilliseconds);
    expect(catalog.read<int>('ttl'), const Duration(hours: 1).inMilliseconds);
    final chapter = await db
        .customSelect('SELECT expires_at FROM chapter_cache')
        .getSingle();
    expect(chapter.readNullable<int>('expires_at'), isNull);
    await repo.close();
    await owner.close();
    await db.close();
  });

  test(
    'clear generation rejects a late remote completion before writing',
    () async {
      final db = CacheDatabase(NativeDatabase.memory());
      final owner = CacheCoordinator();
      final source = Source()..pending = Completer<Result<ChapterContent>>();
      final repo = createNovelRepository(
        sources: SourceRegistry([source]),
        cache: db,
        coordinator: owner,
      );
      final key = ChapterKey(novelKey: source.novel, chapterId: 'chapter');
      final loading = repo.loadChapter(
        key,
        mode: ReadMode.cacheFirst,
        cancellation: CancellationSource().token,
      );
      while (source.chapterCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      owner.invalidate();
      source.pending!.complete(
        Success(
          ChapterContent(
            key: key,
            title: 'chapter',
            blocks: [ParagraphBlock(text: 'late')],
          ),
        ),
      );
      expect(await loading, isA<Failure>());
      expect(
        await db.customSelect('SELECT * FROM chapter_cache').get(),
        isEmpty,
      );
      await repo.close();
      await owner.close();
      await db.close();
    },
  );

  test(
    'LRU evicts unpinned payload while keeping the active chapter',
    () async {
      final db = CacheDatabase(NativeDatabase.memory());
      final owner = CacheCoordinator(
        policy: const CachePolicy(textBytes: 1800),
      );
      final records = NovelRecordStore(db, coordinator: owner);
      final novel = NovelKey(sourceId: SourceId('fixture'), novelId: 'book');
      final active = ChapterKey(novelKey: novel, chapterId: 'active');
      final release = owner.pin(
        NovelRecordStore.recordId('chapter_cache', novel, 'active'),
      );
      for (final id in ['active', 'old', 'new']) {
        await records.writeChapter(
          ChapterContent(
            key: ChapterKey(novelKey: novel, chapterId: id),
            title: id,
            blocks: [ParagraphBlock(text: 'x' * 600)],
          ),
          fetchedAt: DateTime.utc(2026).add(Duration(seconds: id.length)),
          parserVersion: 1,
          cancellation: CancellationSource().token,
        );
      }
      expect(
        await records.readChapter(
          active,
          cancellation: CancellationSource().token,
        ),
        isA<Success<StoredRecord<ChapterContent>?>>().having(
          (r) => r.value,
          'active',
          isNotNull,
        ),
      );
      expect(
        (await db.customSelect('SELECT * FROM chapter_cache').get()).length,
        lessThan(3),
      );
      release();
      release();
      await owner.close();
      await db.close();
    },
  );
}
