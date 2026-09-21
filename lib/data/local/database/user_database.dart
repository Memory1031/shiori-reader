import 'package:drift/drift.dart';
part 'user_database.g.dart';

@DriftDatabase(include: {'users.drift'})
class UserDatabase extends _$UserDatabase {
  UserDatabase(super.executor);
  @override
  int get schemaVersion => 6;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Never silently recreate user or cache files on an unknown version.
    onUpgrade: (m, from, to) async {
      if (from < 1 || from > 5 || to != 6) {
        throw StateError('Unsupported database version');
      }
      await transaction(() async {
        await _checkIntegrity();
        if (from < 2) {
          await m.createTable(prefetchChoices);
          await m.createTable(prefetchSettings);
        }
        if (from < 3) {
          await m.createTable(localBooks);
        } else if (from < 4) {
          await customStatement(
            'ALTER TABLE local_books ADD COLUMN active_bundle TEXT',
          );
          await customStatement(
            'ALTER TABLE local_books ADD COLUMN parser_version INTEGER NOT NULL DEFAULT 1',
          );
          await customStatement(
            'ALTER TABLE local_books ADD COLUMN maintenance INTEGER NOT NULL DEFAULT 0 CHECK(maintenance IN (0,1))',
          );
        }
        if (from < 4) await m.createTable(localChapterRevisions);
        if (from < 5) {
          await customStatement(
            'ALTER TABLE reading_progress ADD COLUMN book_progress TEXT',
          );
        }
        await m.createTable(progressCatalogs);
        await _checkIntegrity();
        // Commit DDL and the version together; Drift's subsequent assignment
        // is idempotent if opening completes normally.
        await customStatement('PRAGMA user_version=$to');
      });
    },
    beforeOpen: (_) => _checkIntegrity(),
  );

  Future<void> _checkIntegrity() async {
    final result = await customSelect('PRAGMA quick_check').get();
    if (result.length != 1 || result.single.data.values.single != 'ok') {
      throw StateError('Database integrity check failed');
    }
  }
}
