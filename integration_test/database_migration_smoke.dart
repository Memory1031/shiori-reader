// DB-003: explicit entry only, no Source requests or production database access.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/local/database/cache_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = await Directory(
    (await getTemporaryDirectory()).path,
  ).createTemp('db003-');
  final report = <String, Object?>{};
  try {
    final snapshots = {
      'user1': const String.fromEnvironment('DB003_USER_1'),
      'user2': const String.fromEnvironment('DB003_USER_2'),
      'cache1': const String.fromEnvironment('DB003_CACHE_1'),
    };
    for (final entry in snapshots.entries) {
      final file = File('${root.path}/${entry.key}.sqlite');
      final raw = sql.sqlite3.open(file.path);
      try {
        final snapshot =
            jsonDecode(utf8.decode(base64Decode(entry.value)))
                as Map<String, dynamic>;
        for (final entity in snapshot['fixed_sql'] as List) {
          raw.execute(
            (entity['sql'] as List).singleWhere(
                  (s) => s['dialect'] == 'sqlite',
                )['sql']
                as String,
          );
        }
        raw.execute('PRAGMA user_version=${entry.key.endsWith('2') ? 2 : 1}');
        if (entry.key.startsWith('user')) {
          raw.execute(
            "INSERT INTO bookshelf VALUES('fixture','book','retained',123,456)",
          );
          raw.execute(
            "INSERT INTO progress_sessions VALUES('fixture','book',3,8)",
          );
        } else {
          raw.execute(
            "INSERT INTO chapter_cache VALUES('s','n','c','retained',1,1,123,NULL,123,8)",
          );
        }
      } finally {
        raw.close();
      }
      final db = entry.key.startsWith('user')
          ? UserDatabase(NativeDatabase.createInBackground(file))
          : CacheDatabase(NativeDatabase.createInBackground(file));
      try {
        final expected = entry.key.startsWith('user') ? 3 : 2;
        final version =
            (await db.customSelect('PRAGMA user_version').getSingle())
                .data
                .values
                .single;
        if (version != expected) throw StateError('version');
        final table = entry.key.startsWith('user')
            ? 'bookshelf'
            : 'chapter_cache';
        final column = entry.key.startsWith('user')
            ? 'summary_json'
            : 'payload';
        if ((await db.customSelect('SELECT $column FROM $table').getSingle())
                .read<String>(column) !=
            'retained') {
          throw StateError('rows');
        }
      } finally {
        await db.close();
      }
      final reopened = sql.sqlite3.open(file.path);
      try {
        if (reopened.userVersion != (entry.key.startsWith('user') ? 3 : 2)) {
          throw StateError('reopen');
        }
      } finally {
        reopened.close();
      }
      report[entry.key] = 'PASS';
    }
    report['status'] = 'PASS';
  } catch (error) {
    report['status'] = 'FAIL';
    report['type'] = error.runtimeType.toString();
  } finally {
    await root.delete(recursive: true);
  }
  await File(
    '${(await getApplicationSupportDirectory()).path}/db003-report.json',
  ).writeAsString(jsonEncode(report));
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text('DB003 ${report['status']}'))),
    ),
  );
}
