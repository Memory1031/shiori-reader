import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/data/repositories/reading_statistics_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'managed_local_books_test.dart' show fixture;

T ok<T>(Result<T> result) => (result as Success<T>).value;
CancellationToken token() => CancellationSource().token;
void main() {
  test(
    'file-backed statistics survive reparse, cache removal and reopen; deletion anonymizes permanently',
    () async {
      final root = await Directory.systemTemp.createTemp('shiori-statistics-');
      final paths = AppPaths(
        support: root,
        temporary: root,
        environment: StorageEnvironment.development,
      );
      await paths.prepare();
      var db = UserDatabase(NativeDatabase(paths.userDatabase));
      var store = ok(await ManagedLocalBooks.open(paths, db));
      var repo = LocalReadingStatisticsRepository(db);
      addTearDown(() async {
        await store.close();
        await db.close();
        await root.delete(recursive: true);
      });
      Future<LocalBookImportResult> import() async => ok(
        await store.importBook(
          bytes: Stream.value(utf8.encode('第一章\n真实原件用于统计生命周期测试。')),
          format: LocalBookFormat.txt,
          parse: (s) async => fixture(s),
          addToShelf: true,
          cancellation: token(),
        ),
      );
      final imported = await import(),
          key = imported.book.content.detail.summary.key;
      final session = ok(await repo.begin(key))!;
      expect(
        ok(await repo.submit(ReadingCheckpoint(session, 1, {20261021: 15000}))),
        true,
      );
      ok(
        await store.reparseBook(
          key,
          chooseEncoding: (_) async => TxtEncoding.utf8,
          cancellation: token(),
        ),
      );
      expect(
        ok(await repo.submit(ReadingCheckpoint(session, 2, {20261021: 5000}))),
        true,
      );
      await paths.disposable.delete(recursive: true);
      await repo.setEnabled(false);
      await store.close();
      await db.close();
      db = UserDatabase(NativeDatabase(paths.userDatabase));
      store = ok(await ManagedLocalBooks.open(paths, db));
      repo = LocalReadingStatisticsRepository(db);
      expect(ok(await repo.settings()).enabled, false);
      var snap = ok(
        await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
      );
      expect(snap.total, 20000);
      expect(snap.anonymous, 0);
      expect(snap.books.single.key, key);
      ok(await repo.setEnabled(true));
      final old = ok(await repo.begin(key))!;
      ok(await store.deleteBook(key, cancellation: token()));
      final replacement = await import();
      expect(replacement.book.content.detail.summary.key, key);
      expect(
        ok(await repo.submit(ReadingCheckpoint(old, 1, {20261021: 9000}))),
        false,
      );
      final fresh = ok(await repo.begin(key))!;
      expect(
        ok(await repo.submit(ReadingCheckpoint(fresh, 1, {20261021: 3000}))),
        true,
      );
      snap = ok(
        await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
      );
      expect(snap.total, 23000);
      expect(snap.anonymous, 20000);
      expect(snap.books.single.milliseconds, 3000);
      ok(await repo.clear());
      expect(ok(await store.read(key, cancellation: token())), isNotNull);
      expect(ok(await repo.settings()).enabled, true);
    },
  );
}
