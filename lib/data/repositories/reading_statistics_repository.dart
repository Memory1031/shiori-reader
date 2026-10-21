import 'dart:math';
import 'package:drift/drift.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../local/database/user_database.dart';
import '../local/local_guard.dart';
import '../local/record_codec.dart';

/// Borrows the app's user database after exclusive storage ownership is held.
class LocalReadingStatisticsRepository implements ReadingStatisticsRepository {
  LocalReadingStatisticsRepository(this.db);
  final UserDatabase db;
  CancellationToken get _token => CancellationSource().token;
  @override
  Stream<void> get changes => db
      .customSelect(
        'SELECT epoch,enabled,notice_seen,started_day FROM reading_statistics_state WHERE id=1',
        readsFrom: {
          db.readingStatisticsState,
          db.readingStatisticsDays,
          db.readingStatisticsBooks,
          db.bookshelf,
          db.readingProgress,
        },
      )
      .watch()
      .map((_) {});

  Future<Result<void>> recover() =>
      localWrite(db, Operation.libraryWrite, _token, () async {
        await db.customUpdate(
          'DELETE FROM reading_statistics_checkpoints',
          updates: {db.readingStatisticsCheckpoints},
        );
      });

  Future<ReadingRecordSettings> _settings() async {
    if ((await db
            .customSelect('SELECT 1 FROM reading_statistics_state WHERE id=1')
            .get())
        .isEmpty) {
      await db.customUpdate(
        'INSERT INTO reading_statistics_state(id) VALUES(1)',
        updates: {db.readingStatisticsState},
      );
    }
    final r = await db
        .customSelect('SELECT * FROM reading_statistics_state WHERE id=1')
        .getSingle();
    return ReadingRecordSettings(
      enabled: r.read<int>('enabled') == 1,
      noticeSeen: r.read<int>('notice_seen') == 1,
      epoch: r.read<int>('epoch'),
      startedDay: r.readNullable<int>('started_day'),
    );
  }

