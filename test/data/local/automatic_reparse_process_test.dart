import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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

Future<void> crash() async {
  // SIGKILL exercises OS file/SQLite recovery, not Future cancellation.
  Process.killPid(pid, ProcessSignal.sigkill);
  await Completer<void>().future;
}

class _CrashDecoder extends BookDecoder {
  @override
  Future<LocalBookContent> decode(
    LocalImportSession session, {
    required LocalBookFormat format,
    required String filename,
    required CancellationToken cancellation,
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
  }) async {
    await crash();
    throw StateError('Unreachable');
  }
}

void main() {
  final directory = Platform.environment['SHIORI_REPARSE_CRASH_ROOT'];
  final phase = Platform.environment['SHIORI_REPARSE_CRASH_PHASE'];
  final verify = Platform.environment['SHIORI_REPARSE_CRASH_VERIFY'] == '1';
  test(
    'opt-in process death recovers durable books and history',
    () async {
      final temp = Directory(directory!);
      await temp.create(recursive: true);
      final paths = AppPaths(
        support: temp,
        temporary: temp,
        environment: StorageEnvironment.development,
      );
      await paths.prepare();
      final db = UserDatabase(NativeDatabase(paths.userDatabase));
      final store =
          (await ManagedLocalBooks.open(paths, db)
                  as Success<ManagedLocalBooks>)
              .value;
      final input = utf8.encode('self-authored process crash fixture');
      final key = LocalBookIdentity.book(sha256.convert(input).toString());
      final library = LocalLibraryRepository(db);
      if (verify) {
        final book =
            (await store.read(key, cancellation: token())
                    as Success<LocalBookRecord?>)
                .value!;
        final progress =
            (await library.getProgress(key, cancellation: token()) as Success)
                .value;
        expect(progress.lastReadAt, DateTime.utc(2025));
        expect(progress.completed, isTrue);
        expect(
          await File(
            '${paths.localBooks.path}/${key.novelId}/original',
          ).readAsBytes(),
          input,
        );
        final row = await db
            .customSelect('SELECT * FROM local_books')
            .getSingle();
        expect(row.read<int>('maintenance'), 0);
        final committed = phase == 'afterCommit' || phase == 'cleanup';
        expect(
          row.read<int>('parser_version'),
          committed ? BookDecoder.parserVersion : 25,
        );
        expect(book.content.chapters, isNotEmpty);
        expect(await paths.localImportStaging.list().toList(), isEmpty);
        if (phase == 'preparedWaiting') {
          final attempt = await db
              .customSelect('SELECT * FROM local_reparse_attempts')
              .getSingle();
          expect(attempt.read<String>('outcome'), 'cancelled');
          expect(attempt.read<int>('failure_count'), 0);
          expect(
            attempt.read<int>('next_retry_at'),
            lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch),
          );
          store.automaticReparseActivity(resumed: true);
          store.startAutomaticReparse(initialDelay: Duration.zero);
          await Future<void>.delayed(Duration.zero);
          await store.automaticReparseIdle;
          expect(
            (await db.customSelect('SELECT * FROM local_books').getSingle())
                .read<int>('parser_version'),
            BookDecoder.parserVersion,
          );
          final saved =
              (await library.getProgress(key, cancellation: token()) as Success)
                  .value;
          expect(saved.lastReadAt, progress.lastReadAt);
          expect(saved.completed, progress.completed);
          expect(saved.position.blockFraction, progress.position.blockFraction);
        }
        await store.close();
        await db.close();
        return;
      }
      final book =
          (await store.importBook(
                    bytes: Stream.value(input),
                    format: LocalBookFormat.txt,
                    cancellation: token(),
                    parse: (s) => const BookDecoder().decode(
                      s,
                      format: LocalBookFormat.txt,
                      filename: 'fixture.txt',
                      cancellation: token(),
                      chooseEncoding: (_) async => TxtEncoding.utf8,
                    ),
                  )
                  as Success<LocalBookRecord>)
              .value;
      final generation =
          (await library.beginProgressSession(key, cancellation: token())
                  as Success<int>)
              .value;
      expect(
        (await library.saveProgress(
                  f.progress(book.content),
                  stamp: ProgressWriteStamp(
                    generation: generation,
                    sequence: 0,
                  ),
                  cancellation: token(),
                )
                as Success<bool>)
            .value,
        isTrue,
      );
      await db.customStatement('UPDATE local_books SET parser_version=25');
      if (phase == 'preparedWaiting') {
        await store.acquireBookUse(key, cancellation: token());
      }
      store.automaticReparseActivity(resumed: true);
      store.startAutomaticReparse(
        initialDelay: Duration.zero,
        decoder: phase == 'prepare' ? _CrashDecoder() : const BookDecoder(),
        checkpoint: (at) async {
          if (at == phase) await crash();
        },
      );
      await Future<void>.delayed(Duration.zero);
      await store.automaticReparseIdle;
      if (phase == 'preparedWaiting') {
        expect(
          (await db
                  .customSelect('SELECT * FROM local_reparse_attempts')
                  .getSingle())
              .read<String>('outcome'),
          'preparedWaiting',
        );
        await crash();
      }
      fail('Crash checkpoint did not terminate the process');
    },
    skip: directory == null || phase == null,
  );
}

CancellationToken token() => CancellationSource().token;
