import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import '../../domain/reparse_position_test.dart' as f;
import 'support/epub_fixtures.dart';

class _ObservedDecoder extends BookDecoder {
  final entered = Completer<void>();
  @override
  Future<LocalBookContent> decode(
    LocalImportSession session, {
    required LocalBookFormat format,
    required String filename,
    required CancellationToken cancellation,
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
  }) {
    if (!entered.isCompleted) entered.complete();
    return super.decode(
      session,
      format: format,
      filename: filename,
      cancellation: cancellation,
      chooseEncoding: chooseEncoding,
      encoding: encoding,
    );
  }
}

T ok<T>(Result<T> result) => (result as Success<T>).value;
CancellationToken token() => CancellationSource().token;
void main() {
  test(
    'opt-in large EPUB and recovery timings',
    () async {
      final temp = await Directory.systemTemp.createTemp('auto-reparse-perf-');
      final paths = AppPaths(
        support: temp,
        temporary: temp,
        environment: StorageEnvironment.development,
      );
      await paths.prepare();
      final db = UserDatabase(
        NativeDatabase.createInBackground(paths.userDatabase),
      );
      var store = ok(await ManagedLocalBooks.open(paths, db));
      try {
        final files = epubFiles();
        final random = Random(12345);
        const alphabet = 'abcdefghijklmnopqrstuvwxyz';
        var textBytes = 0;
        for (final name in ['a', 'b', 'c']) {
          final paragraphs = List.generate(
            3000,
            (i) =>
                '<p>Paragraph $name $i ${String.fromCharCodes(List.generate(1000, (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length))))}</p>',
          ).join();
          final bytes = utf8.encode('<html><body>$paragraphs</body></html>');
          files['OPS/text/$name.xhtml'] = bytes;
          textBytes += bytes.length;
        }
        files['OPS/book.opf'] = utf8.encode(
          utf8
              .decode(files['OPS/book.opf']!)
              .replaceFirst(
                '</manifest>',
                '<item id="c" href="text/c.xhtml" media-type="application/xhtml+xml"/></manifest>',
              )
              .replaceFirst('</spine>', '<itemref idref="c"/></spine>'),
        );
        final input = zipFiles(files);
        final a = ok(
          await store.importBook(
            bytes: Stream.value(input),
            format: LocalBookFormat.epub,
            addToShelf: true,
            cancellation: token(),
            parse: (s) => const BookDecoder().decode(
              s,
              format: LocalBookFormat.epub,
              filename: 'large.epub',
              cancellation: token(),
              chooseEncoding: (_) async => TxtEncoding.utf8,
            ),
          ),
        );
        final b = ok(
          await store.importBook(
            bytes: Stream.value(utf8.encode('unrelated chapter')),
            format: LocalBookFormat.txt,
            cancellation: token(),
            parse: (s) => const BookDecoder().decode(
              s,
              format: LocalBookFormat.txt,
              filename: 'other.txt',
              cancellation: token(),
              chooseEncoding: (_) async => TxtEncoding.utf8,
            ),
          ),
        );
        await db.customStatement('UPDATE local_books SET parser_version=28');
        final library = LocalLibraryRepository(db);
        final key = a.content.detail.summary.key;
        final generation = ok(
          await library.beginProgressSession(key, cancellation: token()),
        );
        final use = (await store.acquireBookUse(key, cancellation: token()))!;
        final decoder = _ObservedDecoder();
        final times = <String, Object?>{};
        var peak = ProcessInfo.currentRss;
        final baseline = peak;
        final sampler = Timer.periodic(const Duration(milliseconds: 20), (_) {
          peak = max(peak, ProcessInfo.currentRss);
        });
        store.automaticReparseActivity(resumed: true);
        store.startAutomaticReparse(
          initialDelay: Duration.zero,
          decoder: decoder,
          measure: (phase, duration) => times[phase] = duration.inMicroseconds,
        );
        await decoder.entered.future;
        final read = Stopwatch()..start();
        ok(
          await store.read(b.content.detail.summary.key, cancellation: token()),
        );
        times['chapterReadUs'] = read.elapsedMicroseconds;
        final save = Stopwatch()..start();
        expect(
          ok(
            await library.saveProgress(
              f.progress(a.content, index: 2000),
              stamp: ProgressWriteStamp(generation: generation, sequence: 0),
              cancellation: token(),
            ),
          ),
          isTrue,
        );
        times['saveProgressUs'] = save.elapsedMicroseconds;
        await store.automaticReparseIdle;
        await use.release(progressSaved: true);
        await store.automaticReparseIdle;
        sampler.cancel();
        // Check both upgrades without relying on timing alone.
        expect(ok(await store.read(key, cancellation: token())), isNotNull);
        final versions = await db
            .customSelect('SELECT parser_version FROM local_books')
            .get();
        expect(
          versions.every(
            (r) => r.read<int>('parser_version') == BookDecoder.parserVersion,
          ),
          isTrue,
        );
        times['compressedBytes'] = input.length;
        times['uncompressedTextBytes'] = textBytes;
        times['rssBaselineBytes'] = baseline;
        times['rssPeakBytes'] = peak;
        await store.close();
        for (var i = 0; i < 1000; i++) {
          final stage = await paths.localImportStaging.createTemp('import-');
          await File('${stage.path}/partial').writeAsString('fixture');
        }
        final recovery = Stopwatch()..start();
        store = ok(await ManagedLocalBooks.open(paths, db));
        times['recover1000StagesUs'] = recovery.elapsedMicroseconds;
        expect(await paths.localImportStaging.list().toList(), isEmpty);
        // ignore: avoid_print
        print('Automatic reparse performance: ${jsonEncode(times)}');
      } finally {
        await store.close();
        await db.close();
        await temp.delete(recursive: true);
      }
    },
    skip: Platform.environment['SHIORI_REPARSE_PERFORMANCE'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test(
    'opt-in many-chapter publication timing',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'auto-reparse-chapters-',
      );
      final paths = AppPaths(
        support: temp,
        temporary: temp,
        environment: StorageEnvironment.development,
      );
      await paths.prepare();
      final db = UserDatabase(
        NativeDatabase.createInBackground(paths.userDatabase),
      );
      final store = ok(await ManagedLocalBooks.open(paths, db));
      try {
        final files = epubFiles();
        files['OPS/book.opf'] = utf8.encode(
          utf8
              .decode(files['OPS/book.opf']!)
              .replaceFirst(
                '<itemref idref="a"/>',
                '<itemref idref="a"/>' * 1500,
              ),
        );
        final book = ok(
          await store.importBook(
            bytes: Stream.value(zipFiles(files)),
            format: LocalBookFormat.epub,
            cancellation: token(),
            parse: (s) => const BookDecoder().decode(
              s,
              format: LocalBookFormat.epub,
              filename: 'many.epub',
              cancellation: token(),
              chooseEncoding: (_) async => TxtEncoding.utf8,
            ),
          ),
        );
        await db.customStatement('UPDATE local_books SET parser_version=28');
        final times = <String, Object?>{
          'chapters': book.content.chapters.length,
        };
        store.automaticReparseActivity(resumed: true);
        store.startAutomaticReparse(
          initialDelay: Duration.zero,
          measure: (phase, duration) => times[phase] = duration.inMicroseconds,
        );
        await Future<void>.delayed(Duration.zero);
        await store.automaticReparseIdle;
        expect(
          (await db
                  .customSelect(
                    'SELECT COUNT(*) AS n FROM local_chapter_revisions',
                  )
                  .getSingle())
              .read<int>('n'),
          1501,
        );
        // ignore: avoid_print
        print('Many-chapter publication performance: ${jsonEncode(times)}');
      } finally {
        await store.close();
        await db.close();
        await temp.delete(recursive: true);
      }
    },
    skip: Platform.environment['SHIORI_REPARSE_PERFORMANCE'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
