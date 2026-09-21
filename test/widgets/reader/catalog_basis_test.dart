import 'dart:io';

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
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_completion_page.dart';
import 'package:shiori/features/reader/position/progress_tracker.dart';
import 'completion_test.dart' show CompletionRepository;

class _UnusedLocalStore implements LocalBookStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected local access');
}

class _MissingCatalogSource extends CompletionRepository {
  AppFailure? catalogFailure;
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async => catalogFailure == null
      ? super.loadCatalog(key, mode: mode, cancellation: cancellation)
      : Failure(catalogFailure!);
}

LoadResult<Catalog> remote(Catalog catalog, int day) => LoadResult(
  value: catalog,
  origin: LoadOrigin.remote,
  fetchedAt: DateTime.utc(2026, 1, day),
);
ReaderPosition position(ChapterContent c, double fraction) => ReaderPosition(
  contentRevision: c.contentRevision,
  blockKey: c.blocks.single.blockKey,
  blockIndex: 0,
  blockFraction: fraction,
  chapterFraction: fraction,
);
Future<void> seed(
  LocalLibraryRepository library,
  CompletionRepository source,
  Catalog basis,
) async {
  final token = CancellationSource().token;
  final c = source.content(source.keys[1]);
  final generation =
      (await library.beginProgressSession(source.key, cancellation: token)
              as Success<int>)
          .value;
  expect(
    await library.saveProgress(
      ReadingProgress(
        snapshot: NovelSummary(key: source.key, title: 'Book'),
        chapterKey: c.key,
        chapterOrdinalSnapshot: 1,
        catalogRevision: basis.revision,
        position: position(c, 1),
        completed: true,
        lastReadAt: DateTime.utc(2026),
        bookProgress: BookProgressMetrics.online(basis).at(c.key, 1),
      ),
      stamp: ProgressWriteStamp(generation: generation, sequence: 0),
      cancellation: token,
    ),
    isA<Success<bool>>(),
  );
}

Future<ReadingProgress> saved(
  LocalLibraryRepository library,
  NovelKey key,
) async =>
    (await library.getProgress(key, cancellation: CancellationSource().token)
            as Success<ReadingProgress?>)
        .value!;

