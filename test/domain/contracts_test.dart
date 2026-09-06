import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:test/test.dart';

import '../support/contract_fakes.dart';
import '../support/contract_library.dart';

T value<T>(Result<T> result) => (result as Success<T>).value;
AppFailure failure<T>(Result<T> result) => (result as Failure<T>).failure;

void main() {
  test(
    'library contract isolates shelf/history and rejects old write stamps',
    () async {
      final LibraryRepository library = ContractLibrary();
      final token = CancellationSource();
      addTearDown((library as ContractLibrary).close);
      addTearDown(token.cancel);
      final summary = NovelSummary(key: contractNovel, title: '合成书');
      final chapter = contractContent('正文');
      final progress = ReadingProgress(
        snapshot: summary,
        chapterKey: contractChapter,
        chapterOrdinalSnapshot: 0,
        catalogRevision: 'catalog',
        completed: false,
        lastReadAt: contractNow,
        position: ReaderPosition(
          contentRevision: chapter.contentRevision,
          blockKey: chapter.blocks.first.blockKey,
          blockIndex: 0,
          blockFraction: 0,
          chapterFraction: 0,
        ),
      );
      final firstGeneration = value(
        await library.beginProgressSession(
          contractNovel,
          cancellation: token.token,
        ),
      );
      expect(
        value(
          await library.saveProgress(
            progress,
            stamp: ProgressWriteStamp(generation: firstGeneration, sequence: 2),
            cancellation: token.token,
          ),
        ),
        true,
      );
      expect(
        value(
          await library.saveProgress(
            progress,
            stamp: ProgressWriteStamp(generation: firstGeneration, sequence: 1),
            cancellation: token.token,
          ),
        ),
        false,
      );
      final entry = BookshelfEntry(snapshot: summary, addedAt: contractNow);
      await library.putBookshelf(entry, cancellation: token.token);
      final repeated = value(
        await library.putBookshelf(
          BookshelfEntry(
            snapshot: summary,
            addedAt: contractNow.add(const Duration(days: 1)),
          ),
          cancellation: token.token,
        ),
      );
      expect(repeated.addedAt, entry.addedAt);
      expect(
        value(
          await library.removeFromBookshelf(
            contractNovel,
            cancellation: token.token,
          ),
        ),
        entry,
      );
      expect(
        value(
          await library.getProgress(contractNovel, cancellation: token.token),
        ),
        progress,
      );
      await library.putBookshelf(
        entry,
        cancellation: token.token,
      ); // Undo keeps addedAt.
      final newerGeneration = value(
        await library.beginProgressSession(
          contractNovel,
          cancellation: token.token,
        ),
      );
      expect(
        value(
          await library.saveProgress(
            progress,
            stamp: ProgressWriteStamp(
              generation: firstGeneration,
              sequence: 99,
            ),
            cancellation: token.token,
          ),
        ),
        false,
      );
      await library.clearHistory(contractNovel, cancellation: token.token);
      expect(
        value(
          await library.saveProgress(
            progress,
            stamp: ProgressWriteStamp(
              generation: newerGeneration,
              sequence: 99,
            ),
            cancellation: token.token,
          ),
        ),
        false,
      );
      expect(
        value(
          await library.getProgress(contractNovel, cancellation: token.token),
        ),
        isNull,
      );
      final shelf = value(await library.watchBookshelf().first);
      expect(shelf, [entry]);
      expect(() => shelf.clear(), throwsUnsupportedError);
      expect(value(await library.watchRecentReading().first), isEmpty);
    },
  );
  test(
    'Result preserves nullable success, typed failure, map and cancellation',
    () {
      expect(value(const Success<int?>(null)), isNull);
      expect(value(const Success(2).map((v) => '$v')), '2');
      final error = AppFailure(
        kind: FailureKind.cache,
        operation: Operation.chapter,
      );
      final mapped = Failure<int>(error).map((v) => v * 2);
      expect(failure(mapped), same(error));
      expect(
        Failure<int>(AppFailure.cancelled(Operation.search)).isCancelled,
        true,
      );
      expect(const Success<int?>(null).isCancelled, false);
    },
  );

  test(
    'failure vocabulary contains no raw response/cause and constrains retry',
    () {
      final error = AppFailure(
        kind: FailureKind.accessRestricted,
        operation: Operation.chapter,
        context: FailureContext.challengeRequired,
      );
      expect(jsonEncode(error.toJson()), isNot(contains('SECRET')));
      expect(error.toJson().keys, isNot(contains('message')));
      expect(error.toJson().keys, isNot(contains('cause')));
      expect(
        () => AppFailure(
          kind: FailureKind.network,
          operation: Operation.search,
          diagnosticId: 'https://example.invalid/?token=SECRET',
        ),
        throwsArgumentError,
      );
      for (final kind in [
        FailureKind.cancelled,
        FailureKind.parse,
        FailureKind.rateLimited,
        FailureKind.accessRestricted,
      ]) {
        expect(
          () => AppFailure(
            kind: kind,
            operation: Operation.search,
            retryPolicy: RetryPolicy.boundedAutomatic,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => AppFailure(
          kind: FailureKind.session,
          operation: Operation.search,
          retryPolicy: RetryPolicy.confirmedSessionRecovery,
        ),
        throwsArgumentError,
      );
      expect(
        AppFailure(
          kind: FailureKind.session,
          operation: Operation.search,
          retryPolicy: RetryPolicy.confirmedSessionRecovery,
          context: FailureContext.sessionExpired,
        ).retryPolicy,
        RetryPolicy.confirmedSessionRecovery,
      );
      final limited = AppFailure(
        kind: FailureKind.rateLimited,
        operation: Operation.search,
        retryPolicy: RetryPolicy.manual,
        retryNotBefore: contractNow.add(const Duration(minutes: 1)),
      );
      expect(limited.retryNotBefore!.isUtc, true);
    },
  );

  test(
    'cancellation is observable before/after registering and idempotent',
    () async {
      final source = CancellationSource();
      final notification = source.token.whenCancelled;
      source.cancel();
      source.cancel();
      expect(source.token.isCancelled, true);
      await notification;
      await source.token.whenCancelled;
      final fake = ContractSource();
      expect(
        (await fake.getChapter(
          contractChapter,
          cancellation: source.token,
        )).isCancelled,
        true,
      );
      expect(fake.chapterCalls, 0);
    },
  );

  test(
    'search cursor binds Source/query, has a real terminal empty page',
    () async {
      final fake = ContractSource();
      final token = CancellationSource();
      addTearDown(token.cancel);
      final first = value(await fake.search('合成', cancellation: token.token));
      expect(first.items, hasLength(1));
      expect(() => first.items.clear(), throwsUnsupportedError);
      final last = value(
        await fake.search(
          '合成',
          cursor: first.nextCursor,
          cancellation: token.token,
        ),
      );
      expect(last.items, isEmpty);
      expect(last.nextCursor, isNull);
      final wrong = await fake.search(
        '别的查询',
        cursor: first.nextCursor,
        cancellation: token.token,
      );
      expect(failure(wrong).context, FailureContext.invalidCursor);
      final foreign = await fake.search(
        '合成',
        cursor: SearchCursor(
          sourceId: SourceId('other'),
          opaqueValue: first.nextCursor!.opaqueValue,
        ),
        cancellation: token.token,
      );
      expect(failure(foreign).context, FailureContext.invalidCursor);
      expect(
        failure(await fake.discover(cancellation: token.token)).kind,
        FailureKind.unsupported,
      );
      expect(
        () => SearchPage(
          sourceId: contractSourceId,
          items: [],
          nextCursor: first.nextCursor,
        ),
        throwsArgumentError,
      );
      expect(
        () => SearchPage(
          sourceId: contractSourceId,
          items: [...first.items, ...first.items],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'stale load requires retained cache data and a non-cancellation refresh failure',
    () {
      final error = AppFailure(
        kind: FailureKind.network,
        operation: Operation.chapter,
      );
      final stale = LoadResult(
        value: contractContent('旧'),
        origin: LoadOrigin.local,
        fetchedAt: contractNow,
        isStale: true,
        refreshFailure: error,
      );
      expect(stale.value.blocks, hasLength(1));
      expect(stale.refreshFailure, error);
      expect(
        () => LoadResult(
          value: 1,
          origin: LoadOrigin.remote,
          fetchedAt: contractNow,
          isStale: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => LoadResult(
          value: 1,
          origin: LoadOrigin.local,
          fetchedAt: contractNow,
          refreshFailure: error,
        ),
        throwsArgumentError,
      );
      expect(
        () => LoadResult(
          value: 1,
          origin: LoadOrigin.local,
          fetchedAt: contractNow,
          isStale: true,
          refreshFailure: AppFailure.cancelled(Operation.chapter),
        ),
        throwsArgumentError,
      );
    },
  );

  test('cacheOnly hit and miss perform no Source operation', () async {
    final source = ContractSource();
    final repo = ContractNovelRepository(source);
    final token = CancellationSource();
    addTearDown(repo.close);
    addTearDown(token.cancel);
    final miss = await repo.loadChapter(
      contractChapter,
      mode: ReadMode.cacheOnly,
      cancellation: token.token,
    );
    expect(failure(miss).context, FailureContext.cacheMiss);
    repo.cached = contractContent('旧');
    final hit = value(
      await repo.loadChapter(
        contractChapter,
        mode: ReadMode.cacheOnly,
        cancellation: token.token,
      ),
    );
    expect(hit.isStale, true);
    expect(hit.origin, LoadOrigin.memory);
    expect(source.chapterCalls, 0);
  });

  test(
    'stale cache returns promptly, refresh is deduplicated and delivered explicitly',
    () async {
      final source = ContractSource()..pendingChapter = Completer();
      final repo = ContractNovelRepository(source)
        ..cached = contractContent('旧');
      final token = CancellationSource();
      addTearDown(repo.close);
      addTearDown(token.cancel);
      final next = repo
          .chapterUpdates(contractChapter)
          .first; // Subscribe before load.
      expect(source.chapterCalls, 0);
      final first = value(
        await repo.loadChapter(
          contractChapter,
          mode: ReadMode.cacheFirst,
          cancellation: token.token,
        ),
      );
      await repo.loadChapter(
        contractChapter,
        mode: ReadMode.cacheFirst,
        cancellation: token.token,
      );
      expect(first.isStale, true);
      expect(source.chapterCalls, 1);
      source.pendingChapter!.complete(Success(contractContent('新')));
      final refreshed = value(await next);
      expect(refreshed.isStale, false);
      expect(refreshed.origin, LoadOrigin.remote);
      expect(
        refreshed.value.contentRevision,
        isNot(first.value.contentRevision),
      );
      expect(
        first.isStale,
        true,
      ); // Original immutable observation was not mutated.
    },
  );

  test(
    'failed refresh reports stale success through update and load result',
    () async {
      final source = ContractSource()..pendingChapter = Completer();
      final old = contractContent('缓存正文');
      final repo = ContractNovelRepository(source)..cached = old;
      final token = CancellationSource();
      addTearDown(repo.close);
      addTearDown(token.cancel);
      final event = repo.chapterUpdates(contractChapter).first;
      final loading = repo.loadChapter(
        contractChapter,
        mode: ReadMode.refresh,
        cancellation: token.token,
      );
      final error = AppFailure(
        kind: FailureKind.network,
        operation: Operation.chapter,
      );
      source.pendingChapter!.complete(Failure(error));
      final result = value(await loading);
      expect(result.value, same(old));
      expect(result.refreshFailure, error);
      expect(result.isStale, true);
      expect(value(await event).refreshFailure, error);
      expect(repo.cached, same(old));
    },
  );

  test(
    'one caller cancellation does not abort another shared consumer',
    () async {
      final source = ContractSource()..pendingChapter = Completer();
      final repo = ContractNovelRepository(source);
      final first = CancellationSource();
      final second = CancellationSource();
      addTearDown(repo.close);
      addTearDown(first.cancel);
      addTearDown(second.cancel);
      final a = repo.loadChapter(
        contractChapter,
        mode: ReadMode.refresh,
        cancellation: first.token,
      );
      final b = repo.loadChapter(
        contractChapter,
        mode: ReadMode.refresh,
        cancellation: second.token,
      );
      first.cancel();
      expect((await a).isCancelled, true);
      source.pendingChapter!.complete(Success(contractContent('完成')));
      expect((await b).isSuccess, true);
      expect(source.chapterCalls, 1);
    },
  );

  test(
    'media bounds are terminal typed failures and the body closes once',
    () async {
      final source = ContractSource();
      final token = CancellationSource();
      addTearDown(token.cancel);
      final body =
          value(
                await source.openMedia(
                  contractMedia,
                  maxBytes: 3,
                  cancellation: token.token,
                ),
              )
              as ContractBody;
      final chunks = await body.chunks.toList();
      expect(value(chunks.first), [1, 2]);
      expect(() => value(chunks.first).clear(), throwsUnsupportedError);
      expect(failure(chunks.last).kind, FailureKind.tooLarge);
      expect(chunks, hasLength(2));
      expect(body.closed, true);
      await body.close();
      expect(body.closeCount, 1);
      expect(() => body.chunks, throwsStateError);
    },
  );

  test(
    'media cancellation and abandoning unopened body release ownership',
    () async {
      final source = ContractSource();
      final token = CancellationSource();
      final body =
          value(
                await source.openMedia(
                  contractMedia,
                  maxBytes: 4,
                  cancellation: token.token,
                ),
              )
              as ContractBody;
      token.cancel();
      expect((await body.chunks.first).isCancelled, true);
      await body.close();
      expect(body.closed, true);
      final unusedToken = CancellationSource();
      addTearDown(unusedToken.cancel);
      final unused = value(
        await source.openMedia(
          contractMedia,
          maxBytes: 4,
          cancellation: unusedToken.token,
        ),
      );
      await unused.close();
      await unused.close();
      expect((unused as ContractBody).closeCount, 1);
    },
  );

  test(
    'one ImageRepository port supports memory/file leases and accurate persistence',
    () async {
      final source = ContractSource();
      final repo = ContractImageRepository(source);
      final token = CancellationSource();
      addTearDown(token.cancel);
      expect(
        failure(
          await repo.load(
            contractMedia,
            mode: ReadMode.cacheOnly,
            cancellation: token.token,
          ),
        ).kind,
        FailureKind.cache,
      );
      expect(source.mediaCalls, 0);
      repo.writeFailure = AppFailure(
        kind: FailureKind.cache,
        operation: Operation.media,
        context: FailureContext.cacheWriteFailed,
      );
      final online = value(
        await repo.load(
          contractMedia,
          mode: ReadMode.refresh,
          cancellation: token.token,
        ),
      );
      expect(online.origin, LoadOrigin.remote);
      expect(online.value.persistence, MediaPersistence.memoryOnly);
      expect(online.value.persistenceFailure, repo.writeFailure);
      final memory = online.value.data as MemoryMedia;
      expect(() => memory.bytes[0] = 9, throwsUnsupportedError);
      final second = value(
        await repo.load(
          contractMedia,
          mode: ReadMode.cacheOnly,
          cancellation: token.token,
        ),
      ).value;
      await online.value.close();
      await online.value.close();
      expect(second.isClosed, false);
      expect(second.data, isA<MemoryMedia>());
      expect(() => online.value.data, throwsStateError);
      await second.close();
      repo.localPath =
          'synthetic-app-private/image.bin'; // Fake handle; no file created.
      final local = value(
        await repo.load(
          contractMedia,
          mode: ReadMode.cacheOnly,
          cancellation: token.token,
        ),
      );
      expect(local.value.data, isA<LocalMedia>());
      expect(local.value.persistence, MediaPersistence.persistedLocal);
      expect(local.origin, LoadOrigin.local);
      expect(source.mediaCalls, 1);
      await local.value.close();
    },
  );

  test('memory media snapshots copy bytes and validate declared lengths', () {
    final bytes = Uint8List.fromList([1, 2]);
    final data = MemoryMedia(
      bytes: bytes,
      info: MediaInfo(format: MediaFormat.png, byteLength: 2),
    );
    bytes[0] = 9;
    expect(data.bytes, [1, 2]);
    expect(
      () => MemoryMedia(
        bytes: bytes,
        info: MediaInfo(format: MediaFormat.png, byteLength: 3),
      ),
      throwsArgumentError,
    );
    expect(
      () => MediaInfo(format: MediaFormat.unknown, width: 0),
      throwsArgumentError,
    );
  });

  test(
    'settings interface preserves typed values and cancelled saves do not commit',
    () async {
      final SettingsStore store = ContractSettings();
      final token = CancellationSource();
      final changed = ReaderSettings(fontSize: 24);
      expect(
        (await store.save(changed, cancellation: token.token)).isSuccess,
        true,
      );
      expect(value(await store.load(cancellation: token.token)), changed);
      token.cancel();
      expect(
        (await store.save(
          ReaderSettings(),
          cancellation: token.token,
        )).isCancelled,
        true,
      );
      expect((store as ContractSettings).settings, changed);
      expect(
        () => ProgressWriteStamp(generation: -1, sequence: 0),
        throwsArgumentError,
      );
    },
  );
}
