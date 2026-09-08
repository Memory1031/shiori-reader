import 'package:drift/drift.dart';
part 'user_database.g.dart';

@DriftDatabase(include: {'users.drift'})
class UserDatabase extends _$UserDatabase {
  UserDatabase(super.executor);
  @override
  int get schemaVersion => 3;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Never silently recreate user or cache files on an unknown version.
    onUpgrade: (m, from, to) async {
      if (from < 1 || from > 2 || to != 3) {
        throw StateError('Unsupported database version');
      }
      await transaction(() async {
        await _checkIntegrity();
        if (from < 2) {
          await m.createTable(prefetchChoices);
          await m.createTable(prefetchSettings);
        }
        await m.createTable(localBooks);
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
