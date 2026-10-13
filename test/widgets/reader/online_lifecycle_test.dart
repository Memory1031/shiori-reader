import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'completion_test.dart' show CompletionRepository;

class UnusedLocal implements LocalBookStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Local access');
}

class FailedChapter extends CompletionRepository {
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async => Failure(
    AppFailure(kind: FailureKind.network, operation: Operation.chapter),
  );
}

Future<void> ready(ReaderController reader) async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    if (reader.status == ReaderStatus.ready) {
      return;
    }
  }
  fail('Reader did not settle');
}

ReaderPosition anchor(ChapterContent c) => ReaderPosition(
  contentRevision: c.contentRevision,
  blockKey: c.blocks.first.blockKey,
  blockIndex: 0,
  blockFraction: .25,
  chapterFraction: .25,
);
void main() {
  test(
    'offline loaded and passive candidates do not join; activation and valid save join atomically',
    () async {
      final db = UserDatabase(NativeDatabase.memory());
      final library = LocalLibraryRepository(db);
      final source = CompletionRepository();
      final repository = LocalReadingRepository(
        local: UnusedLocal(),
        online: source,
        bindOnlineCatalog: library.bindCatalog,
      );
      final reader = ReaderController(
        repository: repository,
        chapter: source.keys.first,
        library: library,
        readMode: ReadMode.cacheOnly,
        deferProgress: true,
      )..onStart();
      await ready(reader);
      reader.sampleProgress(anchor(reader.content!), false);
      expect(await reader.saveForExit(), isTrue);
      for (final table in [
        'bookshelf',
        'reading_progress',
        'progress_catalogs',
      ]) {
        expect(await db.customSelect('SELECT * FROM $table').get(), isEmpty);
      }
      reader.activateProgress();
      await ready(reader);
      await reader.flushProgress();
      expect(
        await db.customSelect('SELECT * FROM bookshelf').get(),
        hasLength(1),
      );
      expect(
        await db.customSelect('SELECT * FROM progress_catalogs').get(),
        hasLength(1),
      );
      final saved =
          (await library.getProgress(
                    source.key,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value!;
      expect(saved.position.blockFraction, .25);
      final candidate = ReaderController(
        repository: repository,
        chapter: source.keys[1],
        library: library,
        deferProgress: true,
      )..onStart();
      await ready(candidate);
      candidate.sampleProgress(anchor(candidate.content!), false);
      candidate.onDelete();
      await candidate.resourcesReleased;
      candidate.dispose();
      expect(
        (await library.getProgress(
                  source.key,
                  cancellation: CancellationSource().token,
                )
                as Success<ReadingProgress?>)
            .value,
        saved,
      );
      reader.onDelete();
      await reader.resourcesReleased;
      reader.dispose();
      await source.updates.close();
      await db.close();
    },
  );
  test('failed chapter does not create ownership', () async {
    final db = UserDatabase(NativeDatabase.memory());
    final source = FailedChapter();
    final reader = ReaderController(
      repository: source,
      chapter: source.keys.first,
      library: LocalLibraryRepository(db),
    )..onStart();
    for (var i = 0; i < 20 && reader.status == ReaderStatus.loading; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(reader.status, ReaderStatus.error);
    expect(await db.customSelect('SELECT * FROM bookshelf').get(), isEmpty);
    expect(
      await db.customSelect('SELECT * FROM reading_progress').get(),
      isEmpty,
    );
    reader.onDelete();
    await reader.resourcesReleased;
    reader.dispose();
    await source.updates.close();
    await db.close();
  });
  testWidgets(
    'removing an open Reader retires its current and passive sessions without resurrection',
    (tester) async {
      final db = UserDatabase(NativeDatabase.memory());
      final library = LocalLibraryRepository(db);
      final source = CompletionRepository();
      final repository = LocalReadingRepository(
        local: UnusedLocal(),
        online: source,
        bindOnlineCatalog: library.bindCatalog,
      );
      await tester.runAsync(() => db.customSelect('SELECT 1').get());
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: source.keys.first,
              repository: repository,
              library: library,
              offline: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final view = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView).first,
      );
      final reader = view.session!;
      final writing = reader.flushProgress();
      await tester.pumpAndSettle();
      await writing;
      await tester.runAsync(() async {
        expect(
          await db.customSelect('SELECT * FROM bookshelf').get(),
          hasLength(1),
        );
        expect(
          await library.removeOnlineBook(
            source.key,
            cancellation: CancellationSource().token,
          ),
          isA<Success>(),
        );
      });
      await tester.pumpAndSettle();
      expect(find.byType(ReaderContentView), findsNothing);
      expect(reader.status, ReaderStatus.cancelled);
      expect(await reader.saveForExit(), isTrue);
      reader.activateProgress();
      reader.sampleProgress(anchor(source.content(source.keys.first)), false);
      await reader.flushProgress();
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(() async {
        for (final table in [
          'bookshelf',
          'reading_progress',
          'progress_catalogs',
        ]) {
          expect(await db.customSelect('SELECT * FROM $table').get(), isEmpty);
        }
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await source.updates.close();
      await tester.runAsync(() => db.close());
    },
  );
}
