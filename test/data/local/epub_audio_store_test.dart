import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/synthetic_audio.dart';

void main() {
  test(
    'normal import persists audio bytes and reopening retains media identity',
    () async {
      final root = await Directory.systemTemp.createTemp('shiori-audio-store-');
      final paths = AppPaths(
        support: Directory('${root.path}/support'),
        temporary: root,
        environment: StorageEnvironment.development,
      );
      await paths.prepare();
      final db = UserDatabase(NativeDatabase(paths.userDatabase));
      var store =
          (await ManagedLocalBooks.open(paths, db)
                  as Success<ManagedLocalBooks>)
              .value;
      final cancellation = CancellationSource();
      try {
        final imported = await store.importBook(
          bytes: Stream.value(
            audioEpubBytes(
              '<p>Self authored recording.</p><audio controls src="../audio/test.wav"></audio>',
            ),
          ),
          format: LocalBookFormat.epub,
          parse: (session) => const BookDecoder().decode(
            session,
            format: LocalBookFormat.epub,
            filename: 'synthetic.epub',
            cancellation: cancellation.token,
            chooseEncoding: (_) async => TxtEncoding.utf8,
          ),
          cancellation: cancellation.token,
        );
        final content = (imported as Success<LocalBookRecord>).value.content;
        final audio = content.chapters.first.blocks
            .whereType<AudioBlock>()
            .single;
        expect(
          (await store.readMedia(audio.media!, cancellation: cancellation.token)
                  as Success)
              .value,
          syntheticWav(),
        );
        await store.close();
        store =
            (await ManagedLocalBooks.open(paths, db)
                    as Success<ManagedLocalBooks>)
                .value;
        final record =
            (await store.read(
                      content.detail.summary.key,
                      cancellation: cancellation.token,
                    )
                    as Success<LocalBookRecord?>)
                .value!;
        expect(
          record.content.chapters.first.blocks.whereType<AudioBlock>().single,
          audio,
        );
        expect(
          (await store.readMedia(audio.media!, cancellation: cancellation.token)
                  as Success)
              .value,
          syntheticWav(),
        );
      } finally {
        await store.close();
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );
}
