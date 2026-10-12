import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/cache/cache_policy.dart';
import 'package:shiori/data/cache/local_cache_management.dart';
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/data/media/persistent_image_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'memory_image_repository_test.dart' show Source, Body, lease;

void main() {
  late Directory root;
  late AppPaths paths;
  late CacheDatabase db;
  late CacheCoordinator owner;
  late PersistentImageRepository repo;
  late Source source;
  final ref = MediaRef(sourceId: SourceId('fixture'), mediaId: 'image');
  Future<Result<LoadResult<MediaLease>>> get([
    ReadMode mode = ReadMode.cacheFirst,
  ]) => repo.load(ref, mode: mode, cancellation: CancellationSource().token);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shiori-image-test-');
    paths = AppPaths(
      support: root,
      temporary: root,
      environment: StorageEnvironment.development,
    );
    await paths.prepare();
    db = CacheDatabase(NativeDatabase(paths.cacheDatabase));
    owner = CacheCoordinator();
    source = Source(() async => Success(Body()));
    repo = CountingImages(
      network: MemoryImageRepository(resolve: (_) => source),
      db: db,
      paths: paths,
      coordinator: owner,
    );
  });
  tearDown(() async {
    await repo.close();
    await owner.close();
    await db.close();
    await root.delete(recursive: true);
  });
  test(
    'overview verifies each shared image once and rechecks the next inspection',
    () async {
      final active = lease(await get());
      final file = File((active.data as LocalMedia).path);
      await active.close();
      final key = NovelKey(sourceId: ref.sourceId, novelId: 'shared');
      final missing = MediaRef(sourceId: ref.sourceId, mediaId: 'missing');
      final records = NovelRecordStore(db);
      for (var i = 0; i < 30; i++) {
        await records.writeChapter(
          ChapterContent(
            key: ChapterKey(novelKey: key, chapterId: '$i'),
            title: '$i',
            blocks: [
              ImageBlock(media: ref),
              ImageBlock(media: missing),
            ],
          ),
          fetchedAt: DateTime.utc(2026),
          parserVersion: 1,
          cancellation: CancellationSource().token,
        );
      }
      final counting = repo as CountingImages;
      counting.loads.clear();
      final control = LocalCacheManagement(db, owner, repo);
      final overview =
          (await control.inspect() as Success<CacheOverview>).value;
      expect(overview.chapters, hasLength(30));
      expect(
        overview.chapters.every((c) => c.imageCount == 2 && c.savedImages == 1),
        true,
      );
      expect(counting.loads, {ref: 1, missing: 1});
      await file.writeAsBytes(List.filled(8, 0));
      final next = (await control.inspect() as Success<CacheOverview>).value;
      expect(next.chapters.every((c) => c.savedImages == 0), true);
      expect(counting.loads, {ref: 2, missing: 2});
      expect(source.calls, 1);
      expect(await control.clear(), isA<Success>());
      await repo.maintain();
      expect(await file.exists(), false);
    },
  );
  test('restart reads verified local file with zero network', () async {
    final first = lease(await get());
    expect(first.persistence, MediaPersistence.persistedLocal);
    await first.close();
    await repo.close();
    await db.close();
    db = CacheDatabase(NativeDatabase(paths.cacheDatabase));
    repo = PersistentImageRepository(
      network: MemoryImageRepository(
        resolve: (_) => throw StateError('offline'),
      ),
      db: db,
      paths: paths,
      coordinator: owner,
    );
    final reopened = lease(await get(ReadMode.cacheOnly));
    expect(reopened.data, isA<LocalMedia>());
    await reopened.close();
    expect(source.calls, 1);
  });
  test('clear invalidates index but does not remove a leased file', () async {
    final active = lease(await get());
    final file = File((active.data as LocalMedia).path);
    final control = LocalCacheManagement(db, owner, repo);
    expect(await control.clear(), isA<Success>());
    expect(await file.exists(), isTrue);
    expect(await get(ReadMode.cacheOnly), isA<Failure>());
    await active.close();
    await repo.maintain();
    expect(await file.exists(), isFalse);
  });
  test('checksum corruption becomes an isolated offline miss', () async {
    final first = lease(await get());
    final file = File((first.data as LocalMedia).path);
    await first.close();
    await file.writeAsBytes(List.filled(8, 0));
    expect(await get(ReadMode.cacheOnly), isA<Failure>());
    expect(source.calls, 1);
    final repaired = lease(await get(ReadMode.refresh));
    expect(repaired.persistence, MediaPersistence.persistedLocal);
    await repaired.close();
    final verified = lease(await get(ReadMode.cacheOnly));
    await verified.close();
  });
  test('late network result after clear never persists', () async {
    final pending = Completer<Result<SourceMediaBody>>();
    source = Source(() => pending.future);
    final result = get();
    while (source.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(await LocalCacheManagement(db, owner, repo).clear(), isA<Success>());
    pending.complete(Success(Body()));
    expect(await result, isA<Failure>());
    expect(await db.customSelect('SELECT * FROM image_cache').get(), isEmpty);
  });
  test('refresh failure retains independently leased previous file', () async {
    final first = lease(await get());
    source = Source(
      () async => Failure(
        AppFailure(kind: FailureKind.network, operation: Operation.media),
      ),
    );
    final result =
        (await get(ReadMode.refresh) as Success<LoadResult<MediaLease>>).value;
    expect(result.isStale, isTrue);
    expect(first.isClosed, isFalse);
    await first.close();
    await result.value.close();
  });
  test('invalid image path does not read outside managed images', () async {
    final first = lease(await get());
    await first.close();
    await db.customStatement(
      "UPDATE image_cache SET file_name='../users/users.sqlite'",
    );
    expect(await get(ReadMode.cacheOnly), isA<Failure>());
  });
  test(
    'failed atomic write stays memory-only and never appears offline',
    () async {
      await paths.staging.delete();
      await File(paths.staging.path).writeAsString('fixture blocks staging');
      final value = lease(await get());
      expect(value.persistence, MediaPersistence.memoryOnly);
      expect(value.persistenceFailure, isNotNull);
      await value.close();
      expect(await get(ReadMode.cacheOnly), isA<Failure>());
      expect(await db.customSelect('SELECT * FROM image_cache').get(), isEmpty);
    },
  );
  test('bad decoded input cannot become a persisted success', () async {
    repo.validate = (_) async =>
        throw const FormatException('fixture invalid PNG');
    final value = lease(await get());
    expect(value.persistence, MediaPersistence.memoryOnly);
    await value.close();
    expect(await get(ReadMode.cacheOnly), isA<Failure>());
  });
  test(
    'missing image is isolated; independent concurrent callers have independent leases',
    () async {
      final values = await Future.wait([get(), get()]);
      final first = lease(values[0]), second = lease(values[1]);
      expect(source.calls, 1);
      await first.close();
      expect(second.isClosed, isFalse);
      final file = File((second.data as LocalMedia).path);
      await second.close();
      await file.delete();
      expect(await get(ReadMode.cacheOnly), isA<Failure>());
    },
  );
  test('orphan sweep continues beyond first bounded batch', () async {
    for (var i = 0; i < 150; i++) {
      await File('${paths.images.path}/orphan-$i').writeAsString('fixture');
    }
    await repo.maintain();
    expect(await paths.images.list().length, 22);
    await repo.maintain();
    expect(await paths.images.list().length, 0);
  });
  test('clear one book preserves an image shared with another book', () async {
    final value = lease(await get());
    await value.close();
    final stable = PersistentImageRepository.keyFor(ref);
    for (final id in ['one', 'two']) {
      await db.customStatement('INSERT INTO image_owners VALUES(?,?,?)', [
        stable,
        'fixture',
        id,
      ]);
    }
    final cache = LocalCacheManagement(db, owner, repo);
    await cache.clear(
      novel: NovelKey(sourceId: ref.sourceId, novelId: 'one'),
    );
    final other = lease(await get(ReadMode.cacheOnly));
    await other.close();
    await cache.clear(
      novel: NovelKey(sourceId: ref.sourceId, novelId: 'two'),
    );
    expect(await get(ReadMode.cacheOnly), isA<Failure>());
  });
}

class CountingImages extends PersistentImageRepository {
  CountingImages({
    required super.network,
    required super.db,
    required super.paths,
    required super.coordinator,
  });
  final loads = <MediaRef, int>{};
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    loads.update(ref, (count) => count + 1, ifAbsent: () => 1);
    return super.load(ref, mode: mode, cancellation: cancellation);
  }
}
