import 'package:drift/drift.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../local/database/cache_database.dart';
import '../local/novel_record_store.dart';
import '../local/record_codec.dart';
import '../media/persistent_image_repository.dart';
import 'cache_policy.dart';

class LocalCacheManagement implements CacheManagement {
  LocalCacheManagement(this.db, this.coordinator, this.images);
  final CacheDatabase db;
  final CacheCoordinator coordinator;
  final PersistentImageRepository images;
  @override
  ReadingPrefetch? prefetch;
  static const _tables = ['novel_cache', 'catalog_cache', 'chapter_cache'];
  @override
  void Function() pinChapter(ChapterKey key) => coordinator.pin(
    NovelRecordStore.recordId('chapter_cache', key.novelKey, key.chapterId),
  );
  @override
  Future<Result<CacheOverview>> inspect({NovelKey? novel}) async {
    final generation = coordinator.generation;
    try {
      final filter = novel == null ? '' : ' WHERE source_id=? AND novel_id=?';
      final vars = <Variable>[
        if (novel != null) ...[
          Variable(novel.sourceId.value),
          Variable(novel.novelId),
        ],
      ];
      var textBytes = 0;
      for (final table in _tables) {
        final row = await db
            .customSelect(
              'SELECT COALESCE(SUM(byte_size),0) AS total FROM $table$filter',
              variables: vars,
            )
            .getSingle();
        textBytes += row.read<int>('total');
      }
      // A valid JSON payload can still have an unsupported outer codec.
      final readableFilter =
          '$filter${novel == null ? " WHERE" : " AND"} codec_version=1';
      final chapterRows = await db
          .customSelect(
            'SELECT payload FROM chapter_cache$readableFilter',
            variables: vars,
          )
          .get();
      final chapters = <CachedChapter>[];
      final books = <NovelKey, String>{};
      final details = await db
          .customSelect(
            'SELECT payload FROM novel_cache$readableFilter',
            variables: vars,
          )
          .get();
      for (final row in details) {
        try {
          final detail = RecordCodec.readDetail(row.read<String>('payload'));
          books[detail.summary.key] = detail.summary.title;
        } catch (_) {
          /* Invalid metadata is not a readable book. */
        }
      }
      for (final row in chapterRows) {
        ChapterContent content;
        try {
          content = RecordCodec.readChapter(row.read<String>('payload'));
        } catch (_) {
          continue;
        }
        final refs = content.blocks
            .whereType<ImageBlock>()
            .map((b) => b.media)
            .toSet();
        var saved = 0;
        for (final ref in refs) {
          final result = await images.load(
            ref,
            mode: ReadMode.cacheOnly,
            cancellation: CancellationSource().token,
          );
          if (result case Success(:final value)) {
            if (value.value.persistence == MediaPersistence.persistedLocal) {
              saved++;
            }
            await value.value.close();
          }
        }
        chapters.add(
          CachedChapter(
            key: content.key,
            title: content.title,
            imageCount: refs.length,
            savedImages: saved,
          ),
        );
        books.putIfAbsent(content.key.novelKey, () => content.title);
      }
      final imageRows = await db
          .customSelect(
            novel == null
                ? 'SELECT COALESCE(SUM(byte_size),0) AS total FROM image_cache'
                : 'SELECT COALESCE(SUM(byte_size),0) AS total FROM image_cache WHERE cache_key IN (SELECT cache_key FROM image_owners WHERE source_id=? AND novel_id=?)',
            variables: vars,
          )
          .getSingle();
      if (coordinator.generation != generation) {
        return Failure(AppFailure.cancelled(Operation.libraryRead));
      }
      return Success(
        CacheOverview(
          textBytes: textBytes,
          imageBytes: imageRows.read<int>('total'),
          chapters: chapters,
          books: books,
        ),
      );
    } catch (_) {
      return Failure(
        AppFailure(kind: FailureKind.cache, operation: Operation.libraryRead),
      );
    }
  }

  @override
  Future<Result<void>> clear({NovelKey? novel}) async {
    coordinator.invalidate();
    images.network.invalidate();
    try {
      await coordinator.exclusive(() async {
        await db.transaction(() async {
          final filter = novel == null
              ? ''
              : ' WHERE source_id=? AND novel_id=?';
          final args = <Object?>[
            if (novel != null) ...[novel.sourceId.value, novel.novelId],
          ];
          for (final table in _tables) {
            await db.customStatement('DELETE FROM $table$filter', args);
          }
          if (novel == null) {
            await db.customStatement('DELETE FROM image_cache');
            await db.customStatement('DELETE FROM image_owners');
          } else {
            final owned = await db
                .customSelect(
                  'SELECT cache_key FROM image_owners$filter',
                  variables: [
                    Variable(novel.sourceId.value),
                    Variable(novel.novelId),
                  ],
                )
                .get();
            await db.customStatement('DELETE FROM image_owners$filter', args);
            for (final row in owned) {
              await db.customStatement(
                'DELETE FROM image_cache WHERE cache_key=? AND NOT EXISTS(SELECT 1 FROM image_owners WHERE cache_key=image_cache.cache_key)',
                [row.read<String>('cache_key')],
              );
            }
          }
        });
      });
      await images.maintain();
      return const Success(null);
    } catch (_) {
      return Failure(
        AppFailure(kind: FailureKind.cache, operation: Operation.libraryWrite),
      );
    }
  }
}
