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
    'cold snapshot, catalog growth and late session writes preserve new metadata',
    () async {
      final dir = await Directory.systemTemp.createTemp('book-progress-');
      final file = File('${dir.path}/users.sqlite');
      var db = UserDatabase(NativeDatabase(file));
      var repo = LocalLibraryRepository(db);
      final key = NovelKey(sourceId: SourceId('online'), novelId: 'book');
      Catalog catalog(int count) => Catalog(
        novelKey: key,
        volumes: [
          Volume(
            groupId: 'v',
            chapters: List.generate(
              count,
              (i) => Chapter(
                key: ChapterKey(novelKey: key, chapterId: '$i'),
                title: '$i',
                ordinal: i,
                volumeGroupId: 'v',
              ),
            ),
          ),
        ],
      );
      final token = CancellationSource().token;
      final old = catalog(2);
      final progress = ReadingProgress(
        snapshot: NovelSummary(key: key, title: 'Book'),
        chapterKey: old.flatChapters.last.key,
        chapterOrdinalSnapshot: 1,
        catalogRevision: old.revision,
        position: ReaderPosition(
          contentRevision: 'content',
          blockKey: 'block',
          blockIndex: 0,
          blockFraction: 1,
          chapterFraction: 1,
        ),
        completed: true,
        lastReadAt: DateTime.utc(2026),
        bookProgress: BookProgressSnapshot(
          fraction: 1,
          chapterCount: 2,
          terminal: BookTerminalState.caughtUp,
        ),
      );
      final gen =
          (await repo.beginProgressSession(key, cancellation: token)
                  as Success<int>)
              .value;
      expect(
        await repo.saveProgress(
          progress,
          stamp: ProgressWriteStamp(generation: gen, sequence: 0),
          cancellation: token,
        ),
        isA<Success<bool>>(),
      );
      await db.close();
      db = UserDatabase(NativeDatabase(file));
      repo = LocalLibraryRepository(db);
      final restored =
          (await repo.getProgress(key, cancellation: token)
                  as Success<ReadingProgress?>)
              .value!;
      expect(restored, progress);
      await repo.reconcileCatalog(catalog(3));
      var updated =
          (await repo.getProgress(key, cancellation: token)
                  as Success<ReadingProgress?>)
              .value!;
      expect(updated.position, progress.position);
      expect(updated.lastReadAt, progress.lastReadAt);
      expect(updated.bookProgress!.fraction, 2 / 3);
      expect(updated.bookProgress!.terminal, BookTerminalState.reading);
      expect(updated.catalogRevision, catalog(3).revision);
      await repo.saveProgress(
        progress,
        stamp: ProgressWriteStamp(generation: gen, sequence: 1),
        cancellation: token,
      );
      updated =
          (await repo.getProgress(key, cancellation: token)
                  as Success<ReadingProgress?>)
              .value!;
      expect(updated.bookProgress!.fraction, 2 / 3);
      await db.customStatement(
        "UPDATE reading_progress SET book_progress='{\"fraction\":2,\"chapterCount\":3,\"terminal\":\"reading\"}'",
      );
      expect(
        await repo.getProgress(key, cancellation: token),
        isA<Failure<ReadingProgress?>>(),
      );
      await db.close();
      await dir.delete(recursive: true);
    },
  );
}
