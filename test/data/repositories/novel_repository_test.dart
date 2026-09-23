import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/repositories/novel_repository.dart';
import 'package:shiori/data/sources/source_registry.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/app_logger.dart';
import '../../support/contract_fakes.dart';

T value<T>(Result<T> result) => (result as Success<T>).value;
CancellationToken get token => CancellationSource().token;
Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

class Source implements NovelSource {
  Source([SourceId? id]) : id = id ?? contractSourceId;
  final SourceId id;
  int chapterCalls = 0, searchCalls = 0, discoverCalls = 0;
  CancellationToken? lastToken;
  Completer<Result<ChapterContent>>? pending;
  bool throws = false, wrongIdentity = false;
  Completer<Result<SearchPage>>? pendingSearch;
  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    sourceId: id,
    displayName: 'fixture',
    supportsDiscover: true,
    supportsSearchPaging: true,
  );
  NovelKey get novel => NovelKey(sourceId: id, novelId: 'book');
  @override
  Future<Result<List<DiscoverSection>>> discover({
    required CancellationToken cancellation,
  }) async {
    discoverCalls++;
    return Success([
      DiscoverSection(
        label: 'fixture',
        items: [NovelSummary(key: novel, title: 'Book')],
      ),
    ]);
  }

  @override
  Future<Result<SearchPage>> search(
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) async {
    searchCalls++;
    lastToken = cancellation;
    if (pendingSearch != null) return pendingSearch!.future;
    return Success(
      SearchPage(
        sourceId: id,
        items: [NovelSummary(key: novel, title: query)],
      ),
    );
  }

  @override
  Future<Result<NovelDetail>> getNovelDetail(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async => Success(
    NovelDetail(
      summary: NovelSummary(key: key, title: 'Detail'),
    ),
  );
  @override
  Future<Result<Catalog>> getCatalog(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async => Success(Catalog(novelKey: key, volumes: []));
  @override
  Future<Result<ChapterContent>> getChapter(
    ChapterKey key, {
    required CancellationToken cancellation,
  }) async {
    chapterCalls++;
    lastToken = cancellation;
    if (throws) throw Exception('secret sentinel');
    if (pending != null) return pending!.future;
    return Success(
      ChapterContent(
        key: wrongIdentity
            ? ChapterKey(novelKey: novel, chapterId: 'wrong')
            : key,
        title: id.value,
        blocks: [ParagraphBlock(text: 'remote')],
      ),
    );
  }
}

class BrokenWrites extends NovelRecordStore {
  BrokenWrites(super.db);
  @override
  Future<Result<void>> writeChapter(
    ChapterContent value, {
    required DateTime fetchedAt,
    required int parserVersion,
    DateTime? expiresAt,
    required CancellationToken cancellation,
  }) async => Failure(
    AppFailure(
      kind: FailureKind.cache,
      operation: Operation.chapter,
      context: FailureContext.cacheWriteFailed,
    ),
  );
}

void main() {
  late CacheDatabase db;
  late NovelRecordStore records;
  late Source source;
  late DefaultNovelRepository repo;
  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    records = NovelRecordStore(db);
    source = Source();
    repo = DefaultNovelRepository(
      sources: SourceRegistry([source]),
      records: records,
      now: () => contractNow,
    );
  });
  tearDown(() async {
    await repo.close();
    await db.close();
  });
  Future<void> seed({bool stale = false, int parserVersion = 2}) async {
    value(
      await records.writeChapter(
        contractContent('cached'),
        fetchedAt: contractNow.subtract(const Duration(days: 1)),
        expiresAt: stale ? contractNow : null,
        parserVersion: parserVersion,
        cancellation: token,
      ),
    );
  }

  test(
    'pre-ruby chapter cache remains readable offline and refreshes online',
    () async {
      await seed(parserVersion: 1);
      final offline = value(
        await repo.loadChapter(
          contractChapter,
          mode: ReadMode.cacheOnly,
          cancellation: token,
        ),
      );
      expect(offline.isStale, isTrue);
      expect(source.chapterCalls, 0);
      source.pending = Completer();
      final updated = repo.chapterUpdates(contractChapter).first;
      final cached = value(
        await repo.loadChapter(
          contractChapter,
          mode: ReadMode.cacheFirst,
          cancellation: token,
        ),
      );
      expect(cached.value, offline.value);
      source.pending!.complete(
        Success(contractContent('new ruby-capable content')),
      );
      await updated;
      expect(
        value(
          await records.readChapter(contractChapter, cancellation: token),
        )!.parserVersion,
        2,
      );
    },
  );

  test(
    'registry rejects duplicate identity; queries forward and cursor source is checked',
    () async {
      expect(() => SourceRegistry([source, Source()]), throwsArgumentError);
      expect(repo.sources.descriptors.single.sourceId, contractSourceId);
      expect(
        value(
          await repo.discover(contractSourceId, cancellation: token),
        ).single.items.single.key,
        contractNovel,
      );
      expect(
        value(
          await repo.search(
            contractSourceId,
            'exact query',
            cancellation: token,
          ),
        ).items.single.title,
        'exact query',
      );
      final result = await repo.search(
        contractSourceId,
        'x',
        cursor: SearchCursor(
          sourceId: SourceId('other'),
          opaqueValue: 'private',
        ),
        cancellation: token,
      );
      expect((result as Failure).failure.context, FailureContext.invalidCursor);
      expect(source.searchCalls, 1);
    },
  );
  test(
    'detail catalog chapter normalize into SQLite and cacheOnly has zero Source calls',
    () async {
      final events = <Result<LoadResult<ChapterContent>>>[];
      final sub = repo.chapterUpdates(contractChapter).listen(events.add);
      await tick();
      expect(events, isEmpty);
      expect(source.chapterCalls, 0);
      expect(
        (await repo.loadChapter(
                  contractChapter,
                  mode: ReadMode.cacheOnly,
                  cancellation: token,
                )
                as Failure)
            .failure
            .context,
        FailureContext.cacheMiss,
      );
      expect(
        value(
          await repo.loadDetail(
            contractNovel,
            mode: ReadMode.cacheFirst,
            cancellation: token,
          ),
        ).origin,
        LoadOrigin.remote,
      );
      expect(
        value(
          await repo.loadCatalog(
            contractNovel,
            mode: ReadMode.refresh,
            cancellation: token,
          ),
        ).value.novelKey,
        contractNovel,
      );
      final remote = value(
        await repo.loadChapter(
          contractChapter,
          mode: ReadMode.cacheFirst,
          cancellation: token,
        ),
      );
      expect(remote.origin, LoadOrigin.remote);
      expect(
        value(
          await repo.loadChapter(
            contractChapter,
            mode: ReadMode.cacheOnly,
            cancellation: token,
          ),
        ).value,
        remote.value,
      );
      expect(
        value(
          await repo.loadChapter(
            contractChapter,
            mode: ReadMode.cacheFirst,
            cancellation: token,
          ),
        ).origin,
        LoadOrigin.local,
      );
      expect(
        value(await records.readDetail(contractNovel, cancellation: token)),
        isNotNull,
      );
      expect(
        value(await records.readCatalog(contractNovel, cancellation: token)),
        isNotNull,
      );
      await tick();
      expect(events.length, 1);
      expect(source.chapterCalls, 1);
      await sub.cancel();
    },
  );
  test(
    'missing Source still reads local and refresh retains original timestamp',
    () async {
      await seed();
      await repo.close();
      repo = DefaultNovelRepository(
        sources: SourceRegistry([]),
        records: records,
      );
      final local = value(
        await repo.loadChapter(
          contractChapter,
          mode: ReadMode.cacheOnly,
          cancellation: token,
        ),
      );
      final fallback = value(
        await repo.loadChapter(
          contractChapter,
          mode: ReadMode.refresh,
          cancellation: token,
        ),
      );
      expect(fallback.isStale, true);
      expect(fallback.fetchedAt, local.fetchedAt);
      expect(fallback.refreshFailure!.context, FailureContext.sourceMissing);
      expect(
        await repo.loadDetail(
          contractNovel,
          mode: ReadMode.refresh,
          cancellation: token,
        ),
        isA<Failure>(),
      );
    },
  );
  test(
    'expired cache returns immediately and deduplicates background refresh notifications',
    () async {
      await seed(stale: true);
      source.pending = Completer();
      final event = repo.chapterUpdates(contractChapter).first;
      final first = value(
        await repo.loadChapter(
          contractChapter,
          mode: ReadMode.cacheFirst,
          cancellation: token,
        ),
      );
      final second = value(
        await repo.loadChapter(
          contractChapter,
          mode: ReadMode.cacheFirst,
          cancellation: token,
        ),
      );
      expect(first.isStale && second.isStale, true);
      expect(source.chapterCalls, 1);
      source.pending!.complete(Success(contractContent('new')));
      expect(value(await event).origin, LoadOrigin.remote);
      expect(
        value(
          await records.readChapter(contractChapter, cancellation: token),
        )!.value,
        contractContent('new'),
      );
    },
  );
  test(
    'refresh failure publishes stale data, thrown secrets do not escape',
    () async {
      await seed(stale: true);
      source.throws = true;
      final event = repo.chapterUpdates(contractChapter).first;
      final result = value(
        await repo.loadChapter(
          contractChapter,
          mode: ReadMode.refresh,
          cancellation: token,
        ),
      );
      expect(result.value, contractContent('cached'));
      expect(result.refreshFailure!.kind, FailureKind.sourceUnavailable);
      expect(
        value(await event).refreshFailure.toString(),
        isNot(contains('secret')),
      );
    },
  );
  test(
    'write failure delivers remote content without claiming local persistence',
    () async {
      await repo.close();
      final logger = AppLogger();
      repo = DefaultNovelRepository(
        sources: SourceRegistry([source]),
        records: BrokenWrites(db),
        logger: logger,
      );
      expect(
        value(
          await repo.loadChapter(
            contractChapter,
            mode: ReadMode.refresh,
            cancellation: token,
          ),
        ).origin,
        LoadOrigin.remote,
      );
      expect(
        value(await records.readChapter(contractChapter, cancellation: token)),
        isNull,
      );
      expect(logger.events.single.fields['context'], 'cacheWriteFailed');
    },
  );
  test(
    'cross-source same IDs stay separate; mismatched response never persists',
    () async {
      final other = Source(SourceId('other'));
      await repo.close();
      repo = DefaultNovelRepository(
        sources: SourceRegistry([source, other]),
        records: records,
      );
      final otherKey = ChapterKey(
        novelKey: other.novel,
        chapterId: contractChapter.chapterId,
      );
      await repo.loadChapter(
        contractChapter,
        mode: ReadMode.refresh,
        cancellation: token,
      );
      await repo.loadChapter(
        otherKey,
        mode: ReadMode.refresh,
        cancellation: token,
      );
      expect(
        value(
          await records.readChapter(contractChapter, cancellation: token),
        )!.value.title,
        contractSourceId.value,
      );
      expect(
        value(
          await records.readChapter(otherKey, cancellation: token),
        )!.value.title,
        'other',
      );
      source.wrongIdentity = true;
      final result = value(
        await repo.loadChapter(
          contractChapter,
          mode: ReadMode.refresh,
          cancellation: token,
        ),
      );
      expect(result.refreshFailure!.context, FailureContext.invalidContent);
      expect(result.value.title, contractSourceId.value);
    },
  );
  test(
    'independent cancellation leaves shared consumer and only one Source call',
    () async {
      source.pending = Completer();
      final a = CancellationSource(), b = CancellationSource();
      final first = repo.loadChapter(
        contractChapter,
        mode: ReadMode.refresh,
        cancellation: a.token,
      );
      final second = repo.loadChapter(
        contractChapter,
        mode: ReadMode.refresh,
        cancellation: b.token,
      );
      await tick();
      a.cancel();
      expect((await first as Failure).failure.isCancellation, true);
      expect(source.lastToken!.isCancelled, false);
      source.pending!.complete(Success(contractContent('shared')));
      expect(value(await second).value, contractContent('shared'));
      expect(source.chapterCalls, 1);
    },
  );
  test(
    'last caller cancellation suppresses late write and notification; next generation works',
    () async {
      source.pending = Completer();
      final events = <Result<LoadResult<ChapterContent>>>[];
      final sub = repo.chapterUpdates(contractChapter).listen(events.add);
      final caller = CancellationSource();
      final first = repo.loadChapter(
        contractChapter,
        mode: ReadMode.refresh,
        cancellation: caller.token,
      );
      await tick();
      caller.cancel();
      expect((await first as Failure).failure.isCancellation, true);
      expect(source.lastToken!.isCancelled, true);
      final next = repo.loadChapter(
        contractChapter,
        mode: ReadMode.refresh,
        cancellation: token,
      );
      await tick();
      source.pending!.complete(Success(contractContent('obsolete')));
      source.pending = null;
      expect(
        value(await next).value.blocks,
        isNot(contractContent('obsolete').blocks),
      );
      await tick();
      expect(events.length, 1);
      expect(
        value(
          await records.readChapter(contractChapter, cancellation: token),
        )!.value,
        value(events.single).value,
      );
      await sub.cancel();
    },
  );
  test(
    'pre-cancel does no work and close cancels background then closes notifications',
    () async {
      final caller = CancellationSource()..cancel();
      expect(
        (await repo.loadChapter(
                  contractChapter,
                  mode: ReadMode.refresh,
                  cancellation: caller.token,
                )
                as Failure)
            .failure
            .isCancellation,
        true,
      );
      expect(source.chapterCalls, 0);
      await seed(stale: true);
      source.pending = Completer();
      final events = repo.chapterUpdates(contractChapter).toList();
      await repo.loadChapter(
        contractChapter,
        mode: ReadMode.cacheFirst,
        cancellation: token,
      );
      final closing = repo.close();
      expect(source.lastToken!.isCancelled, true);
      source.pending!.complete(Success(contractContent('late')));
      await closing;
      expect(await events, isEmpty);
      expect(
        value(
          await records.readChapter(contractChapter, cancellation: token),
        )!.value,
        contractContent('cached'),
      );
    },
  );
  test(
    'corrupt cache is typed offline failure and online read repairs it',
    () async {
      await seed();
      await db.customStatement("UPDATE chapter_cache SET payload='invalid'");
      final offline = await repo.loadChapter(
        contractChapter,
        mode: ReadMode.cacheOnly,
        cancellation: token,
      );
      expect(
        (offline as Failure).failure.context,
        FailureContext.invalidContent,
      );
      expect(source.chapterCalls, 0);
      expect(
        value(
          await repo.loadChapter(
            contractChapter,
            mode: ReadMode.cacheFirst,
            cancellation: token,
          ),
        ).origin,
        LoadOrigin.remote,
      );
      expect(
        value(await records.readChapter(contractChapter, cancellation: token)),
        isNotNull,
      );
    },
  );
  test(
    'uncached failure is stream data; cancellation never becomes stale failure',
    () async {
      source.throws = true;
      final event = repo.chapterUpdates(contractChapter).first;
      expect(
        await repo.loadChapter(
          contractChapter,
          mode: ReadMode.refresh,
          cancellation: token,
        ),
        isA<Failure>(),
      );
      expect(await event, isA<Failure>());
      source.throws = false;
      await seed();
      source.pending = Completer();
      final events = <Result<LoadResult<ChapterContent>>>[];
      final sub = repo.chapterUpdates(contractChapter).listen(events.add);
      final caller = CancellationSource();
      final result = repo.loadChapter(
        contractChapter,
        mode: ReadMode.refresh,
        cancellation: caller.token,
      );
      await tick();
      caller.cancel();
      expect((await result as Failure).failure.isCancellation, true);
      source.pending!.complete(
        Failure(AppFailure.cancelled(Operation.chapter)),
      );
      await tick();
      expect(events, isEmpty);
      await sub.cancel();
    },
  );
  test(
    'composition close waits for cancelled query work before releasing borrowed resources',
    () async {
      await repo.close();
      repo = createNovelRepository(
        sources: SourceRegistry([source]),
        cache: db,
      );
      source.pendingSearch = Completer();
      final result = repo.search(contractSourceId, 'q', cancellation: token);
      await tick();
      var closed = false;
      final closing = repo.close().then((_) => closed = true);
      expect((await result as Failure).failure.isCancellation, true);
      expect(source.lastToken!.isCancelled, true);
      expect(closed, false);
      source.pendingSearch!.complete(
        Success(SearchPage(sourceId: contractSourceId, items: [])),
      );
      await closing;
      expect(closed, true);
    },
  );
}
