import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';

void main() {
  test(
    'shelf and uncollected history survive database reopen; stable order and clear boundary',
    () async {
      final dir = await Directory.systemTemp.createTemp('shiori-phase5-test-');
      final file = File('${dir.path}/fixture.sqlite');
      var db = UserDatabase(NativeDatabase(file));
      var repo = LocalLibraryRepository(db);
      final token = CancellationSource().token;
      final a = NovelSummary(
        key: NovelKey(sourceId: SourceId('fixture'), novelId: 'a'),
        title: 'A',
      );
      final b = NovelSummary(
        key: NovelKey(sourceId: SourceId('fixture'), novelId: 'b'),
        title: 'B',
      );
      final date = DateTime.utc(2026);
      await repo.putBookshelf(
        BookshelfEntry(snapshot: b, addedAt: date),
        cancellation: token,
      );
      await repo.putBookshelf(
        BookshelfEntry(snapshot: a, addedAt: date),
        cancellation: token,
      );
      expect(
        (await repo.watchBookshelf().first as Success<List<BookshelfEntry>>)
            .value
            .first
            .snapshot
            .key,
        a.key,
      );
      final stamp =
          (await repo.beginProgressSession(b.key, cancellation: token)
                  as Success<int>)
              .value;
      final record = ReadingProgress(
        snapshot: b,
        chapterKey: ChapterKey(novelKey: b.key, chapterId: 'c'),
        chapterOrdinalSnapshot: 0,
        catalogRevision: 'catalog',
        position: ReaderPosition(
          contentRevision: 'content',
          blockKey: 'block',
          blockIndex: 2,
          blockFraction: .2,
          chapterFraction: .4,
        ),
        completed: false,
        lastReadAt: DateTime.utc(2026, 9),
      );
      await repo.saveProgress(
        record,
        stamp: ProgressWriteStamp(generation: stamp, sequence: 0),
        cancellation: token,
      );
      expect(
        (await repo.watchBookshelf().first as Success<List<BookshelfEntry>>)
            .value
            .first
            .snapshot
            .key,
        b.key,
      );
      await repo.removeFromBookshelf(b.key, cancellation: token);
      await db.close();
      db = UserDatabase(NativeDatabase(file));
      repo = LocalLibraryRepository(db);
      expect(
        (await repo.getProgress(b.key, cancellation: token)
                as Success<ReadingProgress?>)
            .value,
        record,
      );
      expect(
        (await repo.watchBookshelf().first as Success<List<BookshelfEntry>>)
            .value
            .single
            .snapshot
            .key,
        a.key,
      );
      await repo.clearHistory(b.key, cancellation: token);
      expect(
        (await repo.watchRecentReading().first
                as Success<List<ReadingProgress>>)
            .value,
        isEmpty,
      );
      expect(
        (await repo.watchBookshelf().first as Success<List<BookshelfEntry>>)
            .value
            .length,
        1,
      );
      await db.close();
      // The directory was created exclusively by this test in the OS temp root.
      expect(
        dir.absolute.path.startsWith(
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
        ),
        isTrue,
      );
      await dir.delete(recursive: true);
    },
  );
}
