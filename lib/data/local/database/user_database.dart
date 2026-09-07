import 'package:drift/drift.dart';
part 'user_database.g.dart';

@DriftDatabase(include: {'users.drift'})
class UserDatabase extends _$UserDatabase {
  UserDatabase(super.executor);
  @override
  int get schemaVersion => 2;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Never silently recreate user or cache files on an unknown version.
    onUpgrade: (m, from, to) async {
      if (from != 1 || to != 2) {
        throw StateError('Unsupported database version');
      }
      await m.createTable(prefetchChoices);
      await m.createTable(prefetchSettings);
    },
    beforeOpen: (_) async {
      final result = await customSelect('PRAGMA quick_check').get();
      if (result.length != 1 || result.single.data.values.single != 'ok') {
        throw StateError('Database integrity check failed');
      }
    },
  );
}
