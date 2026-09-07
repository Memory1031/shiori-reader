import 'package:drift/drift.dart';
part 'user_database.g.dart';

@DriftDatabase(include: {'users.drift'})
class UserDatabase extends _$UserDatabase {
  UserDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Never silently recreate user or cache files on an unknown version.
    onUpgrade: (m, from, to) async =>
        throw StateError('Unsupported database version'),
    beforeOpen: (_) async {
      final result = await customSelect('PRAGMA quick_check').get();
      if (result.length != 1 || result.single.data.values.single != 'ok') {
        throw StateError('Database integrity check failed');
      }
    },
  );
}
