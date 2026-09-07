import 'dart:async';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/cache/cache_policy.dart';
import 'package:shiori/data/cache/reading_prefetch.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/network/background_work.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';

final book = NovelKey(sourceId: SourceId('fixture'), novelId: 'series');
ChapterKey key(String id) => ChapterKey(novelKey: book, chapterId: id);
ChapterContent content(String id, [int count = 0]) => ChapterContent(
  key: key(id),
  title: id,
  blocks: [
    ParagraphBlock(text: 'Fixture'),
    for (var i = 0; i < count; i++)
      ImageBlock(
        media: MediaRef(sourceId: book.sourceId, mediaId: '$id-$i'),
      ),
  ],
);
Catalog catalog([
  List<String> ids = const ['volume1', 'translation2', 'special', 'volume3'],
]) => Catalog(
  novelKey: book,
  volumes: [
    Volume(
      groupId: 'g',
      title: 'Fixture versions',
      chapters: [
        for (var i = 0; i < ids.length; i++)
          Chapter(
            key: key(ids[i]),
            title: ids[i],
            ordinal: i,
            volumeGroupId: 'g',
          ),
      ],
    ),
  ],
);

class Novels implements NovelRepository {
  final calls = <ChapterKey>[];
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    calls.add(key);
    return Success(
      LoadResult(
        value: content(key.chapterId, 2),
        origin: LoadOrigin.remote,
        fetchedAt: DateTime.utc(2026),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Images implements ImageRepository {
  final calls = <String>[];
  final leases = <Lease>[];
  Completer<void>? gate;
  FailureKind? failure;
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    calls.add(ref.mediaId);
    BackgroundWork.current!.budget.attempt();
    if (gate != null) {
      await Future.any([gate!.future, cancellation.whenCancelled]);
    }
    if (cancellation.isCancelled) {
      return Failure(AppFailure.cancelled(Operation.media));
    }
    if (failure != null) {
      return Failure(AppFailure(kind: failure!, operation: Operation.media));
    }
    final lease = Lease();
    leases.add(lease);
    return Success(
      LoadResult(
        value: lease,
        origin: LoadOrigin.local,
        fetchedAt: DateTime.utc(2026),
      ),
    );
  }
}

class Lease implements MediaLease {
  @override
  bool isClosed = false;
  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  MediaData get data => MemoryMedia(
    bytes: Uint8List(1),
    info: MediaInfo(format: MediaFormat.png, byteLength: 1),
  );
  @override
  MediaPersistence get persistence => MediaPersistence.persistedLocal;
  @override
  AppFailure? get persistenceFailure => null;
}

Future<void> settle(LocalReadingPrefetch engine) async {
  for (var i = 0; i < 500; i++) {
    await Future<void>.delayed(Duration.zero);
    if (engine.state.phase != PrefetchPhase.running &&
        engine.state.phase != PrefetchPhase.idle) {
      return;
    }
  }
  fail('Prefetch failed to settle');
}

void main() {
  late UserDatabase users;
  late CacheCoordinator owner;
  late Novels novels;
  late Images images;
  late LocalReadingPrefetch engine;
  setUp(() {
    users = UserDatabase(NativeDatabase.memory());
    owner = CacheCoordinator();
    novels = Novels();
    images = Images();
    engine = LocalReadingPrefetch(
      users: users,
      novels: novels,
      images: images,
      coordinator: owner,
    );
  });
  tearDown(() async {
    await engine.close();
    await owner.close();
    await users.close();
  });
  test(
    'unknown relationships never select ordinal; all current images precede one chosen target',
    () async {
      await engine.enter(content('volume1', 8), catalog());
      await settle(engine);
      expect(images.calls, hasLength(8));
      expect(novels.calls, isEmpty);
      expect(await engine.select(key('volume3')), isA<Success>());
      await settle(engine);
      expect(novels.calls, [key('volume3')]);
      expect(images.calls.skip(8), ['volume3-0', 'volume3-1']);
      expect(engine.state.target, key('volume3'));
      expect(
        await users.customSelect('SELECT * FROM reading_progress').get(),
        isEmpty,
      );
    },
  );
  test(
    'selection survives controller recreation; missing refreshed target is removed',
    () async {
      await engine.enter(content('volume1'), catalog());
      await settle(engine);
      await engine.select(key('volume3'));
      await settle(engine);
      await engine.close();
      engine = LocalReadingPrefetch(
        users: users,
        novels: novels,
        images: images,
        coordinator: owner,
      );
      await engine.enter(content('volume1'), null);
      await settle(engine);
      expect(engine.state.target, key('volume3'));
      await engine.enter(content('volume1'), catalog(['volume1', 'special']));
      await settle(engine);
      expect(engine.state.target, isNull);
      expect(
        await users.customSelect('SELECT * FROM prefetch_choices').get(),
        isEmpty,
      );
    },
  );
  test(
    'budget does not reset on navigation or lifecycle; explicit resume retries',
    () async {
      engine.budget.attempts = 198;
      await engine.enter(content('volume1', 10), catalog());
      await settle(engine);
      expect(images.calls, hasLength(2));
      expect(engine.state.phase, PrefetchPhase.budget);
      engine.active(false);
      engine.active(true);
      await engine.enter(content('special', 3), catalog());
      await settle(engine);
      expect(images.calls, hasLength(2));
      engine.resume();
      await settle(engine);
      expect(images.calls, hasLength(5));
    },
  );
  test(
    'clear cancels pending work and does not refill until explicit resume',
    () async {
      images.gate = Completer<void>();
      await engine.enter(content('volume1', 5), catalog());
      while (images.calls.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      owner.invalidate();
      await settle(engine);
      images.gate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(images.calls, hasLength(1));
      expect(engine.state.phase, PrefetchPhase.paused);
      expect(images.leases, isEmpty);
      engine.resume();
      await settle(engine);
      expect(images.calls, hasLength(6));
    },
  );
  test(
    'jump reprioritizes next four and previous image; retained leases stay bounded',
    () async {
      images.gate = Completer<void>();
      await engine.enter(content('volume1', 20), catalog());
      while (images.calls.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      engine.position(15);
      images.gate!.complete();
      await settle(engine);
      expect(images.calls[1], 'volume1-14');
      expect(
        images.leases.where((l) => !l.isClosed).length,
        lessThanOrEqualTo(5),
      );
      engine.leave();
      await Future<void>.delayed(Duration.zero);
      expect(images.leases.every((l) => l.isClosed), isTrue);
    },
  );
  test(
    '429 pauses whole batch; ordinary image failure does not loop',
    () async {
      images.failure = FailureKind.rateLimited;
      await engine.enter(content('volume1', 5), catalog());
      await settle(engine);
      expect(images.calls, hasLength(1));
      expect(engine.state.phase, PrefetchPhase.paused);
      images.failure = FailureKind.network;
      engine.resume();
      await settle(engine);
      expect(images.calls, hasLength(6));
      expect(engine.state.phase, PrefetchPhase.partial);
      await engine.enter(content('volume1', 5), catalog());
      await settle(engine);
      expect(images.calls, hasLength(6));
    },
  );
  test('disabled current and next persist and never request images', () async {
    await engine.configure(current: false, next: false);
    await engine.enter(content('volume1', 6), catalog());
    await settle(engine);
    await engine.select(key('translation2'));
    await settle(engine);
    expect(images.calls, isEmpty);
    expect(novels.calls, isEmpty);
  });
}