void main() {
  test(
    'durable fallback handles misses and network errors without overriding cancellation',
    () async {
      final db = UserDatabase(NativeDatabase.memory());
      final library = LocalLibraryRepository(db);
      final source = _MissingCatalogSource()..count = 3;
      final catalog = source.catalog;
      var resolutions = 0;
      final repository = LocalReadingRepository(
        local: _UnusedLocalStore(),
        online: source,
        resolveOnlineCatalog: (key, result) {
          resolutions++;
          return library.resolveCatalog(key, result);
        },
      );
      final failures = [
        AppFailure(
          kind: FailureKind.cache,
          operation: Operation.catalog,
          context: FailureContext.cacheMiss,
        ),
        AppFailure(
          kind: FailureKind.network,
          operation: Operation.catalog,
          retryPolicy: RetryPolicy.manual,
        ),
        AppFailure(kind: FailureKind.timeout, operation: Operation.catalog),
        AppFailure(
          kind: FailureKind.sourceUnavailable,
          operation: Operation.catalog,
        ),
        AppFailure.cancelled(Operation.catalog),
        AppFailure(
          kind: FailureKind.accessRestricted,
          operation: Operation.catalog,
        ),
      ];
      for (final available in [false, true]) {
        if (available) await library.reconcileCatalog(remote(catalog, 3));
        for (var i = 0; i < failures.length; i++) {
          final failure = source.catalogFailure = failures[i];
          for (final event in [false, true]) {
            final calls = resolutions;
            late Result<LoadResult<Catalog>> result;
            if (event) {
              final pending = repository.catalogUpdates(source.key).first;
              source.updates.add(Failure(failure));
              result = await pending;
            } else {
              result = await repository.loadCatalog(
                source.key,
                mode: ReadMode.cacheOnly,
                cancellation: CancellationSource().token,
              );
            }
            if (available && i < 4) {
              expect(result, isA<Success<LoadResult<Catalog>>>());
              final value = (result as Success<LoadResult<Catalog>>).value;
              expect(value.value.revision, catalog.revision);
              expect(value.origin, LoadOrigin.local);
              expect(value.fetchedAt, DateTime.utc(2026, 1, 3));
              expect(value.isStale, isTrue);
              expect(value.refreshFailure, i == 0 ? null : same(failure));
            } else {
              expect(result, isA<Failure<LoadResult<Catalog>>>());
              expect(
                (result as Failure<LoadResult<Catalog>>).failure,
                same(failure),
              );
            }
            if (failure.isCancellation) expect(resolutions, calls);
          }
        }
      }
      source.catalogFailure = failures.first;
      final cancelled = CancellationSource()..cancel();
      final calls = resolutions;
      final result = await repository.loadCatalog(
        source.key,
        mode: ReadMode.cacheOnly,
        cancellation: cancelled.token,
      );
      expect(
        (result as Failure<LoadResult<Catalog>>).failure.isCancellation,
        isTrue,
      );
      expect(resolutions, calls);
      await source.updates.close();
      await db.close();
    },
  );

  for (final resume in ['retry', 'sample']) {
    test(
      'legacy conflict remains recoverable in the same tracker ($resume)',
      () async {
        final db = UserDatabase(NativeDatabase.memory());
        final library = LocalLibraryRepository(db);
        final source = CompletionRepository();
        final old = source.catalog;
        source.count = 3;
        final reliable = source.catalog;
        await seed(
          library,
          source,
          reliable,
        ); // v5 row: no durable catalog basis
        final c = source.content(source.keys[1]);
        final tracker = ProgressTracker(
          library: library,
          content: c,
          snapshot: NovelSummary(key: source.key, title: 'Book'),
          ordinal: 1,
          catalogRevision: old.revision,
          metrics: BookProgressMetrics.online(old),
        );
        await tracker.start();
        final generation =
            (await db
                    .customSelect('SELECT generation FROM progress_sessions')
                    .getSingle())
                .read<int>('generation');
        tracker.sample(position(c, .8), completed: true);
        await tracker.flush();
        expect(tracker.unsaved, isTrue);
        final blocked = tracker.failure;
        expect((await saved(library, source.key)).position.chapterFraction, 1);
        await library.reconcileCatalog(remote(reliable, 3));
        tracker.updateMetrics(BookProgressMetrics.online(reliable));
        if (resume == 'sample') {
          tracker.sample(position(c, .7), completed: true);
        }
        await tracker.retry();
        final recovered = await saved(library, source.key);
        expect(
          recovered.position.chapterFraction,
          resume == 'sample' ? .7 : .8,
        );
        expect(recovered.catalogRevision, reliable.revision);
        expect(tracker.unsaved, isFalse);
        expect(blocked?.retryPolicy, RetryPolicy.manual);
        expect(
          (await db
                  .customSelect('SELECT generation FROM progress_sessions')
                  .getSingle())
              .read<int>('generation'),
          generation,
        );
        // Ownership loss is permanent even when a newer catalog subsequently arrives.
        await library.beginProgressSession(
          source.key,
          cancellation: CancellationSource().token,
        );
        tracker.sample(position(c, .9), completed: true);
        await tracker.flush();
        await library.reconcileCatalog(remote(old, 4));
        tracker.updateMetrics(BookProgressMetrics.online(old));
        tracker.sample(position(c, .1), completed: true);
        await tracker.retry();
        expect(tracker.unsaved, isTrue);
        expect((await saved(library, source.key)).position, recovered.position);
        await tracker.close();
        await source.updates.close();
        await db.close();
      },
    );
  }

  for (final missing in [false, true]) {
    testWidgets(
      'restarted reader uses durable catalog for navigation and progress (missing=$missing)',
      (tester) async {
        late Directory dir;
        late UserDatabase db;
        late LocalLibraryRepository library;
        final source = _MissingCatalogSource()..count = 3;
        final reliable = source.catalog;
        await tester.runAsync(() async {
          dir = Directory.systemTemp.createTempSync('reader-catalog-basis-');
          final file = File('${dir.path}/user.sqlite');
          db = UserDatabase(NativeDatabase(file));
          library = LocalLibraryRepository(db);
          await seed(library, source, reliable);
          await library.reconcileCatalog(remote(reliable, 3));
          await db.close();
          db = UserDatabase(NativeDatabase(file));
          library = LocalLibraryRepository(db);
          await db.customSelect('SELECT 1').get();
        });
        source.count = 2; // Disposable cache never received B.
        if (missing) {
          source.catalogFailure = AppFailure(
            kind: FailureKind.cache,
            operation: Operation.catalog,
            context: FailureContext.cacheMiss,
          );
        }
        final repository = LocalReadingRepository(
          local: _UnusedLocalStore(),
          online: source,
          resolveOnlineCatalog: library.resolveCatalog,
        );
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (_) => BookReaderScreen(
                chapter: source.keys[1],
                repository: repository,
                library: library,
                offline: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        ReaderContentView view() =>
            tester.widget<ReaderContentView>(find.byType(ReaderContentView));
        expect(view().onNextChapter, isNotNull);
        expect(view().onBookEnd, isNull);
        expect(view().session!.bookMetrics!.revision, reliable.revision);
        final flush = view().session!.flushProgress();
        await tester.pumpAndSettle();
        await flush;
        final fraction = view().viewportController!.capture()!.chapterFraction;
        expect(
          view().session!.bookProgressAt(fraction)!.fraction,
          closeTo(2 / 3, .0001),
        );
        expect(
          (await tester.runAsync(
            () => saved(library, source.key),
          ))!.bookProgress!.fraction,
          closeTo(2 / 3, .0001),
        );
        await view().viewportController!.next();
        await tester.pumpAndSettle();
        expect(view().content.key, source.keys[2]);
        expect(find.byType(ReaderCompletionPage), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await source.updates.close();
        await tester.runAsync(() => db.close());
        dir.deleteSync(recursive: true);
      },
    );
  }
}
