import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';

const png = [137, 80, 78, 71, 13, 10, 26, 10];

class Body implements SourceMediaBody {
  Body({
    this.bytes = png,
    MediaFormat format = MediaFormat.png,
    int? length,
    this.error,
    this.rawError = false,
  }) : info = MediaInfo(format: format, byteLength: length);
  final List<int> bytes;
  final AppFailure? error;
  final bool rawError;
  @override
  final MediaInfo info;
  @override
  int get maxBytes => 1000;
  int closes = 0;
  @override
  Stream<Result<List<int>>> get chunks async* {
    if (rawError) throw StateError('SECRET');
    if (error != null) {
      yield Failure(error!);
      return;
    }
    yield Success(bytes);
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

class Source implements SourceMedia {
  Source(this.open);
  final Future<Result<SourceMediaBody>> Function() open;
  int calls = 0;
  final tokens = <CancellationToken>[];
  @override
  Future<Result<SourceMediaBody>> openMedia(
    MediaRef ref, {
    required int maxBytes,
    required CancellationToken cancellation,
  }) {
    calls++;
    tokens.add(cancellation);
    return open();
  }
}

MediaLease lease(Result<LoadResult<MediaLease>> result) =>
    (result as Success<LoadResult<MediaLease>>).value.value;

void main() {
  test(
    'shared loads have independent leases; cacheOnly never resolves source; last close frees RAM',
    () async {
      final env = FixtureEnvironment();
      var resolutions = 0;
      final repository = MemoryImageRepository(
        resolve: (_) {
          resolutions++;
          return env.source;
        },
      );
      final ref = fixtureMediaRef(0);
      final cancel = CancellationSource();
      final miss = await repository.load(
        ref,
        mode: ReadMode.cacheOnly,
        cancellation: cancel.token,
      );
      expect((miss as Failure).failure.context, FailureContext.cacheMiss);
      expect(resolutions, 0);
      final one = repository.load(
        ref,
        mode: ReadMode.cacheFirst,
        cancellation: cancel.token,
      );
      final two = repository.load(
        ref,
        mode: ReadMode.cacheFirst,
        cancellation: CancellationSource().token,
      );
      final a = lease(await one);
      final b = lease(await two);
      expect(resolutions, 1);
      expect(a, isNot(same(b)));
      expect(a.data, same(b.data));
      expect(a.persistence, MediaPersistence.memoryOnly);
      expect(a.persistenceFailure, isNull);
      expect(repository.retainedBytes, greaterThan(0));
      final cache = lease(
        await repository.load(
          ref,
          mode: ReadMode.cacheOnly,
          cancellation: cancel.token,
        ),
      );
      await a.close();
      await a.close();
      await cache.close();
      expect(repository.retainedBytes, greaterThan(0));
      await b.close();
      expect(repository.retainedBytes, 0);
      expect(
        (await repository.load(
          ref,
          mode: ReadMode.cacheOnly,
          cancellation: cancel.token,
        )).isSuccess,
        isFalse,
      );
      expect(resolutions, 1);
      repository.close();
      await env.close();
    },
  );

  test(
    'one cancelled waiter does not abort others; last cancellation closes late body',
    () async {
      var pending = Completer<Result<SourceMediaBody>>();
      final source = Source(() => pending.future);
      final repository = MemoryImageRepository(resolve: (_) => source);
      final cancel = CancellationSource();
      final first = repository.load(
        fixtureMediaRef(0),
        mode: ReadMode.refresh,
        cancellation: cancel.token,
      );
      final second = repository.load(
        fixtureMediaRef(0),
        mode: ReadMode.refresh,
        cancellation: CancellationSource().token,
      );
      cancel.cancel();
      expect((await first as Failure).failure.isCancellation, isTrue);
      expect(source.tokens.single.isCancelled, isFalse);
      final body = Body();
      pending.complete(Success(body));
      final value = lease(await second);
      await value.close();
      await Future<void>.delayed(Duration.zero);
      expect(body.closes, 1);
      pending = Completer<Result<SourceMediaBody>>();
      final last = CancellationSource();
      final future = repository.load(
        fixtureMediaRef(1),
        mode: ReadMode.refresh,
        cancellation: last.token,
      );
      last.cancel();
      expect((await future as Failure).failure.isCancellation, isTrue);
      expect(source.tokens.last.isCancelled, isTrue);
      final lateBody = Body();
      pending.complete(Success(lateBody));
      await Future<void>.delayed(Duration.zero);
      expect(lateBody.closes, 1);
      expect(repository.retainedBytes, 0);
      repository.close();
    },
  );

  test(
    'format, length, empty, limit and terminal/raw stream failures release body',
    () async {
      for (final body in [
        Body(format: MediaFormat.unknown),
        Body(bytes: []),
        Body(length: 100),
        Body(bytes: [...png, ...png]),
        Body(bytes: [1, 2, 3]),
        Body(length: 7),
        Body(rawError: true),
        Body(
          error: AppFailure(
            kind: FailureKind.network,
            operation: Operation.media,
          ),
        ),
      ]) {
        final source = Source(() async => Success(body));
        final repository = MemoryImageRepository(
          resolve: (_) => source,
          maxBytes: 8,
        );
        final result = await repository.load(
          fixtureMediaRef(0),
          mode: ReadMode.refresh,
          cancellation: CancellationSource().token,
        );
        expect(result, isA<Failure<LoadResult<MediaLease>>>());
        await Future<void>.delayed(Duration.zero);
        expect(body.closes, 1);
        expect(repository.retainedBytes, 0);
        expect(repository.pendingCount, 0);
        repository.close();
      }
    },
  );

  test(
    'failed refresh retains readable old independent lease with stale observation',
    () async {
      var fail = false;
      final source = Source(
        () async => fail
            ? Failure(
                AppFailure(
                  kind: FailureKind.network,
                  operation: Operation.media,
                ),
              )
            : Success(Body()),
      );
      final repository = MemoryImageRepository(resolve: (_) => source);
      final old = lease(
        await repository.load(
          fixtureMediaRef(0),
          mode: ReadMode.cacheFirst,
          cancellation: CancellationSource().token,
        ),
      );
      fail = true;
      final refresh = await repository.load(
        fixtureMediaRef(0),
        mode: ReadMode.refresh,
        cancellation: CancellationSource().token,
      );
      final result = (refresh as Success<LoadResult<MediaLease>>).value;
      expect(result.isStale, isTrue);
      expect(result.refreshFailure!.kind, FailureKind.network);
      expect(result.origin, LoadOrigin.memory);
      expect(result.value.data, same(old.data));
      await old.close();
      await result.value.close();
      expect(repository.retainedBytes, 0);
      repository.close();
    },
  );

  test(
    'encoded RAM budget queues work until lease release; queue stays bounded',
    () async {
      final source = Source(() async => Success(Body()));
      final repository = MemoryImageRepository(
        resolve: (_) => source,
        maxBytes: 8,
        maxRetainedBytes: 8,
      );
      final first = lease(
        await repository.load(
          fixtureMediaRef(0),
          mode: ReadMode.refresh,
          cancellation: CancellationSource().token,
        ),
      );
      final futures = [
        for (var i = 1; i <= 20; i++)
          repository.load(
            fixtureMediaRef(i),
            mode: ReadMode.refresh,
            cancellation: CancellationSource().token,
          ),
      ];
      final overflow = await repository.load(
        fixtureMediaRef(21),
        mode: ReadMode.refresh,
        cancellation: CancellationSource().token,
      );
      expect(overflow.isSuccess, isFalse);
      expect(repository.pendingCount, 20);
      expect(source.calls, 1);
      await first.close();
      for (final future in futures) {
        final current = lease(await future);
        expect(repository.retainedBytes, 8);
        await current.close();
      }
      expect(repository.retainedBytes, 0);
      repository.close();
    },
  );

  test(
    'deadline completes even when Source open never returns; dispose cancels queued waiters',
    () {
      fakeAsync((async) {
        final source = Source(
          () => Completer<Result<SourceMediaBody>>().future,
        );
        final repository = MemoryImageRepository(
          resolve: (_) => source,
          deadline: const Duration(seconds: 2),
        );
        Result<LoadResult<MediaLease>>? result;
        repository
            .load(
              fixtureMediaRef(0),
              mode: ReadMode.refresh,
              cancellation: CancellationSource().token,
            )
            .then((v) => result = v);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect((result as Failure).failure.kind, FailureKind.timeout);
        expect(source.tokens.single.isCancelled, isTrue);
        expect(repository.pendingCount, 0);
        repository
            .load(
              fixtureMediaRef(1),
              mode: ReadMode.refresh,
              cancellation: CancellationSource().token,
            )
            .then((v) => result = v);
        repository.close();
        async.flushMicrotasks();
        expect((result as Failure).failure.isCancellation, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    },
  );
}
