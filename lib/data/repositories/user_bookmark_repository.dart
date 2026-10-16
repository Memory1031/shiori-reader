import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../local/database/user_database.dart' show UserDatabase;
import '../local/local_guard.dart';

class BookmarkChanged implements Exception {}

/// Borrows the user DB. Publication calls snapshot/replace in its own transaction.
final class LocalUserBookmarkRepository implements UserBookmarkRepository {
  LocalUserBookmarkRepository(this.db);
  final UserDatabase db;
  List<Variable> _key(NovelKey key) => [
    Variable(key.sourceId.value),
    Variable(key.novelId),
  ];
  static const _where = 'source_id=? AND novel_id=?';
  Future<int> revision(NovelKey key) async =>
      (await db
              .customSelect(
                'SELECT revision FROM bookmark_versions WHERE $_where',
                variables: _key(key),
              )
              .getSingleOrNull())
          ?.read<int>('revision') ??
      0;
  Future<BookmarkSnapshot> snapshot(NovelKey key) async {
    final stamp = await revision(key);
    final rows = await db
        .customSelect(
          'SELECT * FROM user_bookmarks WHERE $_where ORDER BY created_at DESC,id',
          variables: _key(key),
        )
        .get();
    return BookmarkSnapshot(
      stamp,
      rows.map(
        (r) => UserBookmark(
          id: r.read<String>('id'),
          chapter: ChapterKey(
            novelKey: key,
            chapterId: r.read<String>('chapter_id'),
          ),
          anchor: BookmarkAnchor.fromJson(
            jsonDecode(r.read<String>('anchor_json')) as Map<String, dynamic>,
          ),
          chapterTitle: r.read<String>('chapter_title'),
          createdAt: DateTime.fromMicrosecondsSinceEpoch(
            r.read<int>('created_at'),
            isUtc: true,
          ),
          version: r.read<int>('version'),
          location: BookmarkLocation.values.byName(r.read<String>('location')),
        ),
      ),
    );
  }

  Future<void> advance(NovelKey key) => db
      .customUpdate(
        'INSERT INTO bookmark_versions(source_id,novel_id,revision) VALUES(?,?,1) ON CONFLICT(source_id,novel_id) DO UPDATE SET revision=revision+1',
        variables: _key(key),
        updates: {db.bookmarkVersions},
      )
      .then((_) {});
  Future<void> clear(NovelKey key) async {
    await advance(key);
    await db.customUpdate(
      'DELETE FROM user_bookmarks WHERE $_where',
      variables: _key(key),
      updates: {db.userBookmarks},
    );
  }

  Future<void> replace(
    NovelKey key,
    BookmarkSnapshot before,
    List<UserBookmark> next,
  ) async {
    if (await revision(key) != before.revision ||
        before.bookmarks.length != next.length) {
      throw BookmarkChanged();
    }
    for (var i = 0; i < next.length; i++) {
      final b = next[i], previous = before.bookmarks[i];
      if (b.id != previous.id ||
          b.chapter.novelKey != key ||
          b.version != previous.version + 1) {
        throw StateError('Bookmark migration identity');
      }
      if (await _update(b, previous.version) != 1) throw BookmarkChanged();
    }
    await advance(key);
  }

  Future<int> _update(UserBookmark b, int previous) => db.customUpdate(
    'UPDATE user_bookmarks SET chapter_id=?,anchor_json=?,chapter_title=?,location=?,version=? WHERE id=? AND $_where AND version=?',
    variables: [
      Variable(b.chapter.chapterId),
      Variable(jsonEncode(b.anchor.toJson())),
      Variable(b.chapterTitle),
      Variable(b.location.name),
      Variable(b.version),
      Variable(b.id),
      ..._key(b.chapter.novelKey),
      Variable(previous),
    ],
    updates: {db.userBookmarks},
  );
  @override
  Stream<Result<BookmarkSnapshot>> watchBookmarks(NovelKey book) => localWatch(
    db
        .customSelect(
          'SELECT revision FROM bookmark_versions WHERE $_where',
          variables: _key(book),
          readsFrom: {db.bookmarkVersions, db.userBookmarks},
        )
        .watch()
        .asyncMap((_) => db.transaction(() => snapshot(book))),
    Operation.libraryRead,
  );
  @override
  Future<Result<BookmarkSnapshot>> readBookmarks(
    NovelKey book, {
    required CancellationToken cancellation,
  }) => localRead(
    Operation.libraryRead,
    cancellation,
    () => db.transaction(() => snapshot(book)),
  );
  @override
  Future<Result<bool>> saveBookmark(
    UserBookmark b, {
    required int revision,
    required CancellationToken cancellation,
  }) => localWrite(db, Operation.libraryWrite, cancellation, () async {
    final key = b.chapter.novelKey;
    if (await this.revision(key) != revision) return false;
    if (key.sourceId == LocalBookIdentity.sourceId &&
        (await db
                .customSelect(
                  'SELECT 1 FROM local_books WHERE digest=? AND maintenance=0',
                  variables: [Variable(key.novelId)],
                )
                .get())
            .isEmpty) {
      return false;
    }
    final current = await snapshot(key);
    if (b.version == 1) {
      final p = b.anchor.position;
      if (current.bookmarks.any(
        (v) =>
            v.chapter == b.chapter &&
            v.anchor.position.contentRevision == p.contentRevision &&
            v.anchor.position.blockKey == p.blockKey &&
            v.anchor.position.blockFraction == p.blockFraction,
      )) {
        return false;
      }
      await db.customUpdate(
        'INSERT INTO user_bookmarks(id,source_id,novel_id,chapter_id,anchor_json,chapter_title,created_at,version,location) VALUES(?,?,?,?,?,?,?,?,?)',
        variables: [
          Variable(b.id),
          ..._key(key),
          Variable(b.chapter.chapterId),
          Variable(jsonEncode(b.anchor.toJson())),
          Variable(b.chapterTitle),
          Variable(b.createdAt.toUtc().microsecondsSinceEpoch),
          Variable(b.version),
          Variable(b.location.name),
        ],
        updates: {db.userBookmarks},
      );
    } else if (await _update(b, b.version - 1) != 1) {
      return false;
    }
    await advance(key);
    return true;
  });
  @override
  Future<Result<bool>> deleteBookmark(
    UserBookmark b, {
    required CancellationToken cancellation,
  }) => localWrite(db, Operation.libraryWrite, cancellation, () async {
    final changed = await db.customUpdate(
      'DELETE FROM user_bookmarks WHERE id=? AND $_where AND version=?',
      variables: [
        Variable(b.id),
        ..._key(b.chapter.novelKey),
        Variable(b.version),
      ],
      updates: {db.userBookmarks},
    );
    if (changed == 0) return false;
    await advance(b.chapter.novelKey);
    return true;
  });
}
