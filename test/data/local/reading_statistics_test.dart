import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/reading_statistics_repository.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';

T value<T>(Result<T> result) => (result as Success<T>).value;
final book = NovelKey(sourceId: SourceId('source'), novelId: 'book');
void main() {
  late UserDatabase db;
  late LocalReadingStatisticsRepository repo;
  setUp(() {
    db = UserDatabase(NativeDatabase.memory());
    repo = LocalReadingStatisticsRepository(db);
  });
  tearDown(() async {
    await db.close();
  });
  test(
    'default, closed preference, notice and clear preserve independent state',
    () async {
      expect(value(await repo.settings()).enabled, true);
      expect(value(await repo.settings()).noticeSeen, false);
      await repo.dismissNotice();
      expect(value(await repo.settings()).noticeSeen, true);
      await repo.setEnabled(false);
      expect(
        value(await LocalReadingStatisticsRepository(db).settings()).enabled,
        false,
      );
      await repo.clear();
      expect(value(await repo.settings()).enabled, false);
    },
  );
  test(
    'immutable retry is idempotent even when commit acknowledgement was lost',
    () async {
      final s = value(await repo.begin(book))!;
      final first = ReadingCheckpoint(s, 1, {20261021: 15000});
      expect(value(await repo.submit(first)), true);
      expect(value(await repo.submit(first)), true);
      expect(
        await repo.submit(ReadingCheckpoint(s, 1, {20261021: 20000})),
        isA<Failure>(),
      );
      expect(
        value(await repo.submit(ReadingCheckpoint(s, 2, {20261021: 1000}))),
        true,
      );
      final snap = value(
        await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
      );
      expect(snap.total, 16000);
      expect(snap.books.single.milliseconds, 16000);
      expect(snap.anonymous, 0);
      expect(snap.settings.startedDay, 20261021);
    },
  );
  test(
    'delete keeps total, rejects old checkpoint and reimport never reconnects',
    () async {
      final s = value(await repo.begin(book))!;
      await repo.submit(ReadingCheckpoint(s, 1, {20261021: 10000}));
      final library = LocalLibraryRepository(db);
      await library.removeOnlineBook(
        book,
        cancellation: CancellationSource().token,
      );
      expect(
        value(await repo.submit(ReadingCheckpoint(s, 2, {20261021: 5000}))),
        false,
      );
      var snap = value(
        await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
      );
      expect(snap.total, 10000);
      expect(snap.books, isEmpty);
      expect(snap.anonymous, 10000);
      final newSession = value(await repo.begin(book))!;
      await repo.submit(ReadingCheckpoint(newSession, 1, {20261021: 2000}));
      snap = value(
        await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
      );
      expect(snap.total, 12000);
      expect(snap.books.single.milliseconds, 2000);
      expect(snap.anonymous, 10000);
    },
  );
  test(
    'clear invalidates inflight generation without changing enabled or book data',
    () async {
      final s = value(await repo.begin(book))!;
      await repo.submit(ReadingCheckpoint(s, 1, {20261021: 10000}));
      await repo.clear();
      expect(
        value(await repo.submit(ReadingCheckpoint(s, 2, {20261021: 20000}))),
        false,
      );
      final snap = value(
        await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
      );
      expect(snap.total, 0);
      expect(snap.settings.startedDay, isNull);
      expect(snap.settings.enabled, true);
    },
  );
  test('unavailable storage is not an absent enabled preference', () async {
    await db.customStatement('SELECT 1');
    await db.customStatement('DROP TABLE reading_statistics_state');
    expect(await repo.settings(), isA<Failure>());
  });
  test(
    'history clear retains statistics and same-snapshot sums remain valid',
    () async {
      final s = value(await repo.begin(book))!;
      await repo.submit(ReadingCheckpoint(s, 1, {20261021: 15000}));
      await LocalLibraryRepository(
        db,
      ).clearHistory(book, cancellation: CancellationSource().token);
      expect(
        value(await repo.submit(ReadingCheckpoint(s, 2, {20261021: 5000}))),
        true,
      );
      final snap = value(
        await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
      );
      expect(snap.total, 20000);
      expect(
        snap.total,
        snap.anonymous + snap.books.fold(0, (a, b) => a + b.milliseconds),
      );
    },
  );
  test(
    'missing or corrupt book metadata never becomes anonymous reading',
    () async {
      final s = value(await repo.begin(book))!;
      await repo.submit(ReadingCheckpoint(s, 1, {20261021: 30000}));
      var result = value(
        await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
      );
      expect(result.books.single.summary, isNull);
      expect(result.anonymous, 0);
      await db.customStatement(
        "INSERT INTO bookshelf VALUES('source','book','invalid-json',0,0)",
      );
      expect(
        await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
        isA<Failure>(),
      );
    },
  );
}
