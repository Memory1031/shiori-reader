import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/domain/contracts/contracts.dart';

void main() {
  test('v1 tables, indexes, constraints and user/cache separation', () async {
    final users = UserDatabase(NativeDatabase.memory());
    final cache = CacheDatabase(NativeDatabase.memory());
    final names =
        (await users
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table'",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(
      names,
      containsAll(['bookshelf', 'reading_progress', 'progress_sessions']),
    );
    expect(names.any((n) => n.endsWith('_cache')), false);
    expect(
      (await cache
              .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
              .get())
          .length,
      5,
    );
    expect(
      (await users.customSelect('PRAGMA foreign_key_list(bookshelf)').get()),
      isEmpty,
    );
    expect(
      (await users.customSelect('PRAGMA index_list(reading_progress)').get())
          .any((r) => r.read<String>('name') == 'progress_recent'),
      true,
    );
    await expectLater(
      users.customStatement(
        "INSERT INTO progress_sessions VALUES('s','n',0,-1)",
      ),
      throwsA(anything),
    );
    await users.close();
    await cache.close();
  });
  test(
    'background database reopens, paths isolate dev, bad roots and future schema preserve files',
    () async {
      final temp = await Directory.systemTemp.createTemp('shiori-db-test-');
      final paths = AppPaths(
        support: temp,
        temporary: temp,
        environment: StorageEnvironment.development,
      );
      expect(
        paths.userDatabase.path,
        isNot(
          AppPaths(
            support: temp,
            temporary: temp,
            environment: StorageEnvironment.production,
          ).userDatabase.path,
        ),
      );
      var result = await LocalDatabases.open(paths);
      final first = (result as Success<LocalDatabases>).value;
      await first.users.customStatement(
        "INSERT INTO progress_sessions VALUES('s','n',4,7)",
      );
      await first.close();
      result = await LocalDatabases.open(paths);
      final reopened = (result as Success<LocalDatabases>).value;
      expect(
        (await reopened.users
                .customSelect('SELECT generation FROM progress_sessions')
                .getSingle())
            .read<int>('generation'),
        4,
      );
      await reopened.users.customStatement('PRAGMA user_version=999');
      await reopened.close();
      expect(await LocalDatabases.open(paths), isA<Failure<LocalDatabases>>());
      expect(await paths.userDatabase.exists(), true);
      final bad = File('${temp.path}/not-a-directory');
      await bad.writeAsString('keep');
      expect(
        await LocalDatabases.open(
          AppPaths(
            support: Directory(bad.path),
            temporary: temp,
            environment: StorageEnvironment.development,
          ),
        ),
        isA<Failure<LocalDatabases>>(),
      );
      expect(await bad.readAsString(), 'keep');
      // Delete only this newly created, explicitly verified temporary test root.
      expect(temp.parent.absolute.path, Directory.systemTemp.absolute.path);
      await temp.delete(recursive: true);
    },
  );
}
