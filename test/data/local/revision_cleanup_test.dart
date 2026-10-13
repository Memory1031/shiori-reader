import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/domain/contracts/contracts.dart';

import 'managed_local_books_test.dart' show fixture;

final class _ManifestReads extends IOOverrides {
  final _origin = Zone.current;
  final reads = <String>[];
  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) =>
      _origin.run(() => FileSystemEntity.type(path, followLinks: followLinks));
  @override
  File createFile(String path) => _ObservedFile(super.createFile(path), reads);
}

class _ObservedFile implements File {
  _ObservedFile(this.file, this.reads);
  final File file;
  final List<String> reads;
  @override
  String get path => file.path;
  @override
  File get absolute => file.absolute;
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);
  @override
  Future<String> resolveSymbolicLinks() => file.resolveSymbolicLinks();
  @override
  Future<int> length() => file.length();
  @override
  Future<Uint8List> readAsBytes() {
    reads.add(file.path);
    return file.readAsBytes();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final scenario in [
    'cleanRoot',
    'activeOnly',
    'oldRoot',
    'oldRevision',
    'badHash',
    'badPointer',
  ]) {
    test(
      'startup cleanup reads manifests only before deletion: $scenario',
      () async {
        final temp = await Directory.systemTemp.createTemp('revision-cleanup-');
        final paths = AppPaths(
          support: temp,
          temporary: temp,
          environment: StorageEnvironment.development,
        );
        await paths.prepare();
        final db = UserDatabase(NativeDatabase(paths.userDatabase));
        var store =
            (await ManagedLocalBooks.open(paths, db)
                    as Success<ManagedLocalBooks>)
                .value;
        try {
          final book =
              (await store.importBook(
                        bytes: Stream.value(utf8.encode('Original')),
                        format: LocalBookFormat.txt,
                        parse: (s) async => fixture(s),
                        cancellation: CancellationSource().token,
                      )
                      as Success<LocalBookRecord>)
                  .value;
          final digest = book.content.detail.summary.key.novelId;
          final root = '${paths.localBooks.path}/$digest';
          final active = 'a' * 64;
          File? obsolete;
          if (scenario != 'cleanRoot' && scenario != 'oldRevision') {
            final bundle = await Directory(
              '$root/revisions/$active',
            ).create(recursive: true);
            await File(
              '$root/manifest.json',
            ).copy('${bundle.path}/manifest.json');
            await File('$root/manifest.json').delete();
            await db.customStatement('UPDATE local_books SET active_bundle=?', [
              active,
            ]);
          }
          if (['oldRoot', 'badHash', 'badPointer'].contains(scenario)) {
            obsolete = File('$root/${'b' * 64}');
            await obsolete.writeAsString('old media');
          } else if (scenario == 'oldRevision') {
            final old = await Directory(
              '$root/revisions/${'b' * 64}',
            ).create(recursive: true);
            obsolete = File('${old.path}/manifest.json');
            await obsolete.writeAsString('old content');
          }
          if (scenario == 'badHash') {
            await db.customStatement('UPDATE local_books SET manifest_hash=?', [
              '0' * 64,
            ]);
          }
          if (scenario == 'badPointer') {
            await db.customStatement('UPDATE local_books SET active_bundle=?', [
              'c' * 64,
            ]);
          }
          await store.close();
          final observed = _ManifestReads();
          store =
              (await IOOverrides.runWithIOOverrides(
                        () => ManagedLocalBooks.open(paths, db),
                        observed,
                      )
                      as Success<ManagedLocalBooks>)
                  .value;
          final clean = scenario == 'cleanRoot' || scenario == 'activeOnly';
          expect(
            observed.reads.length,
            clean || scenario == 'badPointer' ? 0 : 1,
          );
          if (obsolete != null) {
            expect(
              await obsolete.exists(),
              scenario == 'badHash' || scenario == 'badPointer',
            );
          }
          expect(await File('$root/original').readAsString(), 'Original');
          if (scenario != 'badHash' && scenario != 'badPointer') {
            expect(
              await store.read(
                book.content.detail.summary.key,
                cancellation: CancellationSource().token,
              ),
              isA<Success<LocalBookRecord?>>(),
            );
          }
        } finally {
          await store.close();
          await db.close();
          await temp.delete(recursive: true);
        }
      },
    );
  }
}
