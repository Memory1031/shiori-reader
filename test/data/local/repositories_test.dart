import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/local_guard.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/local/preferences_settings_store.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/app_logger.dart';

CancellationToken token() => CancellationSource().token;
T value<T>(Result<T> result) => (result as Success<T>).value;
NovelSummary summary(String source) => NovelSummary(
  key: NovelKey(sourceId: SourceId(source), novelId: 'same'),
  title: 'Book',
);
ReadingProgress progress(NovelSummary book, int index) => ReadingProgress(
  snapshot: book,
  chapterKey: ChapterKey(novelKey: book.key, chapterId: 'chapter'),
  chapterOrdinalSnapshot: 0,
  catalogRevision: 'catalog',
  position: ReaderPosition(
    contentRevision: 'revision',
    blockKey: 'block',
    blockIndex: index,
    blockFraction: .25,
    chapterFraction: .5,
  ),
  completed: false,
  lastReadAt: DateTime.utc(2026, 9, 7, 0, 0, index),
);

class Preferences implements SharedPreferencesAsync {
  final data = <String, Object>{};
  bool get fail => data['testFailure'] == true;
  set fail(bool value) => data['testFailure'] = value;
  @override
  Future<String?> getString(String key) async => data[key] as String?;
  @override
  Future<void> setString(String key, String value) async {
    if (fail) throw StateError('secret path');
    data[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'shelf idempotency, cross-source identities, ordered streams, history isolation',
    () async {
      final db = UserDatabase(NativeDatabase.memory());
      final repo = LocalLibraryRepository(db);
      final a = summary('a'), b = summary('b');
      final events = <Result<List<BookshelfEntry>>>[];
      final sub = repo.watchBookshelf().listen(events.add);
      await repo.watchBookshelf().first;
      final first = BookshelfEntry(snapshot: a, addedAt: DateTime.utc(2026));
      expect(
        value(await repo.putBookshelf(first, cancellation: token())),
        first,
      );
      expect(
        value(
          await repo.putBookshelf(
            BookshelfEntry(snapshot: a, addedAt: DateTime.utc(2030)),
            cancellation: token(),
          ),
        ).addedAt,
        first.addedAt,
      );
      await repo.putBookshelf(
        BookshelfEntry(snapshot: b, addedAt: DateTime.utc(2027)),
        cancellation: token(),
      );
      final generation = value(
        await repo.beginProgressSession(a.key, cancellation: token()),
      );
      expect(
        value(
          await repo.saveProgress(
            progress(a, 1),
            stamp: ProgressWriteStamp(generation: generation, sequence: 1),
            cancellation: token(),
          ),
        ),
        true,
      );
      final books = value(await repo.watchBookshelf().first);
      expect(books.map((e) => e.snapshot.key), [b.key, a.key]);
      expect(() => books.clear(), throwsUnsupportedError);
      expect(
        value(await repo.removeFromBookshelf(a.key, cancellation: token())),
        first,
      );
      expect(
        value(await repo.getProgress(a.key, cancellation: token())),
        progress(a, 1),
      );
      await repo.clearHistory(a.key, cancellation: token());
      expect(
        value(
          await repo.saveProgress(
            progress(a, 2),
            stamp: ProgressWriteStamp(generation: generation, sequence: 2),
            cancellation: token(),
          ),
        ),
        false,
      );
      expect(
        value(await repo.getProgress(a.key, cancellation: token())),
        isNull,
      );
      expect(value(await repo.watchBookshelf().first).single.snapshot, b);
      await sub.cancel();
      expect(events, isNotEmpty);
      await db.close();
    },
  );
  test(
    'transaction rollback, cancellation and SQL failure do not advance accepted sequence',
    () async {
      final db = UserDatabase(NativeDatabase.memory());
      final repo = LocalLibraryRepository(db);
      final book = summary('s');
      final gen = value(
        await repo.beginProgressSession(book.key, cancellation: token()),
      );
      await db.customStatement(
        "CREATE TRIGGER reject_progress BEFORE INSERT ON reading_progress BEGIN SELECT RAISE(ABORT,'secret SQL'); END",
      );
      expect(
        await repo.saveProgress(
          progress(book, 1),
          stamp: ProgressWriteStamp(generation: gen, sequence: 5),
          cancellation: token(),
        ),
        isA<Failure<bool>>(),
      );
      await db.customStatement('DROP TRIGGER reject_progress');
      expect(
        value(
          await repo.saveProgress(
            progress(book, 1),
            stamp: ProgressWriteStamp(generation: gen, sequence: 1),
            cancellation: token(),
          ),
        ),
        true,
      );
      final cancelled = CancellationSource();
      final rollback = await localWrite(
        db,
        Operation.libraryWrite,
        cancelled.token,
        () async {
          await db.customStatement('DELETE FROM reading_progress');
          cancelled.cancel();
          return true;
        },
      );
      expect((rollback as Failure<bool>).failure.kind, FailureKind.cancelled);
      expect(
        value(await repo.getProgress(book.key, cancellation: token())),
        progress(book, 1),
      );
      final results = await Future.wait([
        repo.saveProgress(
          progress(book, 3),
          stamp: ProgressWriteStamp(generation: gen, sequence: 3),
          cancellation: token(),
        ),
        repo.saveProgress(
          progress(book, 2),
          stamp: ProgressWriteStamp(generation: gen, sequence: 2),
          cancellation: token(),
        ),
      ]);
      expect(results.map(value), [true, false]);
      expect(
        value(
          await repo.getProgress(book.key, cancellation: token()),
        )!.position.blockIndex,
        3,
      );
      await db.close();
    },
  );
  test(
    'persistent generations survive reopening and clear-history tombstones reject old writers',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'shiori-repository-test-',
      );
      final paths = AppPaths(
        support: temp,
        temporary: temp,
        environment: StorageEnvironment.development,
      );
      var db = value(await LocalDatabases.open(paths));
      var repo = LocalLibraryRepository(db.users);
      final book = summary('s');
      final generation = value(
        await repo.beginProgressSession(book.key, cancellation: token()),
      );
      await repo.putBookshelf(
        BookshelfEntry(snapshot: book, addedAt: DateTime.utc(2026)),
        cancellation: token(),
      );
      await repo.saveProgress(
        progress(book, 4),
        stamp: ProgressWriteStamp(generation: generation, sequence: 4),
        cancellation: token(),
      );
      await db.close();
      db = value(await LocalDatabases.open(paths));
      repo = LocalLibraryRepository(db.users);
      expect(
        value(await repo.getProgress(book.key, cancellation: token())),
        progress(book, 4),
      );
      final next = value(
        await repo.beginProgressSession(book.key, cancellation: token()),
      );
      expect(next, greaterThan(generation));
      expect(
        value(
          await repo.saveProgress(
            progress(book, 9),
            stamp: ProgressWriteStamp(generation: generation, sequence: 99),
            cancellation: token(),
          ),
        ),
        false,
      );
      await repo.clearHistory(book.key, cancellation: token());
      await db.close();
      db = value(await LocalDatabases.open(paths));
      repo = LocalLibraryRepository(db.users);
      expect(
        value(await repo.getProgress(book.key, cancellation: token())),
        isNull,
      );
      expect(
        value(
          await repo.saveProgress(
            progress(book, 8),
            stamp: ProgressWriteStamp(generation: next, sequence: 100),
            cancellation: token(),
          ),
        ),
        false,
      );
      expect(value(await repo.watchBookshelf().first), hasLength(1));
      await db.close();
      expect(temp.parent.absolute.path, Directory.systemTemp.absolute.path);
      await temp.delete(recursive: true);
    },
  );
  test(
    'normalized detail/catalog/chapter roundtrip, atomic replacement and corrupt row isolation',
    () async {
      final db = CacheDatabase(NativeDatabase.memory());
      final store = NovelRecordStore(db);
      const data = FixtureData();
      final detail = NovelDetail(
        summary: data.summary(FixtureScenario.shortChapter),
        synopsis: 'Summary',
        tags: ['test'],
      );
      final catalog = data.catalog(FixtureScenario.shortChapter);
      final chapter = data.content(FixtureScenario.shortChapter);
      expect(
        value(
          await store.readDetail(detail.summary.key, cancellation: token()),
        ),
        isNull,
      );
      expect(
        await store.writeDetail(
          detail,
          fetchedAt: fixtureEpoch,
          parserVersion: 1,
          cancellation: token(),
        ),
        isA<Success<void>>(),
      );
      expect(
        await store.writeCatalog(
          catalog,
          fetchedAt: fixtureEpoch,
          parserVersion: 1,
          cancellation: token(),
        ),
        isA<Success<void>>(),
      );
      expect(
        await store.writeChapter(
          chapter,
          fetchedAt: fixtureEpoch,
          parserVersion: 1,
          cancellation: token(),
        ),
        isA<Success<void>>(),
      );
      expect(
        value(
          await store.readDetail(detail.summary.key, cancellation: token()),
        )!.value,
        detail,
      );
      expect(
        value(
          await store.readCatalog(catalog.novelKey, cancellation: token()),
        )!.value,
        catalog,
      );
      expect(
        value(
          await store.readChapter(chapter.key, cancellation: token()),
        )!.value,
        chapter,
      );
      await db.customStatement(
        "CREATE TRIGGER reject_update BEFORE UPDATE ON chapter_cache BEGIN SELECT RAISE(ABORT,'full'); END",
      );
      final revised = data.content(FixtureScenario.shortChapter, revision: 1);
      expect(
        await store.writeChapter(
          revised,
          fetchedAt: fixtureEpoch,
          parserVersion: 2,
          cancellation: token(),
        ),
        isA<Failure<void>>(),
      );
      expect(
        value(
          await store.readChapter(chapter.key, cancellation: token()),
        )!.value,
        chapter,
      );
      await db.customStatement("UPDATE novel_cache SET payload='broken'");
      expect(
        await store.readDetail(detail.summary.key, cancellation: token()),
        isA<Failure<StoredRecord<NovelDetail>?>>(),
      );
      expect(
        value(
          await store.readChapter(chapter.key, cancellation: token()),
        )!.value,
        chapter,
      );
      await db.close();
    },
  );
  test(
    'settings version/defaults, serialization, environment isolation and failures',
    () async {
      final prefs = Preferences(), logger = AppLogger();
      final paths = AppPaths(
        support: Directory('unused'),
        temporary: Directory('unused'),
        environment: StorageEnvironment.development,
      );
      final store = PreferencesSettingsStore(
        preferences: prefs,
        paths: paths,
        logger: logger,
      );
      expect(value(await store.load(cancellation: token())), ReaderSettings());
      for (final bad in [
        'not json',
        '{"schemaVersion":999}',
        '{"schemaVersion":1,"fontSize":900}',
      ]) {
        prefs.data[paths.settingsKey] = bad;
        expect(
          value(await store.load(cancellation: token())),
          ReaderSettings(),
        );
        expect(prefs.data[paths.settingsKey], bad);
      }
      prefs.data[paths.settingsKey] = 123;
      expect(value(await store.load(cancellation: token())), ReaderSettings());
      final settings = ReaderSettings(
        fontSize: 28,
        themeMode: ReaderThemeMode.dark,
      );
      expect(
        await store.save(settings, cancellation: token()),
        isA<Success<void>>(),
      );
      expect(
        value(
          await PreferencesSettingsStore(
            preferences: prefs,
            paths: paths,
            logger: logger,
          ).load(cancellation: token()),
        ),
        settings,
      );
      prefs.fail = true;
      expect(
        await store.save(ReaderSettings(), cancellation: token()),
        isA<Failure<void>>(),
      );
      expect(value(await store.load(cancellation: token())), settings);
      expect(logger.events.toString(), isNot(contains('secret')));
      final cancelled = CancellationSource()..cancel();
      expect(
        (await store.save(settings, cancellation: cancelled.token) as Failure)
            .failure
            .isCancellation,
        true,
      );
    },
  );
}
