import 'dart:convert';
import 'dart:io';

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
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/book_selection_controller.dart';
import 'package:shiori/features/bookshelf/library_controller.dart';
import 'package:shiori/features/local_books/local_reparse_controller.dart';

import '../../domain/reparse_position_test.dart' as f;
import '../../widgets/bookshelf_test.dart' show RemovalCache;
import 'managed_local_books_test.dart' show fixture;

T ok<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}

CancellationToken token() => CancellationSource().token;

void main() {
  test(
    'selected store reparse cold reopen and mixed deletion preserve exact data boundaries',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'shiori-batch-fixture-',
      );
      final paths = AppPaths(
        support: Directory('${dir.path}/support'),
        temporary: dir,
        environment: StorageEnvironment.development,
      );
      await paths.prepare();
      var db = UserDatabase(NativeDatabase(paths.userDatabase));
      var store = ok(await ManagedLocalBooks.open(paths, db));
      var repository = LocalLibraryRepository(db);
      Future<LocalBookRecord> add(String text) async => ok(
        await store.importBook(
          bytes: Stream.value(utf8.encode(text)),
          format: LocalBookFormat.txt,
          addToShelf: true,
          cancellation: token(),
          parse: (session) => const BookDecoder().decode(
            session,
            filename: 'Same title.txt',
            format: LocalBookFormat.txt,
            encoding: TxtEncoding.utf8,
            chooseEncoding: (_) async => TxtEncoding.utf8,
            cancellation: token(),
          ),
        ),
      );
      final first = await add('第一章\nSynthetic selected text.');
      final untouched = await add('第一章\nSynthetic untouched text.');
      final broken = ok(
        await store.importBook(
          bytes: Stream.value(utf8.encode('Synthetic invalid ZIP original')),
          format: LocalBookFormat.epub,
          addToShelf: true,
          cancellation: token(),
          parse: (session) async => fixture(session),
        ),
      );
      final a = first.content.detail.summary.key,
          b = broken.content.detail.summary.key,
          other = untouched.content.detail.summary.key;
      final old = {
        a: f.progress(first.content),
        b: f.progress(broken.content),
        other: f.progress(untouched.content),
      };
      for (final saved in old.values) {
        final generation = ok(
          await repository.beginProgressSession(
            saved.novelKey,
            cancellation: token(),
          ),
        );
        ok(
          await repository.saveProgress(
            saved,
            stamp: ProgressWriteStamp(generation: generation, sequence: 0),
            cancellation: token(),
          ),
        );
      }
      final invalidated = <NovelKey>[];
      final subscription = store.invalidations.listen(invalidated.add);
      final reparse = LocalReparseController(store);
      await reparse.run(
        [
          LocalReparseTarget(a, 'Same title', LocalBookFormat.txt),
          LocalReparseTarget(b, 'Same title', LocalBookFormat.epub),
        ],
        batch: true,
        chooseEncoding: (_, _) async => TxtEncoding.utf8,
      );
      expect(reparse.outcomes.map((r) => (r.key, r.status)), [
        (a, BookBatchStatus.succeeded),
        (b, BookBatchStatus.failed),
      ]);
      expect(invalidated, contains(a));
      reparse.dispose();
      await subscription.cancel();
      await store.close();
      await db.close();
      db = UserDatabase(NativeDatabase(paths.userDatabase));
      store = ok(await ManagedLocalBooks.open(paths, db));
      repository = LocalLibraryRepository(db);
      expect(
        ok(await store.read(b, cancellation: token()))!.content.chapters,
        broken.content.chapters,
      );
      expect(
        ok(await repository.getProgress(b, cancellation: token())),
        old[b],
      );
      expect(
        ok(await store.read(other, cancellation: token()))!.content.chapters,
        untouched.content.chapters,
      );
      expect(
        ok(await repository.getProgress(other, cancellation: token())),
        old[other],
      );
      final reparsed = ok(
        await repository.getProgress(a, cancellation: token()),
      )!;
      expect(
        reparsed.position.blockFraction,
        closeTo(old[a]!.position.blockFraction, .0001),
      );
      expect(reparsed.position.pixelOffset, isNull);

      final online = NovelSummary(
        key: NovelKey(sourceId: SourceId('fixture'), novelId: 'online'),
        title: 'Same title',
      );
      await repository.putBookshelf(
        BookshelfEntry(snapshot: online, addedAt: DateTime.utc(2026)),
        cancellation: token(),
      );
      final onlineHistory = ReadingProgress(
        snapshot: online,
        chapterKey: ChapterKey(novelKey: online.key, chapterId: 'c'),
        chapterOrdinalSnapshot: 0,
        catalogRevision: 'catalog',
        position: ReaderPosition(
          contentRevision: 'content',
          blockKey: 'block',
          blockIndex: 0,
          blockFraction: .5,
          chapterFraction: .5,
        ),
        completed: false,
        lastReadAt: DateTime.utc(2026),
      );
      final generation = ok(
        await repository.beginProgressSession(
          online.key,
          cancellation: token(),
        ),
      );
      ok(
        await repository.saveProgress(
          onlineHistory,
          stamp: ProgressWriteStamp(generation: generation, sequence: 0),
          cancellation: token(),
        ),
      );
      final external = File('${dir.path}/original.txt');
      await external.writeAsString('External original stays.');
      final cache = RemovalCache();
      final controller = LibraryController(
        repository,
        cache: cache,
        localBooks: store,
      )..onStart();
      final request = CancellationSource(),
          lease = controller.acquireBatch(CancellationSource())!;
      ok(await controller.removeInBatch(a, lease, cancellation: request.token));
      ok(
        await controller.removeInBatch(
          online.key,
          lease,
          cancellation: request.token,
        ),
      );
      expect(controller.writing, isTrue);
      lease.release();
      expect(cache.cleared, [online.key]);
      expect(ok(await store.read(a, cancellation: token())), isNull);
      expect(
        ok(await repository.getProgress(a, cancellation: token())),
        isNull,
      );
      expect(
        await Directory('${paths.localBooks.path}/${a.novelId}').exists(),
        isFalse,
      );
      expect(
        ok(await repository.getProgress(online.key, cancellation: token())),
        onlineHistory,
      );
      expect(
        ok(await store.watchBooks().first).map((item) => item.key).toSet(),
        {b, other},
      );
      expect(await external.readAsString(), 'External original stays.');
      controller.onDelete();
      await controller.resourcesReleased;
      controller.dispose();
      await store.close();
      await db.close();
      db = UserDatabase(NativeDatabase(paths.userDatabase));
      store = ok(await ManagedLocalBooks.open(paths, db));
      repository = LocalLibraryRepository(db);
      expect(
        ok(await repository.getProgress(online.key, cancellation: token())),
        onlineHistory,
      );
      expect(
        ok(
          await repository.watchBookshelf().first,
        ).map((item) => item.snapshot.key).toSet(),
        {b, other},
      );
      await store.close();
      await db.close();
      await dir.delete(recursive: true);
    },
  );
}
