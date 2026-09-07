import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/local/preferences_settings_store.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/app_logger.dart';

T value<T>(Result<T> result) => (result as Success<T>).value;
void check(bool condition) {
  if (!condition) throw StateError('DB probe mismatch');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await AppPaths.resolve(StorageEnvironment.development);
  var databases = value(await LocalDatabases.open(paths));
  var library = LocalLibraryRepository(databases.users);
  final settings = PreferencesSettingsStore(
    preferences: SharedPreferencesAsync(),
    paths: paths,
    logger: AppLogger(),
  );
  final token = CancellationSource().token;
  const data = FixtureData();
  final book = data.summary(FixtureScenario.shortChapter);
  final chapter = data.content(FixtureScenario.shortChapter);
  final old = value(await library.getProgress(book.key, cancellation: token));
  final hadPrior = old != null;
  if (hadPrior) {
    check(old.position.blockIndex == 3);
    check(value(await settings.load(cancellation: token)).fontSize == 26);
    check(
      value(
            await NovelRecordStore(
              databases.cache,
            ).readChapter(chapter.key, cancellation: token),
          )!.value ==
          chapter,
    );
  }
  final generation = value(
    await library.beginProgressSession(book.key, cancellation: token),
  );
  value(
    await library.putBookshelf(
      BookshelfEntry(snapshot: book, addedAt: fixtureEpoch),
      cancellation: token,
    ),
  );
  final progress = ReadingProgress(
    snapshot: book,
    chapterKey: chapter.key,
    chapterOrdinalSnapshot: 0,
    catalogRevision: 'probe',
    position: ReaderPosition(
      contentRevision: chapter.contentRevision,
      blockKey: chapter.blocks.first.blockKey,
      blockIndex: 3,
      blockFraction: .25,
      chapterFraction: .5,
    ),
    completed: false,
    lastReadAt: fixtureEpoch,
  );
  check(
    value(
      await library.saveProgress(
        progress,
        stamp: ProgressWriteStamp(generation: generation, sequence: 5),
        cancellation: token,
      ),
    ),
  );
  check(
    !value(
      await library.saveProgress(
        progress,
        stamp: ProgressWriteStamp(generation: generation, sequence: 4),
        cancellation: token,
      ),
    ),
  );
  value(
    await NovelRecordStore(databases.cache).writeChapter(
      chapter,
      fetchedAt: fixtureEpoch,
      parserVersion: 1,
      cancellation: token,
    ),
  );
  value(await settings.save(ReaderSettings(fontSize: 26), cancellation: token));
  await databases.close();
  databases = value(await LocalDatabases.open(paths));
  library = LocalLibraryRepository(databases.users);
  check(
    value(await library.getProgress(book.key, cancellation: token)) == progress,
  );
  check(value(await library.watchBookshelf().first).isNotEmpty);
  await databases.close();
  final message =
      'DB_PASS coldExisting=$hadPrior generation=$generation reopen=true settings=26 staleWriteRejected=true';
  debugPrint(message);
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(child: Center(child: Text(message))),
      ),
    ),
  );
}
