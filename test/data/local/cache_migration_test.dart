import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/data/local/database/user_database.dart';

void main() {
  test(
    'v1 upgrades preserve old cache and user rows; new tables are independent',
    () async {
      final cacheSql = File(
        'lib/data/local/database/cache.drift',
      ).readAsStringSync().split('CREATE TABLE image_cache').first;
      final userSql = File('lib/data/local/database/users.drift')
          .readAsStringSync()
          .replaceAll(' book_progress TEXT,', '')
          .split('CREATE TABLE prefetch_choices')
          .first;
      final cache = CacheDatabase(
        NativeDatabase.memory(
          setup: (db) {
            db.execute(cacheSql);
            db.execute(
              "INSERT INTO chapter_cache VALUES('s','n','c','old',1,1,1,NULL,1,3)",
            );
            db.execute('PRAGMA user_version=1');
          },
        ),
      );
      final users = UserDatabase(
        NativeDatabase.memory(
          setup: (db) {
            db.execute(userSql);
            db.execute("INSERT INTO bookshelf VALUES('s','n','keep',1,1)");
            db.execute('PRAGMA user_version=1');
          },
        ),
      );
      expect(
        (await cache
                .customSelect('SELECT payload FROM chapter_cache')
                .getSingle())
            .read<String>('payload'),
        'old',
      );
      expect(
        (await users
                .customSelect('SELECT summary_json FROM bookshelf')
                .getSingle())
            .read<String>('summary_json'),
        'keep',
      );
      expect(
        await cache.customSelect('SELECT * FROM image_cache').get(),
        isEmpty,
      );
      expect(
        await users.customSelect('SELECT * FROM prefetch_choices').get(),
        isEmpty,
      );
      expect(
        (await users.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        6,
      );
      await cache.close();
      await users.close();
    },
  );
}
