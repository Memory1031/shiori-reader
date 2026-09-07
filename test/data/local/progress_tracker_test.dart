import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/position/progress_tracker.dart';

void main() {
  test(
    'tracker persists to SQLite, retries rollback and retains latest record after reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('shiori-progress-');
      final path = File('${dir.path}/users.sqlite');
      var db = UserDatabase(NativeDatabase(path));
      var library = LocalLibraryRepository(db);
      final content = const FixtureData().content(
        FixtureScenario.extremeParagraph,
      );
      final tracker = ProgressTracker(
        library: library,
        content: content,
        snapshot: const FixtureData().summary(FixtureScenario.extremeParagraph),
        ordinal: 0,
        catalogRevision: 'catalog',
      );
      ReaderPosition at(double fraction) => ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks.first.blockKey,
        blockIndex: 0,
        blockFraction: fraction,
        chapterFraction: fraction,
      );
      await tracker.start();
      await db.customStatement(
        "CREATE TRIGGER reject_progress BEFORE INSERT ON reading_progress BEGIN SELECT RAISE(ABORT, 'fixture'); END",
      );
      tracker.sample(at(.5), completed: false);
      await tracker.flush();
      expect(tracker.unsaved, isTrue);
      expect(
        (await library.getProgress(
                  content.key.novelKey,
                  cancellation: CancellationSource().token,
                )
                as Success<ReadingProgress?>)
            .value,
        isNull,
      );
      await db.customStatement('DROP TRIGGER reject_progress');
      tracker.sample(at(.8), completed: true);
      await tracker.retry();
      expect(tracker.unsaved, isFalse);
      await tracker.close();
      await db.close();
      db = UserDatabase(NativeDatabase(path));
      library = LocalLibraryRepository(db);
      final saved =
          (await library.getProgress(
                    content.key.novelKey,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value!;
      expect(saved.position.blockFraction, .8);
      expect(saved.completed, isTrue);
      await db.close();
      await dir.delete(recursive: true);
    },
  );
}
