import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/domain/contracts/contracts.dart';

import 'managed_local_books_test.dart' show fixture;

enum _Fault { rollback, lostReply, unreadableReference, changedHash }

class _FaultDatabase extends UserDatabase {
  _FaultDatabase(super.executor);
  _Fault? fault;
  bool unreadable = false;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) async {
    final current = fault;
    fault = null;
    final value = await super.transaction(() async {
      final value = await action();
      if (current == _Fault.rollback) throw StateError('Rollback');
      return value;
    }, requireNew: requireNew);
    if (current == _Fault.changedHash) {
      await customStatement('UPDATE local_books SET manifest_hash=?', [
        '0' * 64,
      ]);
    }
    if (current != null) {
      unreadable = current == _Fault.unreadableReference;
      throw StateError('Lost commit reply');
    }
    return value;
  }

  @override
  Selectable<QueryRow> customSelect(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation> readsFrom = const {},
  }) {
    if (unreadable && query.contains('FROM local_books')) {
      throw StateError('Reference unavailable');
    }
    return super.customSelect(
      query,
      variables: variables,
      readsFrom: readsFrom,
    );
  }
}

void main() {
  for (final fault in _Fault.values) {
    test('published import cleanup respects ${fault.name}', () async {
      final root = await Directory.systemTemp.createTemp('import-publication-');
      final paths = AppPaths(
        support: root,
        temporary: root,
        environment: StorageEnvironment.development,
      );
      await paths.prepare();
      final db = _FaultDatabase(NativeDatabase(paths.userDatabase));
      var store =
          (await ManagedLocalBooks.open(paths, db)
                  as Success<ManagedLocalBooks>)
              .value;
      final bytes = utf8.encode('Durable original');
      final digest = sha256.convert(bytes).toString();
      final directory = Directory('${paths.localBooks.path}/$digest');
      var parses = 0;
      Future<Result<LocalBookRecord>> import() => store.importBook(
        bytes: Stream.value(bytes),
        format: LocalBookFormat.txt,
        parse: (session) async {
          parses++;
          return fixture(session);
        },
        addToShelf: true,
        cancellation: CancellationSource().token,
      );
      try {
        db.fault = fault;
        expect(await import(), isA<Failure>());
        expect(await directory.exists(), fault != _Fault.rollback);
        expect(await paths.localImportStaging.list().toList(), isEmpty);
        db.unreadable = false;
        final rows = await db.customSelect('SELECT * FROM local_books').get();
        expect(rows.length, fault == _Fault.rollback ? 0 : 1);
        if (fault != _Fault.rollback) {
          expect(await File('${directory.path}/original').readAsBytes(), bytes);
        }
        await store.close();
        store =
            (await ManagedLocalBooks.open(paths, db)
                    as Success<ManagedLocalBooks>)
                .value;
        if (fault == _Fault.changedHash) {
          expect(await directory.exists(), isTrue);
          expect(await import(), isA<Failure>());
          expect(parses, 1);
        } else {
          final retry = (await import() as Success<LocalBookRecord>).value;
          expect(retry.content.detail.summary.key.novelId, digest);
          expect(parses, fault == _Fault.rollback ? 2 : 1);
          expect(
            await store.read(
              retry.content.detail.summary.key,
              cancellation: CancellationSource().token,
            ),
            isA<Success<LocalBookRecord?>>(),
          );
        }
      } finally {
        db.unreadable = false;
        await store.close();
        await db.close();
        await root.delete(recursive: true);
      }
    });
  }
}
