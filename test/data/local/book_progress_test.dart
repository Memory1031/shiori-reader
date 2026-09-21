import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';

class _UnusedLocalStore implements LocalBookStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected local access');
}

class _CatalogOnline implements NovelRepository {
  late LoadResult<Catalog> observation;
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async => Success(observation);
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      Stream.value(Success(observation));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final scenario in ['restart', 'retry', 'legacy']) {
    test(
      'catalog basis survives $scenario and rejects old cache and late writes',
      () async {
        final dir = await Directory.systemTemp.createTemp('book-progress-');
        final file = File('${dir.path}/users.sqlite');
        var db = UserDatabase(NativeDatabase(file));
        var repo = LocalLibraryRepository(db);
        final key = NovelKey(sourceId: SourceId('online'), novelId: 'book');
        Catalog catalog(int count) => Catalog(
          novelKey: key,
          volumes: [
            Volume(
              groupId: 'v',
              chapters: List.generate(
                count,
                (i) => Chapter(
                  key: ChapterKey(novelKey: key, chapterId: '$i'),
                  title: '$i',
                  ordinal: i,
                  volumeGroupId: 'v',
                ),
              ),
            ),
          ],
        );
        final token = CancellationSource().token;
        final old = catalog(2);
        final progress = ReadingProgress(
          snapshot: NovelSummary(key: key, title: 'Book'),
          chapterKey: old.flatChapters.last.key,
          chapterOrdinalSnapshot: 1,
          catalogRevision: old.revision,
          position: ReaderPosition(
            contentRevision: 'content',
            blockKey: 'block',
            blockIndex: 0,
            blockFraction: 1,
            chapterFraction: 1,
          ),
          completed: true,
          lastReadAt: DateTime.utc(2026),
          bookProgress: BookProgressSnapshot(
            fraction: 1,
            chapterCount: 2,
            terminal: BookTerminalState.caughtUp,
          ),
        );
        final gen =
            (await repo.beginProgressSession(key, cancellation: token)
                    as Success<int>)
                .value;
        expect(
          await repo.saveProgress(
            progress,
            stamp: ProgressWriteStamp(generation: gen, sequence: 0),
            cancellation: token,
          ),
          isA<Success<bool>>(),
        );
        await db.close();
        db = UserDatabase(NativeDatabase(file));
        repo = LocalLibraryRepository(db);
        final restored =
            (await repo.getProgress(key, cancellation: token)
                    as Success<ReadingProgress?>)
                .value!;
        expect(restored, progress);
        LoadResult<Catalog> observation(
          int count,
          int day, {
          LoadOrigin origin = LoadOrigin.remote,
          bool stale = false,
        }) => LoadResult(
          value: catalog(count),
          origin: origin,
          fetchedAt: DateTime.utc(2026, 1, day),
          isStale: stale,
        );
        if (scenario == 'legacy') {
          // Emulate a pre-v6 progress row: B is persisted, its fetch time is not.
          await db.customStatement(
            'UPDATE reading_progress SET catalog_revision=?,book_progress=?',
            [
              catalog(3).revision,
              jsonEncode(
                BookProgressMetrics.online(
                  catalog(3),
                ).at(progress.chapterKey, 1)!.toJson(),
              ),
            ],
          );
          await repo.reconcileCatalog(
            observation(2, 1, origin: LoadOrigin.local),
          );
          final guarded =
              (await repo.getProgress(key, cancellation: token)
                      as Success<ReadingProgress?>)
                  .value!;
          expect(guarded.catalogRevision, catalog(3).revision);
          expect(guarded.bookProgress!.fraction, 2 / 3);
          final blocked = await repo.saveProgress(
            progress,
            stamp: ProgressWriteStamp(generation: gen, sequence: 1),
            cancellation: token,
          );
          expect(blocked, isA<Failure<bool>>());
          expect(
            (blocked as Failure<bool>).failure.context,
            FailureContext.catalogBasisUnavailable,
          );
          expect(blocked.failure.retryPolicy, RetryPolicy.manual);
        }
        final newer = observation(3, 3);
        if (scenario == 'retry') {
          await db.customStatement(
            "CREATE TRIGGER fail_progress BEFORE UPDATE ON reading_progress BEGIN SELECT RAISE(ABORT, 'injected write failure'); END",
          );
          expect(
            await repo.reconcileCatalog(newer),
            isA<Failure<LoadResult<Catalog>>>(),
          );
          final failedReading = LocalReadingRepository(
            local: _UnusedLocalStore(),
            online: _CatalogOnline()..observation = newer,
            resolveOnlineCatalog: repo.resolveCatalog,
          );
          final failedLoad = await failedReading.loadCatalog(
            key,
            mode: ReadMode.refresh,
            cancellation: token,
          );
          expect(failedLoad, isA<Failure<LoadResult<Catalog>>>());
          expect(
            (failedLoad as Failure<LoadResult<Catalog>>).failure.retryPolicy,
            RetryPolicy.manual,
          );
          final unchanged =
              (await repo.getProgress(key, cancellation: token)
                      as Success<ReadingProgress?>)
                  .value!;
          expect(unchanged, progress);
          expect(
            await db.customSelect('SELECT * FROM progress_catalogs').get(),
            isEmpty,
          );
          await db.customStatement('DROP TRIGGER fail_progress');
        }
        final online = _CatalogOnline()..observation = newer;
        final observed = <LoadResult<Catalog>>[];
        final reading = LocalReadingRepository(
          local: _UnusedLocalStore(),
          online: online,
          resolveOnlineCatalog: (key, result) async {
            if (result case Success(:final value)) observed.add(value);
            return repo.resolveCatalog(key, result);
          },
        );
        await reading.loadCatalog(
          key,
          mode: ReadMode.refresh,
          cancellation: token,
        );
        expect(observed.last, same(online.observation));
        final accepted =
            (await repo.getProgress(key, cancellation: token)
                    as Success<ReadingProgress?>)
                .value!;
        expect(accepted.bookProgress!.fraction, 2 / 3);
        if (scenario == 'restart') {
          await db.close();
          db = UserDatabase(NativeDatabase(file));
          repo = LocalLibraryRepository(db);
        }
        // Remote B was accepted, but its cache write failed. A is still readable.
        online.observation = LoadResult(
          value: catalog(2),
          origin: LoadOrigin.local,
          fetchedAt: DateTime.utc(2026, 1, 1),
          isStale: true,
          refreshFailure: AppFailure(
            kind: FailureKind.network,
            operation: Operation.catalog,
          ),
        );
        final resolved =
            (await reading.catalogUpdates(key).single
                    as Success<LoadResult<Catalog>>)
                .value;
        expect(resolved.value.revision, catalog(3).revision);
        expect(resolved.fetchedAt, newer.fetchedAt);
        expect(resolved.origin, LoadOrigin.local);
        expect(resolved.isStale, isTrue);
        expect(resolved.refreshFailure, online.observation.refreshFailure);
        final cached =
            (await reading.loadCatalog(
                      key,
                      mode: ReadMode.cacheOnly,
                      cancellation: token,
                    )
                    as Success<LoadResult<Catalog>>)
                .value;
        expect(cached.value.revision, resolved.value.revision);
        expect(observed.last, same(online.observation));
        expect(observed.last.refreshFailure, isNotNull);
        var updated =
            (await repo.getProgress(key, cancellation: token)
                    as Success<ReadingProgress?>)
                .value!;
        expect(updated.position, progress.position);
        expect(updated.lastReadAt, progress.lastReadAt);
        expect(updated.bookProgress!.fraction, 2 / 3);
        expect(updated.bookProgress!.terminal, BookTerminalState.reading);
        expect(updated.catalogRevision, catalog(3).revision);
        await repo.saveProgress(
          progress,
          stamp: ProgressWriteStamp(generation: gen, sequence: 1),
          cancellation: token,
        );
        updated =
            (await repo.getProgress(key, cancellation: token)
                    as Success<ReadingProgress?>)
                .value!;
        expect(updated.bookProgress!.fraction, 2 / 3);
        expect(updated.bookProgress!.terminal, BookTerminalState.reading);
        // A genuinely newer deletion must still be accepted (not max chapter count).
        online.observation = observation(2, 4);
        final deletion =
            (await reading.loadCatalog(
                      key,
                      mode: ReadMode.refresh,
                      cancellation: token,
                    )
                    as Success<LoadResult<Catalog>>)
                .value;
        expect(deletion.value.revision, catalog(2).revision);
        expect(deletion.origin, LoadOrigin.remote);
        updated =
            (await repo.getProgress(key, cancellation: token)
                    as Success<ReadingProgress?>)
                .value!;
        expect(updated.bookProgress!.fraction, 1);
        expect(updated.bookProgress!.chapterCount, 2);
        expect(updated.bookProgress!.terminal, BookTerminalState.reading);
        expect(updated.lastReadAt, progress.lastReadAt);
        await db.customStatement(
          "UPDATE reading_progress SET book_progress='{\"fraction\":2,\"chapterCount\":3,\"terminal\":\"reading\"}'",
        );
        expect(
          await repo.getProgress(key, cancellation: token),
          isA<Failure<ReadingProgress?>>(),
        );
        await db.close();
        await dir.delete(recursive: true);
      },
    );
  }
}
