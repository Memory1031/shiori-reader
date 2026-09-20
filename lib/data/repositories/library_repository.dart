import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../local/database/user_database.dart' show UserDatabase;
import '../local/local_guard.dart';
import '../local/record_codec.dart';
import '../local/library_rows.dart';

/// Borrows the single app-owned user database. All writes are transactions.
class LocalLibraryRepository implements LibraryRepository {
  LocalLibraryRepository(this.db, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final UserDatabase db;
  final DateTime Function() now;
  final _catalogs = <NovelKey, BookProgressMetrics>{};
  ReadingProgress _reconcile(
    ReadingProgress progress,
    BookProgressMetrics metrics,
  ) {
    if (progress.catalogRevision == metrics.revision) return progress;
    final ordinal = metrics.ordinal(progress.chapterKey);
    return progress.withBookProgress(
      ordinal == null
          ? null
          : metrics.at(progress.chapterKey, progress.position.chapterFraction),
      ordinal: ordinal,
      revision: metrics.revision,
    );
  }

  /// A catalog already loaded by a reader/detail refresh updates only metadata,
  /// inside the same DB transaction as progress writes. It never opens a session.
  Future<Result<void>> reconcileCatalog(Catalog catalog) {
    final metrics = BookProgressMetrics.online(catalog);
    _catalogs[catalog.novelKey] = metrics;
    return localWrite(
      db,
      Operation.progressWrite,
      CancellationSource().token,
      () async {
        final row = await db
            .customSelect(
              'SELECT * FROM reading_progress WHERE $_where',
              variables: _key(catalog.novelKey),
            )
            .getSingleOrNull();
        if (row == null) return;
        final before = _progress(row);
        final after = _reconcile(before, metrics);
        if (before != after) await writeProgressRow(db, after, now());
      },
    );
  }

  List<Variable> _key(NovelKey key) => [
    Variable(key.sourceId.value),
    Variable(key.novelId),
  ];
  static const _where = 'source_id = ? AND novel_id = ?';
  NovelKey _rowKey(QueryRow row) => NovelKey(
    sourceId: SourceId(row.read<String>('source_id')),
    novelId: row.read<String>('novel_id'),
  );
  NovelSummary _summary(QueryRow row) {
    final value = RecordCodec.readSummary(row.read<String>('summary_json'));
    if (value.key != _rowKey(row)) {
      throw const FormatException('Record identity mismatch');
    }
    return value;
  }

  BookshelfEntry _book(QueryRow row) => BookshelfEntry(
    snapshot: _summary(row),
    addedAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('added_at'),
      isUtc: true,
    ),
  );
  ReadingProgress _progress(QueryRow row) {
    if (row.read<int>('position_version') != 1) {
      throw const FormatException('Unsupported position');
    }
    return ReadingProgress(
      snapshot: _summary(row),
      chapterKey: ChapterKey(
        novelKey: _rowKey(row),
        chapterId: row.read<String>('chapter_id'),
      ),
      chapterOrdinalSnapshot: row.read<int>('chapter_ordinal'),
      catalogRevision: row.read<String>('catalog_revision'),
      position: ReaderPosition(
        contentRevision: row.read<String>('content_revision'),
        blockKey: row.read<String>('block_key'),
        blockIndex: row.read<int>('block_index'),
        blockFraction: row.read<double>('block_fraction'),
        chapterFraction: row.read<double>('chapter_fraction'),
        pixelOffset: row.readNullable<double>('pixel_offset'),
        layoutKey: row.readNullable<String>('layout_key'),
      ),
      bookProgress: row.readNullable<String>('book_progress') == null
          ? null
          : BookProgressSnapshot.fromJson(
              jsonDecode(row.read<String>('book_progress'))
                  as Map<String, dynamic>,
            ),
      completed: row.read<int>('completed') == 1,
      lastReadAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('last_read_at'),
        isUtc: true,
      ),
    );
  }

  @override
  Stream<Result<List<BookshelfEntry>>> watchBookshelf() => localWatch(
    db
        .customSelect(
          'SELECT b.* FROM bookshelf b LEFT JOIN reading_progress r ON b.source_id=r.source_id AND b.novel_id=r.novel_id ORDER BY COALESCE(r.last_read_at,b.added_at) DESC,b.source_id,b.novel_id',
          readsFrom: {db.bookshelf, db.readingProgress},
        )
        .watch()
        .map((rows) => List<BookshelfEntry>.unmodifiable(rows.map(_book))),
    Operation.libraryRead,
  );
  @override
  Stream<Result<List<ReadingProgress>>> watchRecentReading() => localWatch(
    db
        .customSelect(
          'SELECT * FROM reading_progress ORDER BY last_read_at DESC,source_id,novel_id',
          readsFrom: {db.readingProgress},
        )
        .watch()
        .map((rows) => List<ReadingProgress>.unmodifiable(rows.map(_progress))),
    Operation.progressRead,
  );
  @override
  Future<Result<BookshelfEntry>> putBookshelf(
    BookshelfEntry entry, {
    required CancellationToken cancellation,
  }) => localWrite(db, Operation.libraryWrite, cancellation, () async {
    if (!await _available(entry.snapshot.key)) {
      throw const FormatException('Deleted local book');
    }
    await writeBookshelfRow(db, entry, now());
    return _book(
      await db
          .customSelect(
            'SELECT * FROM bookshelf WHERE $_where',
            variables: _key(entry.snapshot.key),
          )
          .getSingle(),
    );
  });
  @override
  Future<Result<BookshelfEntry?>> removeFromBookshelf(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => localWrite(db, Operation.libraryWrite, cancellation, () async {
    final row = await db
        .customSelect(
          'SELECT * FROM bookshelf WHERE $_where',
          variables: _key(key),
        )
        .getSingleOrNull();
    final removed = row == null ? null : _book(row);
    await db.customUpdate(
      'DELETE FROM bookshelf WHERE $_where',
      variables: _key(key),
      updates: {db.bookshelf},
    );
    return removed;
  });
  @override
  Future<Result<ReadingProgress?>> getProgress(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => localRead(Operation.progressRead, cancellation, () async {
    final row = await db
        .customSelect(
          'SELECT * FROM reading_progress WHERE $_where',
          variables: _key(key),
        )
        .getSingleOrNull();
    return row == null ? null : _progress(row);
  });
  Future<int> _advance(NovelKey key) async {
    await db.customUpdate(
      'INSERT INTO progress_sessions(source_id,novel_id,generation,sequence) VALUES(?,?,1,-1) ON CONFLICT(source_id,novel_id) DO UPDATE SET generation=generation+1,sequence=-1',
      variables: _key(key),
      updates: {db.progressSessions},
    );
    return (await db
            .customSelect(
              'SELECT generation FROM progress_sessions WHERE $_where',
              variables: _key(key),
            )
            .getSingle())
        .read<int>('generation');
  }

  Future<bool> _available(NovelKey key) async =>
      key.sourceId != LocalBookIdentity.sourceId ||
      (await db
              .customSelect(
                'SELECT 1 FROM local_books WHERE digest=? AND maintenance=0',
                variables: [Variable(key.novelId)],
              )
              .get())
          .isNotEmpty;

  @override
  Future<Result<int>> beginProgressSession(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => localWrite(db, Operation.progressWrite, cancellation, () async {
    if (!await _available(key)) {
      throw const FormatException('Deleted local book');
    }
    return _advance(key);
  });
  @override
  Future<Result<bool>> saveProgress(
    ReadingProgress progress, {
    required ProgressWriteStamp stamp,
    required CancellationToken cancellation,
  }) => localWrite(db, Operation.progressWrite, cancellation, () async {
    final key = progress.novelKey;
    if (!await _available(key)) return false;
    if (key.sourceId == LocalBookIdentity.sourceId) {
      final row = await db
          .customSelect(
            'SELECT active_bundle FROM local_books WHERE digest=?',
            variables: [Variable(key.novelId)],
          )
          .getSingle();
      if (row.readNullable<String>('active_bundle') != null) {
        final match = await db
            .customSelect(
              'SELECT 1 FROM local_chapter_revisions WHERE digest=? AND chapter_id=? AND content_revision=? AND catalog_revision=?',
              variables: [
                Variable(key.novelId),
                Variable(progress.chapterKey.chapterId),
                Variable(progress.position.contentRevision),
                Variable(progress.catalogRevision),
              ],
            )
            .get();
        if (match.isEmpty) return false;
      }
    }
    final session = await db
        .customSelect(
          'SELECT generation,sequence FROM progress_sessions WHERE $_where',
          variables: _key(key),
        )
        .getSingleOrNull();
    if (session == null ||
        session.read<int>('generation') != stamp.generation ||
        stamp.sequence <= session.read<int>('sequence')) {
      return false;
    }
    final known = _catalogs[key];
    await writeProgressRow(
      db,
      known == null ? progress : _reconcile(progress, known),
      now(),
    );
    await db.customUpdate(
      'UPDATE progress_sessions SET sequence=? WHERE $_where',
      variables: [Variable(stamp.sequence), ..._key(key)],
      updates: {db.progressSessions},
    );
    return true;
  });
  @override
  Future<Result<void>> clearHistory(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => localWrite(db, Operation.progressWrite, cancellation, () async {
    await _advance(key);
    await db.customUpdate(
      'DELETE FROM reading_progress WHERE $_where',
      variables: _key(key),
      updates: {db.readingProgress},
    );
  });
}
