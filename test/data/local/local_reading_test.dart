import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/data/media/local_image_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'managed_local_books_test.dart' show ok, token;
import 'support/epub_fixtures.dart';

// Any accidental delegation fails the test, even for cacheOnly requests.
class ForbiddenOnline implements NovelRepository, ImageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Local book reached online: ${invocation.memberName}');
}

void main() {
  late Directory temp;
  late List<int> epubBytes;
  late AppPaths paths;
  late UserDatabase db;
  late ManagedLocalBooks store;
  late LocalLibraryRepository library;
  late LocalReadingRepository novels;
  late LocalImageRepository images;
  Future<void> open() async {
    db = UserDatabase(NativeDatabase(paths.userDatabase));
    store = ok(await ManagedLocalBooks.open(paths, db));
    library = LocalLibraryRepository(db);
    novels = LocalReadingRepository(local: store, online: ForbiddenOnline());
    images = LocalImageRepository(local: store, online: ForbiddenOnline());
  }

  setUp(() async {
    // Duplicate import must use identical bytes, including ZIP timestamps.
    epubBytes = zipFiles(epubFiles());
    temp = await Directory.systemTemp.createTemp('local005-');
    paths = AppPaths(
      support: temp,
      temporary: temp,
      environment: StorageEnvironment.development,
    );
    await paths.prepare();
    await open();
  });
  tearDown(() async {
    await store.close();
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<Result<LocalBookRecord>> add(LocalBookFormat format) {
    final bytes = format == LocalBookFormat.txt
        ? utf8.encode('第一章 星光\n开头正文。\n第二章 日出\n日出正文。')
        : epubBytes;
    return store.importBook(
      bytes: Stream.value(bytes),
      format: format,
      addToShelf: true,
      cancellation: token(),
      parse: (session) => const BookDecoder().decode(
        session,
        format: format,
        filename: '离线测试.${format.name}',
        cancellation: token(),
        chooseEncoding: (_) async => TxtEncoding.utf8,
      ),
    );
  }

  ReadingProgress progress(LocalBookRecord record) {
    final chapter = record.content.chapters.first;
    return ReadingProgress(
      snapshot: record.content.detail.summary,
      chapterKey: chapter.key,
      chapterOrdinalSnapshot: 0,
      catalogRevision: record.content.catalog.revision,
      position: ReaderPosition(
        contentRevision: chapter.contentRevision,
        blockKey: chapter.blocks[1].blockKey,
        blockIndex: 1,
        blockFraction: .25,
        chapterFraction: .25,
      ),
      completed: false,
      lastReadAt: DateTime.now(),
    );
  }

  for (final format in LocalBookFormat.values) {
    test(
      '${format.name}: import, shelf removal, duplicate, reopen and offline dispatch',
      () async {
        final record = ok(await add(format));
        final key = record.content.detail.summary.key;
        final originalShelf = ok(await library.watchBookshelf().first).single;
        expect(originalShelf.snapshot.key, key);
        expect(ok(await store.watchBooks().first).single.key, key);
        final generation = ok(
          await library.beginProgressSession(key, cancellation: token()),
        );
        expect(
          ok(
            await library.saveProgress(
              progress(record),
              stamp: ProgressWriteStamp(generation: generation, sequence: 0),
              cancellation: token(),
            ),
          ),
          isTrue,
        );
        ok(await library.removeFromBookshelf(key, cancellation: token()));
        expect(ok(await library.watchBookshelf().first), isEmpty);
        expect(ok(await store.read(key, cancellation: token())), isNotNull);
        expect(
          ok(await library.getProgress(key, cancellation: token())),
          isNotNull,
        );
        expect(ok(await add(format)).importedAt, record.importedAt);
        expect(ok(await library.watchBookshelf().first), hasLength(1));
        // External input is no longer needed; disposable online cache is unrelated.
        await paths.disposable.delete(recursive: true);
        await store.close();
        await db.close();
        await open();
        for (final mode in ReadMode.values) {
          expect(
            ok(
              await novels.loadDetail(key, mode: mode, cancellation: token()),
            ).origin,
            LoadOrigin.local,
          );
          expect(
            ok(
              await novels.loadCatalog(key, mode: mode, cancellation: token()),
            ).value,
            record.content.catalog,
          );
          for (final chapter in record.content.chapters) {
            expect(
              ok(
                await novels.loadChapter(
                  chapter.key,
                  mode: mode,
                  cancellation: token(),
                ),
              ).value,
              chapter,
            );
          }
        }
        expect(
          ok(await library.getProgress(key, cancellation: token()))!.position,
          progress(record).position,
        );
        expect(
          await novels
              .chapterUpdates(record.content.chapters.first.key)
              .isEmpty,
          isTrue,
        );
        expect(
          ok(await novels.loadNavigation(key, cancellation: token())),
          isNotEmpty,
        );
      },
    );
  }
  test('shelf failure rolls back import index and published files', () async {
    await db.customStatement(
      "CREATE TRIGGER fail_shelf BEFORE INSERT ON bookshelf BEGIN SELECT RAISE(ABORT,'fixture'); END",
    );
    expect(await add(LocalBookFormat.txt), isA<Failure>());
    expect(ok(await store.watchBooks().first), isEmpty);
    expect(ok(await library.watchBookshelf().first), isEmpty);
    expect(await paths.localBooks.list().toList(), isEmpty);
  });
  test(
    'delete invalidates leases and old progress, including after reimport',
    () async {
      final record = ok(await add(LocalBookFormat.epub));
      final key = record.content.detail.summary.key;
      final cover = record.content.detail.summary.cover!;
      final lease = ok(
        await images.load(
          cover,
          mode: ReadMode.cacheOnly,
          cancellation: token(),
        ),
      ).value;
      final generation = ok(
        await library.beginProgressSession(key, cancellation: token()),
      );
      final saved = progress(record);
      ok(
        await library.saveProgress(
          saved,
          stamp: ProgressWriteStamp(generation: generation, sequence: 0),
          cancellation: token(),
        ),
      );
      final deleted = ok(await store.deleteBook(key, cancellation: token()));
      expect(deleted.cleanupPending, isFalse);
      expect(ok(await store.watchBooks().first), isEmpty);
      expect(ok(await library.watchBookshelf().first), isEmpty);
      expect(ok(await library.getProgress(key, cancellation: token())), isNull);
      expect(
        await Directory('${paths.localBooks.path}/${key.novelId}').exists(),
        isFalse,
      );
      expect(
        await novels.loadChapter(
          saved.chapterKey,
          mode: ReadMode.cacheOnly,
          cancellation: token(),
        ),
        isA<Failure>(),
      );
      expect(
        await images.load(
          cover,
          mode: ReadMode.cacheOnly,
          cancellation: token(),
        ),
        isA<Failure>(),
      );
      expect((lease.data as MemoryMedia).bytes, tinyPng);
      expect(
        await library.putBookshelf(
          BookshelfEntry(snapshot: saved.snapshot, addedAt: DateTime.now()),
          cancellation: token(),
        ),
        isA<Failure>(),
      );
      expect(
        await library.beginProgressSession(key, cancellation: token()),
        isA<Failure>(),
      );
      ok(await add(LocalBookFormat.epub));
      expect(
        ok(
          await library.saveProgress(
            saved,
            stamp: ProgressWriteStamp(generation: generation, sequence: 99),
            cancellation: token(),
          ),
        ),
        isFalse,
      );
      expect(ok(await library.getProgress(key, cancellation: token())), isNull);
      await lease.close();
      await lease.close();
      expect(lease.isClosed, isTrue);
    },
  );
  test(
    'cancelled deletion preserves files, shelf and progress generation',
    () async {
      final record = ok(await add(LocalBookFormat.txt));
      final key = record.content.detail.summary.key;
      final source = CancellationSource()..cancel();
      expect(
        await store.deleteBook(key, cancellation: source.token),
        isA<Failure>(),
      );
      expect(ok(await store.read(key, cancellation: token())), isNotNull);
      expect(ok(await library.watchBookshelf().first), hasLength(1));
    },
  );
  test(
    'reader explicit fragment overrides saved position; missing anchor starts chapter',
    () async {
      final record = ok(await add(LocalBookFormat.epub));
      final chapter = record.content.chapters.first;
      final target = record.content.navigation.last.children.first;
      final generation = ok(
        await library.beginProgressSession(
          chapter.key.novelKey,
          cancellation: token(),
        ),
      );
      ok(
        await library.saveProgress(
          progress(record),
          stamp: ProgressWriteStamp(generation: generation, sequence: 0),
          cancellation: token(),
        ),
      );
      for (final anchor in [target.blockKey, 'absent']) {
        final reader = ReaderController(
          repository: novels,
          library: library,
          chapter: chapter.key,
          initialBlockKey: anchor,
        );
        await reader.load();
        final expected = anchor == 'absent'
            ? 0
            : chapter.blocks.indexWhere((b) => b.blockKey == anchor);
        expect(reader.initialPosition!.blockIndex, expected);
        expect(reader.usedFallback, anchor == 'absent');
        reader.onDelete();
        await reader.resourcesReleased;
      }
    },
  );
}
