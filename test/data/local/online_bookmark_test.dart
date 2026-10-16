import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/user_bookmark_repository.dart';
import 'package:shiori/data/repositories/novel_repository.dart';
import 'package:shiori/data/sources/source_registry.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/bookmark_position.dart';
import '../repositories/novel_repository_test.dart' show Source;

class BookSource extends Source {
  String body =
      'A uniquely identifiable paragraph retained after cache eviction.';
  FailureKind? fail;
  @override
  Future<Result<ChapterContent>> getChapter(
    ChapterKey key, {
    required CancellationToken cancellation,
  }) async {
    chapterCalls++;
    if (fail case final kind?) {
      return Failure(
        AppFailure(
          kind: kind,
          operation: Operation.chapter,
          retryPolicy: RetryPolicy.manual,
        ),
      );
    }
    if (key.chapterId != 'chapter') {
      return Failure(
        AppFailure(kind: FailureKind.notFound, operation: Operation.chapter),
      );
    }
    return Success(
      ChapterContent(
        key: key,
        title: 'Chapter',
        blocks: [ParagraphBlock(text: body)],
      ),
    );
  }
}

void main() {
  test(
    'bookmarks and local list survive disposable chapter eviction, refresh and remote failure',
    () async {
      final users = UserDatabase(NativeDatabase.memory()),
          cache = CacheDatabase(NativeDatabase.memory()),
          source = BookSource();
      final bookmarks = LocalUserBookmarkRepository(users),
          novels = createNovelRepository(
            sources: SourceRegistry([source]),
            cache: cache,
          );
      addTearDown(() async {
        await novels.close();
        await cache.close();
        await users.close();
      });
      final key = ChapterKey(novelKey: source.novel, chapterId: 'chapter'),
          token = CancellationSource().token;
      Future<Result<LoadResult<ChapterContent>>> load() => novels.loadChapter(
        key,
        mode: ReadMode.cacheFirst,
        cancellation: token,
      );
      final c =
          (await load() as Success<LoadResult<ChapterContent>>).value.value;
      final p = ReaderPosition(
        contentRevision: c.contentRevision,
        blockKey: c.blocks.first.blockKey,
        blockIndex: 0,
        blockFraction: 0,
        chapterFraction: 0,
      );
      final anchor = BookmarkPositionIndex([c]).capture(c.key, p)!;
      await bookmarks.saveBookmark(
        UserBookmark(
          id: 'one',
          chapter: key,
          anchor: anchor,
          chapterTitle: c.title,
          createdAt: DateTime.utc(2026),
        ),
        revision: 0,
        cancellation: token,
      );
      final calls = source.chapterCalls;
      await cache.customStatement('DELETE FROM chapter_cache');
      final snapshot = await bookmarks.readBookmarks(
        source.novel,
        cancellation: token,
      );
      expect(
        (snapshot as Success<BookmarkSnapshot>).value.bookmarks.single.id,
        'one',
      );
      expect(source.chapterCalls, calls);
      final reloaded =
          (await load() as Success<LoadResult<ChapterContent>>).value.value;
      expect(source.chapterCalls, calls + 1);
      expect(
        BookmarkPositionIndex([reloaded]).resolve(key, anchor).location,
        BookmarkLocation.exact,
      );
      await cache.customStatement('DELETE FROM chapter_cache');
      source.body =
          'An entirely different body replacing the original online text.';
      final changed =
          (await load() as Success<LoadResult<ChapterContent>>).value.value;
      expect(
        BookmarkPositionIndex([changed]).resolve(key, anchor).located,
        isFalse,
      );
      await cache.customStatement('DELETE FROM chapter_cache');
      source.fail = FailureKind.network;
      expect(await load(), isA<Failure<LoadResult<ChapterContent>>>());
      expect(
        (await bookmarks.snapshot(source.novel)).bookmarks.single.id,
        'one',
      );
      source.fail = null;
      final missing = await novels.loadChapter(
        ChapterKey(novelKey: source.novel, chapterId: 'deleted'),
        mode: ReadMode.cacheFirst,
        cancellation: token,
      );
      expect(
        (missing as Failure<LoadResult<ChapterContent>>).failure.kind,
        FailureKind.notFound,
      );
      expect((await bookmarks.snapshot(source.novel)).bookmarks.length, 1);
      // A bookmark alone is durable user ownership, even after history is cleared.
      await users.customStatement(
        "INSERT INTO progress_catalogs VALUES(?,?,'{}',1,'remote')",
        [source.novel.sourceId.value, source.novel.novelId],
      );
      await users.repairOnlineOwnership();
      expect(
        await users.customSelect('SELECT * FROM progress_catalogs').get(),
        hasLength(1),
      );
    },
  );
}
