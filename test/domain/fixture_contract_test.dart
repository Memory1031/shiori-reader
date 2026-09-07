import 'dart:async';
import 'dart:io';

import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:test/test.dart';

T value<T>(Result<T> result) => (result as Success<T>).value;
AppFailure error<T>(Result<T> result) => (result as Failure<T>).failure;
CancellationToken token() => CancellationSource().token;

final class NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Fixture attempted external IO');
  }
}

void main() {
  test('all scenarios traverse official contracts without external IO', () async {
    final guard = NoNetwork();
    await HttpOverrides.runWithHttpOverrides(() async {
      for (final scenario in FixtureScenario.values) {
        final env = FixtureEnvironment(scenario: scenario);
        try {
          final key = fixtureNovelKey(scenario);
          final detail = value(
            await env.novels.loadDetail(
              key,
              mode: ReadMode.refresh,
              cancellation: token(),
            ),
          );
          expect(detail.value.summary.key, key);
          final catalog = value(
            await env.novels.loadCatalog(
              key,
              mode: ReadMode.refresh,
              cancellation: token(),
            ),
          ).value;
          expect(catalog.flatChapters, isNotEmpty);
          final chapter = value(
            await env.novels.loadChapter(
              catalog.flatChapters.first.key,
              mode: ReadMode.refresh,
              cancellation: token(),
            ),
          ).value;
          expect(chapter.key.novelKey, key);
          expect(chapter.blocks, isNotEmpty);
          expect(scenario.labelZh, isNotEmpty);
          expect(scenario.labelEn, isNotEmpty);
        } finally {
          await env.close();
        }
      }
    }, guard);
    expect(guard.attempts, 0);
    expect(
      () => HttpOverrides.runWithHttpOverrides(HttpClient.new, guard),
      throwsStateError,
    );
    // Fail closed for future transports (including direct sockets), not only HttpClient.
    for (final file in Directory(
      'lib/dev',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final imports = RegExp(
        r'''(?:import|export)\s+['"]([^'"]+)['"]''',
      ).allMatches(file.readAsStringSync()).map((match) => match[1]!);
      for (final uri in imports) {
        expect(
          uri.startsWith('dart:')
              ? {'dart:async', 'dart:convert', 'dart:typed_data'}.contains(uri)
              : uri.startsWith('../domain/') ||
                    uri.startsWith('package:shiori/domain/') ||
                    uri.startsWith('fixture'),
          isTrue,
          reason: '${file.path}: $uri',
        );
      }
    }
    // The production composition graph contains no fixture import.
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.dart') &&
                  !f.path.replaceAll('\\', '/').contains('/dev/'),
            )) {
      expect(
        file.readAsStringSync(),
        isNot(contains('dev/fixture')),
        reason: file.path,
      );
    }
  });

  test(
    'stable seed, exact stress shapes and content revisions preserve identity',
    () {
      const data = FixtureData(seed: 42);
      final long = data.content(FixtureScenario.longChapter);
      expect(long.blocks.length, 2000);
      expect(
        long.blocks.cast<ParagraphBlock>().fold<int>(
          0,
          (sum, p) => sum + p.text.runes.length,
        ),
        100000,
      );
      final single = data.content(FixtureScenario.extremeParagraph);
      expect(single.blocks.length, 1);
      expect(
        (single.blocks.single as ParagraphBlock).text.runes.length,
        100000,
      );
      final normal = data.content(FixtureScenario.shortChapter);
      expect(
        normal,
        const FixtureData(seed: 42).content(FixtureScenario.shortChapter),
      );
      expect(
        normal.contentRevision,
        isNot(
          const FixtureData(
            seed: 43,
          ).content(FixtureScenario.shortChapter).contentRevision,
        ),
      );
      final revised = data.content(FixtureScenario.shortChapter, revision: 1);
      expect(normal.key, revised.key);
      expect(normal.contentRevision, isNot(revised.contentRevision));
      expect(normal.blocks.first.blockKey, revised.blocks[1].blockKey);
      expect(fixturePng(40, 60, 42), fixturePng(40, 60, 42));
      expect(fixturePng(40, 60, 42), isNot(fixturePng(40, 60, 43)));
    },
  );

  test('catalog shapes, typography and image-only semantics', () {
    const data = FixtureData();
    final multi = data.catalog(FixtureScenario.multiVolume);
    expect(multi.volumes.length, 3);
    expect(multi.volumes.last.title, contains('Extras'));
    expect(
      multi.flatChapters.map((c) => c.ordinal),
      List.generate(9, (i) => i),
    );
    expect(
      data.catalog(FixtureScenario.noVolume).volumes.single.isSynthetic,
      isTrue,
    );
    final unnamed = data
        .catalog(FixtureScenario.missingVolumeName)
        .volumes
        .single;
    expect(unnamed.title, isNull);
    expect(unnamed.isSynthetic, isFalse);
    final text = data
        .content(FixtureScenario.typography)
        .blocks
        .whereType<ParagraphBlock>();
    expect(text.any((p) => p.text.isEmpty), isTrue);
    expect(text.any((p) => p.alignment == ParagraphAlignment.center), isTrue);
    expect(text.any((p) => p.leadingIndent == 2), isTrue);
    expect(text.first.text, contains('こんにちは'));
    expect(
      data.content(FixtureScenario.singleImage).blocks.single,
      isA<ImageBlock>(),
    );
    final images = data
        .content(FixtureScenario.twentyImages)
        .blocks
        .cast<ImageBlock>();
    expect(images.map((i) => (i.width, i.height)).toSet().length, 20);
    final unknown =
        data.content(FixtureScenario.unknownImageSize).blocks.single
            as ImageBlock;
    expect(unknown.width, isNull);
    expect(unknown.height, isNull);
  });

  test(
    'search pages terminate with unique IDs and bound opaque cursors',
    () async {
      final source = FixtureNovelSource();
      final found = <NovelKey>{};
      SearchCursor? cursor;
      do {
        final page = value(
          await source.search('', cursor: cursor, cancellation: token()),
        );
        for (final item in page.items) {
          expect(found.add(item.key), isTrue);
        }
        cursor = page.nextCursor;
      } while (cursor != null);
      expect(found.length, FixtureScenario.values.length);
      final first = value(await source.search('', cancellation: token()));
      expect(
        error(
          await source.search(
            'short',
            cursor: first.nextCursor,
            cancellation: token(),
          ),
        ).context,
        FailureContext.invalidCursor,
      );
      expect(
        value(await source.search('no-such-book', cancellation: token())).items,
        isEmpty,
      );
      final replay = FixtureNovelSource(
        scenario: FixtureScenario.repeatedCursor,
      );
      final page = value(await replay.search('', cancellation: token()));
      expect(
        error(
          await replay.search(
            '',
            cursor: page.nextCursor,
            cancellation: token(),
          ),
        ).context,
        FailureContext.repeatedPage,
      );
      expect(
        value(
          await FixtureNovelSource(
            scenario: FixtureScenario.emptySearch,
          ).search('', cancellation: token()),
        ).nextCursor,
        isNull,
      );
      expect(
        value(await source.discover(cancellation: token())).single.items.length,
        FixtureScenario.values.length,
      );
    },
  );

  test('deletion and revision controls change source snapshots only', () async {
    final source = FixtureNovelSource(scenario: FixtureScenario.revisedContent);
    final key = fixtureChapterKey(FixtureScenario.revisedContent);
    final old = value(await source.getChapter(key, cancellation: token()));
    source.controls.revision = 1;
    final revised = value(await source.getChapter(key, cancellation: token()));
    expect(old.contentRevision, isNot(revised.contentRevision));
    source.controls.chapterDeleted = true;
    expect(
      error(await source.getChapter(key, cancellation: token())).kind,
      FailureKind.notFound,
    );
    expect(
      value(
        await source.getCatalog(key.novelKey, cancellation: token()),
      ).flatChapters.any((c) => c.key == key),
      isFalse,
    );
    expect(old.blocks.length, 8);
  });

  test(
    'fail-next controls, cancellation before work and during delay',
    () async {
      final source = FixtureNovelSource();
      final key = fixtureChapterKey(FixtureScenario.shortChapter);
      final cancelled = CancellationSource()..cancel();
      expect(
        (await source.getChapter(
          key,
          cancellation: cancelled.token,
        )).isCancelled,
        isTrue,
      );
      expect(source.controls.calls, isEmpty);
      source.controls.failNext(
        AppFailure(
          kind: FailureKind.timeout,
          operation: Operation.chapter,
          retryPolicy: RetryPolicy.manual,
        ),
      );
      expect(
        error(await source.getChapter(key, cancellation: token())).kind,
        FailureKind.timeout,
      );
      expect(
        (await source.getChapter(key, cancellation: token())).isSuccess,
        isTrue,
      );
      source.controls.delays[Operation.chapter] = const Duration(seconds: 30);
      final cancel = CancellationSource();
      final pending = source.getChapter(key, cancellation: cancel.token);
      cancel.cancel();
      expect(
        (await pending.timeout(const Duration(seconds: 1))).isCancelled,
        isTrue,
      );
    },
  );

  test(
    'all novel cacheOnly reads are silent, per-key streams have no initial IO',
    () async {
      final env = FixtureEnvironment();
      final key = fixtureNovelKey(FixtureScenario.shortChapter);
      final events = <Object>[];
      final sub = env.novels.detailUpdates(key).listen(events.add);
      expect(events, isEmpty);
      expect(env.source.controls.calls, isEmpty);
      expect(
        error(
          await env.novels.loadDetail(
            key,
            mode: ReadMode.cacheOnly,
            cancellation: token(),
          ),
        ).context,
        FailureContext.cacheMiss,
      );
      expect(
        error(
          await env.novels.loadCatalog(
            key,
            mode: ReadMode.cacheOnly,
            cancellation: token(),
          ),
        ).context,
        FailureContext.cacheMiss,
      );
      expect(
        error(
          await env.novels.loadChapter(
            fixtureChapterKey(FixtureScenario.shortChapter),
            mode: ReadMode.cacheOnly,
            cancellation: token(),
          ),
        ).context,
        FailureContext.cacheMiss,
      );
      expect(env.source.controls.calls, isEmpty);
      await sub.cancel();
      await env.close();
    },
  );

  test(
    'stale refresh deduplicates, publishes revisions and retains failed cache',
    () async {
      final env = FixtureEnvironment();
      final key = fixtureChapterKey(FixtureScenario.revisedContent);
      final first = value(
        await env.novels.loadChapter(
          key,
          mode: ReadMode.refresh,
          cancellation: token(),
        ),
      );
      env.novels.markStale();
      env.source.controls.revision = 1;
      env.source.controls.delays[Operation.chapter] = const Duration(
        milliseconds: 10,
      );
      final update = env.novels.chapterUpdates(key).first;
      final stale = value(
        await env.novels.loadChapter(
          key,
          mode: ReadMode.cacheFirst,
          cancellation: token(),
        ),
      );
      final cancel = CancellationSource();
      final a = env.novels.loadChapter(
        key,
        mode: ReadMode.refresh,
        cancellation: cancel.token,
      );
      final b = env.novels.loadChapter(
        key,
        mode: ReadMode.refresh,
        cancellation: token(),
      );
      cancel.cancel();
      expect((await a).isCancelled, isTrue);
      final fresh = value(await b);
      expect(stale.isStale, isTrue);
      expect(stale.fetchedAt, first.fetchedAt);
      expect(value(await update).value, fresh.value);
      expect(fresh.value.contentRevision, isNot(first.value.contentRevision));
      expect(env.source.controls.calls[Operation.chapter], 2);
      env.source.controls.failNext(
        AppFailure(kind: FailureKind.network, operation: Operation.chapter),
      );
      final failed = value(
        await env.novels.loadChapter(
          key,
          mode: ReadMode.refresh,
          cancellation: token(),
        ),
      );
      expect(failed.isStale, isTrue);
      expect(failed.refreshFailure!.kind, FailureKind.network);
      expect(failed.fetchedAt, fresh.fetchedAt);
      await env.close();
    },
  );

  test(
    'detail and catalog caches notify only their key and close suppresses late writes',
    () async {
      final env = FixtureEnvironment();
      final key = fixtureNovelKey(FixtureScenario.shortChapter);
      final detailEvent = env.novels.detailUpdates(key).first;
      final catalogEvent = env.novels.catalogUpdates(key).first;
      await env.novels.loadDetail(
        key,
        mode: ReadMode.refresh,
        cancellation: token(),
      );
      await env.novels.loadCatalog(
        key,
        mode: ReadMode.refresh,
        cancellation: token(),
      );
      expect((await detailEvent).isSuccess, isTrue);
      expect((await catalogEvent).isSuccess, isTrue);
      final events = <Object>[];
      final sub = env.novels
          .chapterUpdates(fixtureChapterKey(FixtureScenario.shortChapter))
          .listen(events.add);
      env.source.controls.delays[Operation.chapter] = const Duration(
        seconds: 30,
      );
      final pending = env.novels.loadChapter(
        fixtureChapterKey(FixtureScenario.shortChapter),
        mode: ReadMode.refresh,
        cancellation: token(),
      );
      await env.close();
      expect((await pending).isCancelled, isTrue);
      expect(events, isEmpty);
      await sub.cancel();
    },
  );

  test(
    'media stream terminal failure retries real PNG and enforces cumulative bound',
    () async {
      final source = FixtureNovelSource(scenario: FixtureScenario.failingImage);
      final ref = fixtureMediaRef(0);
      final failedBody = value(
        await source.openMedia(ref, maxBytes: 100000, cancellation: token()),
      );
      final chunks = await failedBody.chunks.toList();
      expect(chunks.first, isA<Success<List<int>>>());
      expect(error(chunks.last).retryPolicy, RetryPolicy.manual);
      expect(source.activeBodies, 0);
      await failedBody.close();
      final body = value(
        await source.openMedia(ref, maxBytes: 1500, cancellation: token()),
      );
      final limited = await body.chunks.toList();
      expect(error(limited.last).kind, FailureKind.tooLarge);
      expect(
        limited.whereType<Success<List<int>>>().fold<int>(
          0,
          (n, c) => n + c.value.length,
        ),
        lessThanOrEqualTo(1500),
      );
      expect(source.activeBodies, 0);
      final unopened = value(
        await source.openMedia(ref, maxBytes: 100000, cancellation: token()),
      );
      await unopened.close();
      await unopened.close();
      expect(source.activeBodies, 0);
      final foreign = MediaRef(
        sourceId: SourceId('other'),
        mediaId: ref.mediaId,
      );
      expect(
        error(
          await source.openMedia(
            foreign,
            maxBytes: 100000,
            cancellation: token(),
          ),
        ).kind,
        FailureKind.notFound,
      );
    },
  );

  test(
    'media cancellation and consumer cancellation release slow bodies',
    () async {
      final source = FixtureNovelSource(scenario: FixtureScenario.slowImage);
      source.controls.mediaChunkDelay = const Duration(seconds: 30);
      final cancel = CancellationSource();
      final body = value(
        await source.openMedia(
          fixtureMediaRef(0),
          maxBytes: 100000,
          cancellation: cancel.token,
        ),
      );
      final read = body.chunks.toList();
      cancel.cancel();
      expect(
        error(
          (await read.timeout(const Duration(seconds: 1))).single,
        ).isCancellation,
        isTrue,
      );
      expect(source.activeBodies, 0);
      source.controls.mediaChunkDelay = Duration.zero;
      final next = value(
        await source.openMedia(
          fixtureMediaRef(0),
          maxBytes: 100000,
          cancellation: token(),
        ),
      );
      await next.chunks.take(1).drain<void>();
      expect(source.activeBodies, 0);
    },
  );

  test(
    'image cache uses independent memory leases, cache miss silent, retry works',
    () async {
      final env = FixtureEnvironment(scenario: FixtureScenario.failingImage);
      final ref = fixtureMediaRef(0);
      expect(
        error(
          await env.images.load(
            ref,
            mode: ReadMode.cacheOnly,
            cancellation: token(),
          ),
        ).context,
        FailureContext.cacheMiss,
      );
      expect(env.source.controls.calls, isEmpty);
      expect(
        error(
          await env.images.load(
            ref,
            mode: ReadMode.refresh,
            cancellation: token(),
          ),
        ).kind,
        FailureKind.network,
      );
      final a = value(
        await env.images.load(
          ref,
          mode: ReadMode.refresh,
          cancellation: token(),
        ),
      );
      final b = value(
        await env.images.load(
          ref,
          mode: ReadMode.cacheOnly,
          cancellation: token(),
        ),
      );
      expect(a.value.persistence, MediaPersistence.memoryOnly);
      expect(b.origin, LoadOrigin.memory);
      await a.value.close();
      expect(b.value.isClosed, isFalse);
      expect(() => a.value.data, throwsStateError);
      expect(
        () => (b.value.data as MemoryMedia).bytes[0] = 0,
        throwsUnsupportedError,
      );
      env.source.controls.failNext(
        AppFailure(kind: FailureKind.network, operation: Operation.media),
      );
      final stale = value(
        await env.images.load(
          ref,
          mode: ReadMode.refresh,
          cancellation: token(),
        ),
      );
      expect(stale.isStale, isTrue);
      expect(stale.fetchedAt, a.fetchedAt);
      final cachedStale = value(
        await env.images.load(
          ref,
          mode: ReadMode.cacheOnly,
          cancellation: token(),
        ),
      );
      expect(cachedStale.isStale, isTrue);
      expect(cachedStale.refreshFailure!.kind, FailureKind.network);
      await cachedStale.value.close();
      await stale.value.close();
      await b.value.close();
      await env.close();
      expect(env.source.activeBodies, 0);
    },
  );

  test(
    'closing image repository during open or streaming leaves no body',
    () async {
      for (final duringOpen in [true, false]) {
        final env = FixtureEnvironment();
        if (duringOpen) {
          env.source.controls.delays[Operation.media] = const Duration(
            seconds: 30,
          );
        } else {
          env.source.controls.mediaChunkDelay = const Duration(seconds: 30);
        }
        final pending = env.images.load(
          fixtureMediaRef(0),
          mode: ReadMode.refresh,
          cancellation: token(),
        );
        await Future<void>.delayed(Duration.zero);
        await env.close();
        expect(
          (await pending.timeout(const Duration(seconds: 1))).isCancelled,
          isTrue,
        );
        expect(env.source.activeBodies, 0);
      }
    },
  );

  test(
    'library and settings implement local writes, failure switches and history isolation',
    () async {
      final env = FixtureEnvironment();
      final summary = env.source.data.summary(FixtureScenario.shortChapter);
      expect(value(await env.library.watchBookshelf().first), isEmpty);
      final entry = BookshelfEntry(snapshot: summary, addedAt: fixtureEpoch);
      value(await env.library.putBookshelf(entry, cancellation: token()));
      final duplicate = value(
        await env.library.putBookshelf(
          BookshelfEntry(
            snapshot: summary,
            addedAt: fixtureEpoch.add(const Duration(days: 1)),
          ),
          cancellation: token(),
        ),
      );
      expect(duplicate.addedAt, fixtureEpoch);
      final generation = value(
        await env.library.beginProgressSession(
          summary.key,
          cancellation: token(),
        ),
      );
      final content = env.source.data.content(FixtureScenario.shortChapter);
      final progress = ReadingProgress(
        snapshot: summary,
        chapterKey: content.key,
        chapterOrdinalSnapshot: 0,
        catalogRevision: env.source.data
            .catalog(FixtureScenario.shortChapter)
            .revision,
        completed: false,
        position: ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks.first.blockKey,
          blockIndex: 0,
          blockFraction: 0,
          chapterFraction: 0,
        ),
        lastReadAt: fixtureEpoch,
      );
      final stamp = ProgressWriteStamp(generation: generation, sequence: 1);
      expect(
        value(
          await env.library.saveProgress(
            progress,
            stamp: stamp,
            cancellation: token(),
          ),
        ),
        isTrue,
      );
      expect(
        value(
          await env.library.saveProgress(
            progress,
            stamp: stamp,
            cancellation: token(),
          ),
        ),
        isFalse,
      );
      await env.library.removeFromBookshelf(summary.key, cancellation: token());
      expect(
        value(
          await env.library.getProgress(summary.key, cancellation: token()),
        ),
        progress,
      );
      await env.library.clearHistory(summary.key, cancellation: token());
      expect(
        value(
          await env.library.saveProgress(
            progress,
            stamp: ProgressWriteStamp(generation: generation, sequence: 2),
            cancellation: token(),
          ),
        ),
        isFalse,
      );
      env.library.controls.failNext(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.libraryWrite,
        ),
      );
      expect(
        error(
          await env.library.putBookshelf(entry, cancellation: token()),
        ).kind,
        FailureKind.database,
      );
      await env.settings.save(
        ReaderSettings(fontSize: 24),
        cancellation: token(),
      );
      env.settings.controls.failNext(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.settingsWrite,
        ),
      );
      expect(
        (await env.settings.save(
          ReaderSettings(),
          cancellation: token(),
        )).isSuccess,
        isFalse,
      );
      expect(
        value(await env.settings.load(cancellation: token())).fontSize,
        24,
      );
      expect(env.source.controls.calls, isEmpty);
      await env.close();
    },
  );
}
