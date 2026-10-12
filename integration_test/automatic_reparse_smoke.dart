// Offline native-channel / SQLite / ReaderController probe in a private root.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:path_provider/path_provider.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/files/storage_capacity.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import '../test/data/local/support/epub_fixtures.dart';

class _Offline implements NovelRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Online access');
}

T ok<T>(Result<T> result) => (result as Success<T>).value;
void require(bool condition) {
  if (!condition) throw StateError('Probe assertion');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('AUTOREPARSE_RUNNING'))),
    ),
  );
  final support = await getApplicationSupportDirectory();
  final root = await Directory(
    '${support.path}/automatic-reparse-probe',
  ).create(recursive: true);
  final report = <String, Object?>{};
  LocalDatabases? databases;
  ReaderController? reader;
  try {
    final paths = AppPaths(
      support: await root.createTemp('run-'),
      temporary: await getTemporaryDirectory(),
      environment: StorageEnvironment.development,
    );
    databases = ok(await LocalDatabases.open(paths));
    final store = databases!.localBooks;
    final db = databases.users;
    final capacity = await availableStorageBytes(paths.localBooks);
    require(capacity != null && capacity > 0);
    report['availableCapacityKnown'] = true;
    final token = CancellationSource().token;
    final books = <LocalBookRecord>[];
    for (final format in LocalBookFormat.values) {
      books.add(
        ok(
          await store.importBook(
            bytes: Stream.value(
              format == LocalBookFormat.txt
                  ? utf8.encode(
                      '第一章\nSelf-authored probe text for the current reader.',
                    )
                  : zipFiles(epubFiles()),
            ),
            format: format,
            cancellation: token,
            parse: (s) => const BookDecoder().decode(
              s,
              format: format,
              filename: 'fixture.${format.name}',
              cancellation: token,
              chooseEncoding: (_) async => TxtEncoding.utf8,
            ),
          ),
        ),
      );
    }
    await db.customStatement('UPDATE local_books SET parser_version=28');
    final a = books.first.content.chapters.first;
    reader = ReaderController(
      repository: LocalReadingRepository(local: store, online: _Offline()),
      chapter: a.key,
      library: LocalLibraryRepository(db),
    );
    await reader.load();
    await reader.retryProgress();
    reader.sampleProgress(
      ReaderPosition(
        contentRevision: a.contentRevision,
        blockKey: a.blocks.first.blockKey,
        blockIndex: 0,
        blockFraction: .5,
        chapterFraction: .5 / a.blocks.length,
      ),
      true,
    );
    await reader.flushProgress();
    store.automaticReparseActivity(resumed: true);
    store.startAutomaticReparse(
      initialDelay: Duration.zero,
      freeSpace: availableStorageBytes,
      measure: (phase, duration) =>
          report['${phase}Us'] = duration.inMicroseconds,
    );
    await Future<void>.delayed(Duration.zero);
    await store.automaticReparseIdle;
    Future<int> version(NovelKey key) async =>
        (await db
                .customSelect(
                  'SELECT parser_version FROM local_books WHERE digest=?',
                  variables: [Variable(key.novelId)],
                )
                .getSingle())
            .read<int>('parser_version');
    require(await version(a.key.novelKey) == 28);
    require(
      await version(books.last.content.detail.summary.key) ==
          BookDecoder.parserVersion,
    );
    reader.onDelete();
    await reader.closeReader();
    reader = null;
    await store.automaticReparseIdle;
    require(await version(a.key.novelKey) == BookDecoder.parserVersion);
    final progress = ok(
      await LocalLibraryRepository(
        db,
      ).getProgress(a.key.novelKey, cancellation: token),
    )!;
    require(progress.position.blockFraction == .5 && progress.completed);
    await databases.close();
    databases = null;
    databases = ok(await LocalDatabases.open(paths));
    require(
      ok(
            await databases!.localBooks.read(
              a.key.novelKey,
              cancellation: token,
            ),
          ) !=
          null,
    );
    report['status'] = 'PASS';
  } catch (error) {
    report['status'] = 'FAIL';
    report['errorType'] = error.runtimeType.toString();
  } finally {
    reader?.onDelete();
    await reader?.closeReader();
    await databases?.close();
  }
  await File(
    '${root.path}/report.json',
  ).writeAsString(jsonEncode(report), flush: true);
  // ignore: avoid_print
  print('AUTOREPARSE_${report['status']} ${jsonEncode(report)}');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(child: Text('AUTOREPARSE_${report['status']}')),
      ),
    ),
  );
}
