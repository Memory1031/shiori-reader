import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/user_bookmark_repository.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/bookmark_position.dart';

final key = NovelKey(sourceId: SourceId('source'), novelId: 'book');
UserBookmark bookmark(String id, {NovelKey? book}) {
  final c = ChapterContent(
    key: ChapterKey(novelKey: book ?? key, chapterId: 'chapter'),
    title: 'Chapter',
    blocks: [
      ParagraphBlock(text: 'A sufficiently unique paragraph for bookmark $id'),
    ],
  );
  final p = ReaderPosition(
    contentRevision: c.contentRevision,
    blockKey: c.blocks.first.blockKey,
    blockIndex: 0,
    blockFraction: .3,
    chapterFraction: .3,
  );
  return UserBookmark(
    id: id,
    chapter: c.key,
    anchor: BookmarkPositionIndex([c]).capture(c.key, p)!,
    chapterTitle: c.title,
    createdAt: DateTime.utc(2026, 10, 16, 0, int.parse(id)),
  );
}

void main() {
  test(
    'multiple bookmarks isolate books, survive reopen and history clearing',
    () async {
      final root = await Directory.systemTemp.createTemp('shiori-bookmark-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/users.sqlite');
      var db = UserDatabase(NativeDatabase(file));
      var repo = LocalUserBookmarkRepository(db);
      final token = CancellationSource().token;
      expect(
        await repo.saveBookmark(
          bookmark('1'),
          revision: 0,
          cancellation: token,
        ),
        isA<Success<bool>>(),
      );
      expect(
        (await repo.saveBookmark(
                  bookmark('2'),
                  revision: 1,
                  cancellation: token,
                )
                as Success<bool>)
            .value,
        isTrue,
      );
      final other = NovelKey(sourceId: key.sourceId, novelId: 'other');
      await repo.saveBookmark(
        bookmark('3', book: other),
        revision: 0,
        cancellation: token,
      );
      final before = await repo.snapshot(key);
      expect(before.bookmarks.map((b) => b.id), ['2', '1']);
      final duplicate = UserBookmark(
        id: 'duplicate',
        chapter: before.bookmarks.first.chapter,
        anchor: before.bookmarks.first.anchor,
        chapterTitle: 'Chapter',
        createdAt: DateTime.utc(2026),
      );
      expect(
        (await repo.saveBookmark(duplicate, revision: 2, cancellation: token)
                as Success<bool>)
            .value,
        isFalse,
      );
      await LocalLibraryRepository(db).clearHistory(key, cancellation: token);
      await db.close();
      db = UserDatabase(NativeDatabase(file));
      repo = LocalUserBookmarkRepository(db);
      expect((await repo.snapshot(key)).bookmarks.map((b) => b.id), ['2', '1']);
      expect((await repo.snapshot(other)).bookmarks.single.id, '3');
      await LocalLibraryRepository(
        db,
      ).removeOnlineBook(key, cancellation: token);
      expect((await repo.snapshot(key)).bookmarks, isEmpty);
      expect(
        (await repo.saveBookmark(
                  bookmark('4'),
                  revision: before.revision,
                  cancellation: token,
                )
                as Success<bool>)
            .value,
        isFalse,
      );
      await db.close();
    },
  );
  for (final operation in ['add', 'delete', 'removeBook']) {
    test(
      'publication CAS rejects $operation after migration snapshot without resurrection',
      () async {
        final db = UserDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = LocalUserBookmarkRepository(db),
            token = CancellationSource().token;
        await repo.saveBookmark(
          bookmark('1'),
          revision: 0,
          cancellation: token,
        );
        final before = await repo.snapshot(key);
        final migrated = [
          for (final b in before.bookmarks)
            b.resolved(b.chapter, b.anchor, BookmarkLocation.migrated),
        ];
        switch (operation) {
          case 'add':
            await repo.saveBookmark(
              bookmark('2'),
              revision: before.revision,
              cancellation: token,
            );
          case 'delete':
            await repo.deleteBookmark(
              before.bookmarks.single,
              cancellation: token,
            );
          case 'removeBook':
            await LocalLibraryRepository(
              db,
            ).removeOnlineBook(key, cancellation: token);
        }
        final current = await repo.snapshot(key);
        await expectLater(
          db.transaction(() => repo.replace(key, before, migrated)),
          throwsA(isA<BookmarkChanged>()),
        );
        expect(
          (await repo.snapshot(key)).bookmarks.map((b) => b.id),
          current.bookmarks.map((b) => b.id),
        );
        if (operation != 'add') expect(current.bookmarks, isEmpty);
      },
    );
  }
  test(
    'failed publication rolls back anchors and mutation stamp together',
    () async {
      final db = UserDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LocalUserBookmarkRepository(db),
          token = CancellationSource().token;
      await repo.saveBookmark(bookmark('1'), revision: 0, cancellation: token);
      final before = await repo.snapshot(key);
      await expectLater(
        db.transaction(() async {
          await repo.replace(key, before, [
            before.bookmarks.single.resolved(
              before.bookmarks.single.chapter,
              before.bookmarks.single.anchor,
              BookmarkLocation.unavailable,
            ),
          ]);
          throw StateError('commit fault');
        }),
        throwsStateError,
      );
      final after = await repo.snapshot(key);
      expect(after.revision, before.revision);
      expect(after.bookmarks.single.location, BookmarkLocation.exact);
      expect(after.bookmarks.single.version, 1);
    },
  );
}
