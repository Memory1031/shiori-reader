import 'package:drift/drift.dart';
part 'cache_database.g.dart';

@DriftDatabase(include: {'cache.drift'})
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase(super.executor);
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
      await m.createTable(imageCache);
      await m.createTable(imageOwners);
      await customStatement(
        'CREATE INDEX image_access ON image_cache(last_access_at)',
      );
    },
    beforeOpen: (_) async {
      final result = await customSelect('PRAGMA quick_check').get();
      if (result.length != 1 || result.single.data.values.single != 'ok') {
        throw StateError('Database integrity check failed');
      }
    },
  );
}