  @override
  Future<Result<ReadingRecordSettings>> settings() =>
      localWrite(db, Operation.libraryRead, _token, _settings);
  @override
  Future<Result<ReadingRecordSettings>> setEnabled(
    bool enabled,
  ) => localWrite(db, Operation.libraryWrite, _token, () async {
    await _settings();
    await db.customUpdate(
      'UPDATE reading_statistics_state SET enabled=?,epoch=epoch+1,notice_seen=1 WHERE id=1',
      variables: [Variable(enabled ? 1 : 0)],
      updates: {db.readingStatisticsState},
    );
    await db.customUpdate(
      'DELETE FROM reading_statistics_checkpoints',
      updates: {db.readingStatisticsCheckpoints},
    );
    return _settings();
  });
  @override
  Future<Result<void>> dismissNotice() =>
      localWrite(db, Operation.libraryWrite, _token, () async {
        await _settings();
        await db.customUpdate(
          'UPDATE reading_statistics_state SET notice_seen=1 WHERE id=1',
          updates: {db.readingStatisticsState},
        );
      });
  @override
  Future<Result<ReadingRecordSettings>>
  clear() => localWrite(db, Operation.libraryWrite, _token, () async {
    await _settings();
    await db.customUpdate(
      'UPDATE reading_statistics_state SET epoch=epoch+1,started_day=NULL WHERE id=1',
      updates: {db.readingStatisticsState},
    );
    for (final table in <TableInfo>[
      db.readingStatisticsDays,
      db.readingStatisticsBooks,
      db.readingStatisticsCheckpoints,
    ]) {
      await db.customUpdate(
        'DELETE FROM ${table.actualTableName}',
        updates: {table},
      );
    }
    return _settings();
  });
  @override
  Future<Result<ReadingRecordSession?>> begin(
    NovelKey book,
  ) => localWrite(db, Operation.libraryWrite, _token, () async {
    final prefs = await _settings();
    if (!prefs.enabled) return null;
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final removal = await db.removalGeneration(
      book.sourceId.value,
      book.novelId,
    );
    if (book.sourceId == LocalBookIdentity.sourceId &&
        (await db
                .customSelect(
                  'SELECT 1 FROM local_books WHERE digest=?',
                  variables: [Variable(book.novelId)],
                )
                .get())
            .isEmpty) {
      return null;
    }
    await db.customUpdate(
      'INSERT INTO reading_statistics_checkpoints(session_id,source_id,novel_id,epoch,removal_generation) VALUES(?,?,?,?,?)',
      variables: [
        Variable(id),
        Variable(book.sourceId.value),
        Variable(book.novelId),
        Variable(prefs.epoch),
        Variable(removal),
      ],
      updates: {db.readingStatisticsCheckpoints},
    );
    return ReadingRecordSession(id, book, prefs.epoch, removal);
  });
  @override
  Future<Result<bool>> submit(
    ReadingCheckpoint checkpoint,
  ) => localWrite(db, Operation.libraryWrite, _token, () async {
    final session = checkpoint.session, book = session.book;
    final prefs = await _settings();
    final row = await db
        .customSelect(
          'SELECT * FROM reading_statistics_checkpoints WHERE session_id=?',
          variables: [Variable(session.id)],
        )
        .getSingleOrNull();
    if (row == null ||
        !prefs.enabled ||
        prefs.epoch != session.epoch ||
        row.read<int>('epoch') != session.epoch ||
        row.read<int>('removal_generation') != session.removalGeneration ||
        row.read<String>('source_id') != book.sourceId.value ||
        row.read<String>('novel_id') != book.novelId ||
        await db.removalGeneration(book.sourceId.value, book.novelId) !=
            session.removalGeneration) {
      return false;
    }
    final days = checkpoint.days.keys.toList()..sort();
    final payload = days.map((day) => '$day:${checkpoint.days[day]}').join(',');
    final sequence = row.read<int>('sequence');
    if (checkpoint.sequence == sequence) {
      if (payload != row.read<String>('payload')) {
        throw const FormatException('Changed checkpoint retry');
      }
      return true;
    }
    if (checkpoint.sequence != sequence + 1) return false;
    for (final day in days) {
      final duration = checkpoint.days[day]!;
      await db.customUpdate(
        'INSERT INTO reading_statistics_days(day,milliseconds) VALUES(?,?) ON CONFLICT(day) DO UPDATE SET milliseconds=milliseconds+excluded.milliseconds',
        variables: [Variable(day), Variable(duration)],
        updates: {db.readingStatisticsDays},
      );
      await db.customUpdate(
        'INSERT INTO reading_statistics_books(day,source_id,novel_id,milliseconds) VALUES(?,?,?,?) ON CONFLICT(day,source_id,novel_id) DO UPDATE SET milliseconds=milliseconds+excluded.milliseconds',
        variables: [
          Variable(day),
          Variable(book.sourceId.value),
          Variable(book.novelId),
          Variable(duration),
        ],
        updates: {db.readingStatisticsBooks},
      );
    }
    await db.customUpdate(
      'UPDATE reading_statistics_checkpoints SET sequence=?,payload=? WHERE session_id=?',
      variables: [
        Variable(checkpoint.sequence),
        Variable(payload),
        Variable(session.id),
      ],
      updates: {db.readingStatisticsCheckpoints},
    );
    await db.customUpdate(
      'UPDATE reading_statistics_state SET started_day=COALESCE(started_day,?) WHERE id=1',
      variables: [Variable(days.first)],
      updates: {db.readingStatisticsState},
    );
    return true;
  });
  @override
  Future<Result<void>> finish(ReadingRecordSession session) =>
      localWrite(db, Operation.libraryWrite, _token, () async {
        await db.customUpdate(
          'DELETE FROM reading_statistics_checkpoints WHERE session_id=?',
          variables: [Variable(session.id)],
          updates: {db.readingStatisticsCheckpoints},
        );
      });
  @override
  Future<Result<ReadingStatisticsSnapshot>> read({
    required int firstDay,
    required int lastDay,
    required int today,
  }) => localWrite(db, Operation.libraryRead, _token, () async {
    final prefs = await _settings();
    final all = await db
        .customSelect('SELECT * FROM reading_statistics_days ORDER BY day')
        .get();
    final days = <int, int>{
      for (final r in all)
        if (r.read<int>('day') >= firstDay && r.read<int>('day') <= lastDay)
          r.read<int>('day'): r.read<int>('milliseconds'),
    };
    final rows = await db
        .customSelect(
          'SELECT s.source_id,s.novel_id,SUM(s.milliseconds) AS duration,COALESCE(b.summary_json,p.summary_json) AS summary,l.title FROM reading_statistics_books s LEFT JOIN bookshelf b ON b.source_id=s.source_id AND b.novel_id=s.novel_id LEFT JOIN reading_progress p ON p.source_id=s.source_id AND p.novel_id=s.novel_id LEFT JOIN local_books l ON s.source_id=\'local\' AND l.digest=s.novel_id WHERE s.day>=? AND s.day<=? GROUP BY s.source_id,s.novel_id ORDER BY duration DESC,s.source_id,s.novel_id',
          variables: [Variable(firstDay), Variable(lastDay)],
        )
        .get();
    final books = <ReadingBookTime>[];
    for (final r in rows) {
      final key = NovelKey(
        sourceId: SourceId(r.read<String>('source_id')),
        novelId: r.read<String>('novel_id'),
      );
      final json = r.readNullable<String>('summary');
      final title = r.readNullable<String>('title');
      final summary = json != null
          ? RecordCodec.readSummary(json)
          : title != null
          ? NovelSummary(key: key, title: title)
          : null;
      if (summary != null && summary.key != key) {
        throw const FormatException('Statistics metadata identity');
      }
      books.add(ReadingBookTime(key, r.read<int>('duration'), summary));
    }
    final total = days.values.fold(0, (a, b) => a + b),
        named = books.fold(0, (a, b) => a + b.milliseconds);
    if (named > total) {
      throw const FormatException('Inconsistent statistics snapshot');
    }
    return ReadingStatisticsSnapshot(
      settings: prefs,
      lifetime: all.fold(0, (a, r) => a + r.read<int>('milliseconds')),
      today: all
          .where((r) => r.read<int>('day') == today)
          .fold(0, (a, r) => a + r.read<int>('milliseconds')),
      days: days,
      books: books,
      anonymous: total - named,
    );
  });
}
