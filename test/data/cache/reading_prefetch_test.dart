import 'dart:async';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/cache/cache_policy.dart';
import 'package:shiori/data/repositories/library_repository.dart';
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
  final tokens = <CancellationToken>[];
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
    tokens.add(cancellation);
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

class GatedUsers extends UserDatabase {
  GatedUsers() : super(NativeDatabase.memory());
  final generations = <Completer<int>>[];
  final queried = <(String, String)>[];
  @override
  Future<int> removalGeneration(String source, String novel) {
    queried.add((source, novel));
    return generations.isEmpty
        ? super.removalGeneration(source, novel)
        : generations.removeAt(0).future;
  }
}

void main() {
  late GatedUsers users;
  late CacheCoordinator owner;
  late Novels novels;
  late Images images;
  late LocalReadingPrefetch engine;
  setUp(() {
    users = GatedUsers();
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

  for (final failed in [false, true]) {
    test(
      'late initialization keeps the newer choice with failed query=$failed',
      () async {
        await users.customStatement(
          'INSERT INTO prefetch_choices VALUES(?,?,?,?),(?,?,?,?)',
          [
            book.sourceId.value,
            book.novelId,
            'volume1',
            'translation2',
            book.sourceId.value,
            book.novelId,
            'special',
            'volume3',
          ],
        );
        final initial = Completer<int>()..complete(0);
        final validation = Completer<int>();
        users.generations.addAll([initial, validation]);
        images.gate = Completer<void>();
        final old = engine.enter(content('volume1'), catalog());
        for (var i = 0; i < 500 && users.queried.length < 2; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(users.queried, hasLength(2));
        await engine.enter(content('special', 1), catalog());
        expect(engine.state.target, key('volume3'));
        if (failed) {
          validation.completeError(StateError('retired query failed'));
        } else {
          validation.complete(0);
        }
        await old;
        images.gate!.complete();
        await settle(engine);
        expect(engine.state.target, key('volume3'));
        expect(engine.state.failures, 0);
        expect(novels.calls, [key('volume3')]);
        expect(images.calls, ['special-0', 'volume3-0', 'volume3-1']);
      },
    );
  }

  for (final newerFirst in [false, true]) {
    test(
      'latest enter wins with newer query finishing first=$newerFirst',
      () async {
        final a = Completer<int>(), b = Completer<int>();
        users.generations.addAll([a, b]);
        final first = engine.enter(content('volume1', 1), catalog());
        final second = engine.enter(content('special', 1), catalog());
        if (newerFirst) {
          b.complete(0);
          await second;
          await settle(engine);
          a.complete(0);
          await first;
        } else {
          a.complete(0);
          await first;
          expect(images.calls, isEmpty);
          b.complete(0);
          await second;
          await settle(engine);
        }
        expect(images.calls, ['special-0']);
        expect(await engine.select(key('volume1')), isA<Success>());
        expect(await engine.select(key('special')), isA<Failure>());
      },
    );
  }

  for (final action in ['leave', 'remove', 'close']) {
    test(
      '$action invalidates enter waiting for its first generation query',
      () async {
        final gate = Completer<int>();
        users.generations.add(gate);
        final entering = engine.enter(content('volume1', 1), catalog());
        switch (action) {
          case 'leave':
            engine.leave();
          case 'remove':
            expect(
              await LocalLibraryRepository(users).removeOnlineBook(
                book,
                cancellation: CancellationSource().token,
              ),
              isA<Success>(),
            );
          case 'close':
            await engine.close();
        }
        gate.complete(0);
        await entering;
        expect(images.calls, isEmpty);
        expect(novels.calls, isEmpty);
        expect(engine.state.phase, PrefetchPhase.idle);
        expect(await engine.select(key('special')), isA<Failure>());
      },
    );
  }

  test('unrelated removal does not discard the pending enter', () async {
    final gate = Completer<int>();
    users.generations.add(gate);
    final entering = engine.enter(content('volume1', 1), catalog());
    users.notifyRemoved(book.sourceId.value, 'another-book');
    gate.complete(0);
    await entering;
    await settle(engine);
    expect(images.calls, ['volume1-0']);
  });

  test('same chapter notifications keep in-flight prefetch running', () async {
    images.gate = Completer<void>();
    await engine.enter(content('volume1', 1), catalog());
    while (images.calls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final a = Completer<int>(), b = Completer<int>();
    users.generations.addAll([a, b]);
    final first = engine.enter(content('volume1', 1), catalog());
    final second = engine.enter(content('volume1', 1), catalog());
    a.complete(0);
    await first;
    b.complete(0);
    await second;
    expect(images.tokens.single.isCancelled, isFalse);
    images.gate!.complete();
    await settle(engine);
    expect(images.calls, ['volume1-0']);
    expect(images.leases.single.isClosed, isFalse);
  });

  test(
    'stale enter query failure cannot overwrite newer prefetch state',
    () async {
      final a = Completer<int>(), b = Completer<int>();
      users.generations.addAll([a, b]);
      final first = engine.enter(content('volume1', 1), catalog());
      final second = engine.enter(content('special', 1), catalog());
      a.completeError(StateError('old generation query failed'));
      await first;
      b.complete(0);
      await second;
      await settle(engine);
      expect(images.calls, ['special-0']);
      expect(engine.state.failures, 0);
      expect(engine.state.phase, PrefetchPhase.complete);
    },
  );
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
      await LocalLibraryRepository(users).putBookshelf(
        BookshelfEntry(
          snapshot: NovelSummary(key: book, title: 'Owned'),
          addedAt: DateTime.utc(2026),
        ),
        cancellation: CancellationSource().token,
      );
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
    'unowned choices stay transient; removal cancels old work and new reading can choose',
    () async {
      final library = LocalLibraryRepository(users);
      final token = CancellationSource().token;
      await engine.enter(content('volume1'), catalog());
      await settle(engine);
      expect(await engine.select(key('volume3')), isA<Success>());
      await settle(engine);
      expect(
        await users.customSelect('SELECT * FROM prefetch_choices').get(),
        isEmpty,
      );
      await library.putBookshelf(
        BookshelfEntry(
          snapshot: NovelSummary(key: book, title: 'Owned'),
          addedAt: DateTime.utc(2026),
        ),
        cancellation: token,
      );
      images.gate = Completer<void>();
      await engine.enter(content('special', 2), catalog());
      expect(await engine.select(key('volume3')), isA<Success>());
      expect(
        await users.customSelect('SELECT * FROM prefetch_choices').get(),
        hasLength(1),
      );
      expect(
        await library.removeOnlineBook(book, cancellation: token),
        isA<Success>(),
      );
      expect(await engine.select(key('volume3')), isA<Failure>());
      images.gate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        await users.customSelect('SELECT * FROM prefetch_choices').get(),
        isEmpty,
      );
      await library.putBookshelf(
        BookshelfEntry(
          snapshot: NovelSummary(key: book, title: 'Owned again'),
          addedAt: DateTime.utc(2026),
        ),
        cancellation: token,
      );
      images.gate = null;
      await engine.enter(content('volume1'), catalog());
      expect(await engine.select(key('volume3')), isA<Success>());
      await settle(engine);
      expect(
        await users.customSelect('SELECT * FROM prefetch_choices').get(),
        hasLength(1),
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
