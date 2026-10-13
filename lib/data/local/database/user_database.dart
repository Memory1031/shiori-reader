import 'dart:async';
import 'package:drift/drift.dart';
part 'user_database.g.dart';

@DriftDatabase(include: {'users.drift'})
class UserDatabase extends _$UserDatabase {
  UserDatabase(super.executor);
  final _removals = StreamController<(String, String)>.broadcast(sync: true);
  Stream<(String, String)> get removedBooks => _removals.stream;
  Future<int> removalGeneration(String source, String novel) async =>
      (await customSelect(
        'SELECT removal_generation FROM progress_sessions WHERE source_id=? AND novel_id=?',
        variables: [Variable(source), Variable(novel)],
      ).getSingleOrNull())?.read<int>('removal_generation') ??
      0;
  void notifyRemoved(String source, String novel) =>
      _removals.add((source, novel));
  @override
  Future<void> close() async {
    await super.close();
    await _removals.close();
  }

  @override
  int get schemaVersion => 8;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Never silently recreate user or cache files on an unknown version.
    onUpgrade: (m, from, to) async {
      if (from < 1 || from > 7 || to != 8) {
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
        if (from < 6) await m.createTable(progressCatalogs);
        if (from < 7) await m.createTable(localReparseAttempts);
        await customStatement(
          'ALTER TABLE progress_sessions ADD COLUMN removal_generation INTEGER NOT NULL DEFAULT 0 CHECK(removal_generation >= 0)',
        );
        await repairOnlineOwnership();
        await _checkIntegrity();
        // Commit DDL and the version together; Drift's subsequent assignment
        // is idempotent if opening completes normally.
        await customStatement('PRAGMA user_version=$to');
      });
    },
    beforeOpen: (_) => _checkIntegrity(),
  );

  /// Runs once before any Reader is active; session tombstones stay intact.
  Future<void> repairOnlineOwnership() async {
    await customStatement(
      'INSERT INTO bookshelf(source_id,novel_id,summary_json,added_at,updated_at) '
      'SELECT source_id,novel_id,summary_json,last_read_at,updated_at FROM reading_progress '
      'WHERE source_id<>? AND position_version=1 ON CONFLICT(source_id,novel_id) DO NOTHING',
      ['local'],
    );
    for (final table in ['progress_catalogs', 'prefetch_choices']) {
      await customStatement(
        'DELETE FROM $table WHERE source_id<>? '
        'AND NOT EXISTS(SELECT 1 FROM bookshelf b WHERE b.source_id=$table.source_id AND b.novel_id=$table.novel_id) '
        'AND NOT EXISTS(SELECT 1 FROM reading_progress r WHERE r.source_id=$table.source_id AND r.novel_id=$table.novel_id)',
        ['local'],
      );
    }
  }

  Future<void> _checkIntegrity() async {
    final result = await customSelect('PRAGMA quick_check').get();
    if (result.length != 1 || result.single.data.values.single != 'ok') {
      throw StateError('Database integrity check failed');
    }
  }
}
