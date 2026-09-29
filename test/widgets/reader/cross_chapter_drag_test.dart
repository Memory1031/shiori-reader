import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/epub_layout_page.dart';
import 'package:shiori/features/reader/viewport/page_turn.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'restore_test.dart' show ObservedLibrary;
import 'settings_test.dart' show Store;

class Chapters
    implements
        NovelRepository,
        LocalBookInvalidation,
        LocalPagePresentationRepository {
  Chapters(this.inner);
  final NovelRepository inner;
  final events = StreamController<NovelKey>.broadcast();
  final presentations = <ChapterKey, String>{};
  @override
  Stream<NovelKey> get invalidations => events.stream;
  @override
  Stream<NovelKey> get changes => const Stream.empty();
  @override
  Future<Result<String?>> loadPagePresentation(
    ChapterKey key, {
    required CancellationToken cancellation,
  }) async => Success(presentations[key]);

  final requests = <(ChapterKey, ReadMode, CancellationToken)>[];
  final holds = <ChapterKey, Completer<Result<LoadResult<ChapterContent>>>>{};
  final contents = <ChapterKey, ChapterContent>{};
  final cacheMisses = <ChapterKey>{};
  bool cacheMiss = false, forbidOnline = false;
  ChapterContent content(ChapterKey key) =>
      contents[key] ??
      ChapterContent(
        key: key,
        title: 'Title ${key.chapterId}',
        blocks: [ParagraphBlock(text: 'Visible entry ${key.chapterId}')],
      );
  Result<LoadResult<ChapterContent>> result(ChapterKey key) => Success(
    LoadResult(
      value: content(key),
      origin: LoadOrigin.memory,
      fetchedAt: DateTime.utc(2026),
    ),
  );
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    if (forbidOnline && mode != ReadMode.cacheOnly) {
      throw StateError("online chapter forbidden");
    }
    requests.add((key, mode, cancellation));
    if ((cacheMiss || cacheMisses.contains(key)) &&
        mode == ReadMode.cacheOnly) {
      return Failure(
        AppFailure(
          kind: FailureKind.cache,
          operation: Operation.chapter,
          context: FailureContext.cacheMiss,
        ),
      );
    }
    return holds[key]?.future ?? result(key);
  }

  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => inner.loadDetail(key, mode: mode, cancellation: cancellation);
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => inner.loadCatalog(key, mode: mode, cancellation: cancellation);
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      inner.catalogUpdates(key);
  @override
  Stream<Result<LoadResult<ChapterContent>>> chapterUpdates(ChapterKey key) =>
      const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SavingLibrary extends ObservedLibrary {
  SavingLibrary(super.inner);
  Completer<Result<bool>>? save;
  int saveCalls = 0;
  @override
  Future<Result<bool>> saveProgress(
    ReadingProgress progress, {
    required ProgressWriteStamp stamp,
    required CancellationToken cancellation,
  }) async {
    saveCalls++;
    if (save case final held?) {
      final result = await held.future;
      if (result is Failure<bool>) return result;
    }
    return super.saveProgress(
      progress,
      stamp: stamp,
      cancellation: cancellation,
    );
  }
}

class Lease implements MediaLease {
  Lease(this.ref);
  final MediaRef ref;
  @override
  final data = MemoryMedia(
    bytes: fixturePng(16, 16, 3),
    info: MediaInfo(format: MediaFormat.png, width: 16, height: 16),
  );
  @override
  bool isClosed = false;
  @override
  MediaPersistence get persistence => MediaPersistence.memoryOnly;
  @override
  AppFailure? get persistenceFailure => null;
  @override
  Future<void> close() async {
    isClosed = true;
  }
}

class Images implements ImageRepository {
  final requests = <(MediaRef, ReadMode, CancellationToken)>[];
  bool forbidOnline = false, succeed = false;
  final leases = <Lease>[];
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    if (forbidOnline && mode != ReadMode.cacheOnly) {
      throw StateError('network forbidden');
    }
    requests.add((ref, mode, cancellation));
    if (succeed) {
      final lease = Lease(ref);
      leases.add(lease);
      return Success(
        LoadResult(
          value: lease,
          origin: LoadOrigin.memory,
          fetchedAt: DateTime.utc(2026),
        ),
      );
    }
    return Failure(
      AppFailure(
        kind: FailureKind.cache,
        operation: Operation.media,
        context: FailureContext.cacheMiss,
      ),
    );
  }
}

class Prefetch implements ReadingPrefetch {
  final positions = <int>[];
  final entries = <ChapterKey>[];
  @override
  void position(int blockIndex) => positions.add(blockIndex);
  @override
  Future<void> enter(ChapterContent content, Catalog? catalog) async {
    entries.add(content.key);
  }

  @override
  void active(bool value) {}
  @override
  void leave() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Cache implements CacheManagement {
  @override
  final Prefetch prefetch = Prefetch();
  final pins = <ChapterKey>{};
  @override
  void Function() pinChapter(ChapterKey chapter) {
    pins.add(chapter);
    return () => pins.remove(chapter);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Harness {
  final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
  late final repository = Chapters(env.novels);
  late final library = SavingLibrary(env.library);
  final images = Images();
  final cache = Cache();
  final settings = Store()..value = ReaderSettings(controlsHintSeen: true);
  ChapterKey key(int index) =>
      fixtureChapterKey(FixtureScenario.multiVolume, index);
  Future<void> open(
    WidgetTester tester, {
    int index = 0,
    bool offline = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: key(index),
            repository: repository,
            library: library,
            settings: settings,
            images: images,
            cache: cache,
            offline: offline,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await layoutFrames(tester);
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await repository.events.close();
    await env.close();
  }
}

ReaderContentView active(WidgetTester tester) => tester
    .widgetList<ReaderContentView>(
      find.byType(ReaderContentView, skipOffstage: false),
    )
    .singleWhere((w) => w.appearanceActive == true);
PageTurnFrame frame(WidgetTester tester) => tester
    .widgetList<PageTurnSlot>(find.byType(PageTurnSlot, skipOffstage: false))
    .first
    .frame;
Future<void> layoutFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

Future<TestGesture> drag(
  WidgetTester tester,
  int direction, {
  double y = 400,
  double distance = 220,
}) async {
  final gesture = await tester.startGesture(
    Offset(direction > 0 ? 450 : 150, y),
  );
  await gesture.moveBy(Offset(-direction * 24, 0));
  await tester.pump(const Duration(milliseconds: 30));
  await gesture.moveBy(Offset(-direction * distance, 0));
  await layoutFrames(tester);
  return gesture;
}

void main() {
  for (final direction in [1, -1]) {
    testWidgets(
      'held native boundary $direction shows real target without activation and cancels',
      (tester) async {
        final h = Harness();
        await h.open(tester, index: direction > 0 ? 0 : 1);
        final old = active(tester);
        final state = tester.state(find.byType(PagedReaderViewport));
        final sessions = h.library.sessions;
        final gesture = await drag(tester, direction);
        expect(frame(tester).progress, inExclusiveRange(0, 1));
        expect(frame(tester).direction, direction);
        expect(
          find.text('Visible entry ${h.key(direction > 0 ? 1 : 0).chapterId}'),
          findsOneWidget,
        );
        expect(active(tester).session, same(old.session));
        expect(h.library.sessions, sessions);
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(active(tester).session, same(old.session));
        expect(tester.state(find.byType(PagedReaderViewport)), same(state));
        expect(
          find.text('Visible entry ${old.content.key.chapterId}'),
          findsOneWidget,
        );
        expect(h.library.sessions, sessions);
        expect(h.repository.requests.last.$3.isCancelled, isTrue);
        await h.close(tester);
      },
    );
    testWidgets(
      'boundary $direction settles from displayed progress and activates once',
      (tester) async {
        final h = Harness();
        await h.open(tester, index: direction > 0 ? 0 : 1);
        final sessions = h.library.sessions;
        final gesture = await drag(tester, direction);
        final shown = frame(tester).progress;
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.up();
        await layoutFrames(tester);
        expect(frame(tester).progress, greaterThanOrEqualTo(shown));
        expect(h.library.sessions, sessions);
        await tester.pumpAndSettle();
        expect(active(tester).content.key, h.key(direction > 0 ? 1 : 0));
        expect(h.library.sessions, sessions + 1);
        await h.close(tester);
      },
    );
  }
  testWidgets(
    'target arriving during drag uses latest progress; cancelled late result is inert',
    (tester) async {
      final h = Harness();
      final pending = Completer<Result<LoadResult<ChapterContent>>>();
      h.repository.holds[h.key(1)] = pending;
      await h.open(tester);
      final old = active(tester).session;
      final gesture = await drag(tester, 1);
      expect(frame(tester).progress, 0);
      await gesture.moveBy(const Offset(-80, 0));
      pending.complete(h.repository.result(h.key(1)));
      await layoutFrames(tester);
      expect(frame(tester).progress, greaterThan(.45));
      expect(active(tester).session, same(old));
      await gesture.cancel();
      await tester.pumpAndSettle();
      final late = Completer<Result<LoadResult<ChapterContent>>>();
      h.repository.holds[h.key(1)] = late;
      final second = await drag(tester, 1);
      await second.cancel();
      await tester.pumpAndSettle();
      late.complete(h.repository.result(h.key(1)));
      await tester.pumpAndSettle();
      expect(active(tester).session, same(old));
      expect(h.library.sessions, 1);
      expect(frame(tester).progress, 0);
      await h.close(tester);
    },
  );
  for (final direction in [1, -1]) {
    for (final reversal in [false, true]) {
      testWidgets(
        'boundary $direction ${reversal ? "fast reverse" : "small release"} cancels',
        (tester) async {
          final h = Harness();
          await h.open(tester, index: direction > 0 ? 0 : 1);
          final old = active(tester).session;
          final gesture = await drag(
            tester,
            direction,
            distance: reversal ? 350 : 65,
          );
          if (reversal) {
            for (var i = 0; i < 5; i++) {
              await gesture.moveBy(
                Offset(direction * 12, 0),
                timeStamp: Duration(milliseconds: 100 + i * 10),
              );
            }
            expect(frame(tester).progress, greaterThan(.28));
            await gesture.up(timeStamp: const Duration(milliseconds: 145));
          } else {
            await tester.pump(const Duration(milliseconds: 120));
            await gesture.up();
          }
          await tester.pumpAndSettle();
          expect(active(tester).session, same(old));
          expect(h.library.sessions, 1);
          await h.close(tester);
        },
      );
    }
  }
  for (final style in PageTurnStyle.values) {
    testWidgets(
      '$style uses full page grip, never activates at held progress one',
      (tester) async {
        final h = Harness();
        h.settings.value = h.settings.value.copyWith(pageTurn: style);
        await h.open(tester);
        final old = active(tester).session;
        for (final y in [140.0, 400.0, 660.0]) {
          final gesture = await drag(tester, 1, y: y);
          expect(frame(tester).grip, closeTo(y / 800, .015));
          await gesture.moveBy(const Offset(-700, 0));
          await tester.pump();
          expect(frame(tester).progress, 1);
          expect(h.library.sessions, 1);
          expect(active(tester).session, same(old));
          await gesture.cancel();
          await tester.pumpAndSettle();
          expect(active(tester).session, same(old));
        }
        await h.close(tester);
      },
    );
  }
  testWidgets(
    'passive ready is inert, cache only, bounded, and discrete input reuses it',
    (tester) async {
      final h = Harness();
      await h.open(tester);
      final old = active(tester);
      expect(
        h.repository.requests.where((r) => r.$1 == h.key(1)).single.$2,
        ReadMode.cacheOnly,
      );
      expect(h.library.sessions, 1);
      final prefetched = h.cache.prefetch.positions.length;
      final focus = FocusManager.instance.primaryFocus;
      final chrome = old.chrome!.value;
      final views = tester
          .widgetList<ReaderContentView>(
            find.byType(ReaderContentView, skipOffstage: false),
          )
          .toList();
      expect(views.length, 2);
      final target = views.singleWhere((v) => v.appearanceActive == false);
      expect(target.session!.progress, isNull);
      expect(target.active, isFalse);
      expect(target.crossChapterTurning, isFalse);
      expect(h.cache.pins.length, 2);
      target.onReady!();
      target.onReady!();
      old.chrome!.value = !chrome;
      await tester.pumpAndSettle();
      old.chrome!.value = chrome;
      await tester.pumpAndSettle();
      expect(h.repository.requests.length, 2);
      expect(h.cache.prefetch.positions.length, prefetched);
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(h.library.sessions, 1);
      old.actions.nextChapter!();
      await tester.pumpAndSettle();
      expect(active(tester).session, same(target.session));
      expect(h.library.sessions, 2);
      expect(h.repository.requests.where((r) => r.$1 == h.key(1)).length, 1);
      expect(h.cache.prefetch.positions.length, greaterThan(prefetched));
      expect(target.session!.readMode, ReadMode.cacheFirst);
      await h.close(tester);
      expect(h.cache.pins, isEmpty);
    },
  );
  testWidgets('passive cache miss retries only for explicit intent', (
    tester,
  ) async {
    final h = Harness();
    h.repository.cacheMiss = true;
    await h.open(tester);
    final old = active(tester);
    expect(h.repository.requests.length, 2);
    expect(find.text('Retry'), findsNothing);
    old.chrome!.value = true;
    await tester.pumpAndSettle();
    old.chrome!.value = false;
    await tester.pumpAndSettle();
    expect(h.repository.requests.length, 2);
    final gesture = await drag(tester, 1);
    expect(h.repository.requests.last.$2, ReadMode.cacheFirst);
    expect(frame(tester).progress, greaterThan(0));
    await gesture.cancel();
    await tester.pumpAndSettle();
    final count = h.repository.requests.length;
    old.chrome!.value = true;
    await tester.pumpAndSettle();
    expect(h.repository.requests.length, count);
    expect(h.cache.pins, {old.content.key});
    await h.close(tester);
  });
  for (final cancel in [false, true]) {
    testWidgets(
      'release waiting for data ${cancel ? "can cancel" : "commits once"}',
      (tester) async {
        final h = Harness();
        final pending = Completer<Result<LoadResult<ChapterContent>>>();
        h.repository.holds[h.key(1)] = pending;
        await h.open(tester);
        final old = active(tester).session;
        final gesture = await drag(tester, 1);
        await gesture.up();
        await layoutFrames(tester);
        expect(
          find.byKey(const ValueKey('cancel-chapter-turn')),
          findsOneWidget,
        );
        expect(frame(tester).progress, 0);
        if (cancel) {
          await tester.tap(find.byKey(const ValueKey('cancel-chapter-turn')));
          await tester.pumpAndSettle();
        }
        pending.complete(h.repository.result(h.key(1)));
        await layoutFrames(tester);
        expect(h.library.sessions, 1);
        await tester.pumpAndSettle();
        expect(h.library.sessions, cancel ? 1 : 2);
        if (cancel) {
          expect(active(tester).session, same(old));
        } else {
          expect(active(tester).content.key, h.key(1));
        }
        await h.close(tester);
      },
    );
  }
  testWidgets(
    'cancel while save and data await: neither late completion can commit',
    (tester) async {
      final h = Harness();
      h.library.save = Completer<Result<bool>>();
      final pending = Completer<Result<LoadResult<ChapterContent>>>();
      h.repository.holds[h.key(1)] = pending;
      await h.open(tester);
      final old = active(tester).session;
      final gesture = await drag(tester, 1);
      await gesture.up();
      await layoutFrames(tester);
      expect(h.library.saveCalls, greaterThan(0));
      await tester.tap(find.byKey(const ValueKey('cancel-chapter-turn')));
      await tester.pumpAndSettle();
      h.library.save!.complete(const Success(true));
      pending.complete(h.repository.result(h.key(1)));
      await tester.pumpAndSettle();
      expect(active(tester).session, same(old));
      expect(h.library.sessions, 1);
      expect(h.library.writes.every((p) => p.chapterKey == h.key(0)), isTrue);
      await h.close(tester);
    },
  );
  testWidgets(
    'save failure returns old page and retry permits a new operation',
    (tester) async {
      final h = Harness();
      h.library.save = Completer<Result<bool>>();
      await h.open(tester);
      final old = active(tester).session;
      final gesture = await drag(tester, 1);
      await gesture.up();
      await layoutFrames(tester);
      h.library.save!.complete(
        Failure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.progressWrite,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(active(tester).session, same(old));
      expect(h.library.sessions, 1);
      expect(find.text('Retry'), findsWidgets);
      h.library.save = null;
      await old!.retryProgress();
      active(tester).actions.nextChapter!();
      await tester.pumpAndSettle();
      expect(h.library.sessions, 2);
      await h.close(tester);
    },
  );
  for (final change in ['resize', 'font', 'scale', 'metadata']) {
    testWidgets('$change invalidates a held turn and keeps old semantic page', (
      tester,
    ) async {
      final h = Harness();
      await h.open(tester);
      final old = active(tester);
      final viewport = old.viewportController!;
      final position = viewport.capture();
      final gesture = await drag(tester, 1);
      expect(frame(tester).progress, greaterThan(0));
      switch (change) {
        case 'resize':
          tester.view.physicalSize = const Size(1400, 800);
        case 'font':
          old.preferences!.update(h.settings.value.copyWith(fontSize: 28));
        case 'scale':
          tester.platformDispatcher.textScaleFactorTestValue = 1.4;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        case 'metadata':
          final content = ChapterContent(
            key: old.content.key,
            title: old.content.title,
            blocks: [
              ParagraphBlock(
                text: 'Visible entry ${old.content.key.chapterId}',
                hangingIndentEm: 2,
              ),
            ],
          );
          expect(content.contentRevision, old.content.contentRevision);
          old.session!.content = content;
          old.session!.update();
      }
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(active(tester).session, same(old.session));
      expect(viewport.capture(), position);
      expect(
        find.text('Visible entry ${old.content.key.chapterId}'),
        findsOneWidget,
      );
      expect(h.library.sessions, 1);
      if (change == 'resize') {
        expect(
          tester
              .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
              .columns,
          2,
        );
        tester.view.physicalSize = const Size(600, 800);
        await tester.pumpAndSettle();
        expect(viewport.capture(), position);
      }
      await h.close(tester);
    });
  }
  for (final commit in [false, true]) {
    testWidgets(
      'both image geometries freeze until ${commit ? "commit" : "cancel"}',
      (tester) async {
        final h = Harness();
        for (var i = 0; i < 2; i++) {
          h.repository.contents[h.key(i)] = ChapterContent(
            key: h.key(i),
            title: 'Images $i',
            blocks: [ImageBlock(media: fixtureMediaRef(i), alt: 'Image $i')],
          );
        }
        await h.open(tester);
        expect(
          h.images.requests.where((r) => r.$1 == fixtureMediaRef(1)).single.$2,
          ReadMode.cacheOnly,
        );
        final gesture = await drag(tester, 1);
        final images = tester
            .widgetList<ReaderImage>(find.byType(ReaderImage))
            .toList();
        expect(images.length, 2);
        final geometries = tester
            .widgetList<PagedReaderViewport>(find.byType(PagedReaderViewport))
            .map((v) => (v.controller, v.controller.layoutGeneration))
            .toList();
        for (final image in images) {
          image.onIntrinsicSize(const Size(100, 200));
        }
        await tester.pump();
        for (final (controller, generation) in geometries) {
          expect(controller.layoutGeneration, generation);
        }
        if (commit) {
          await gesture.up();
        } else {
          await gesture.cancel();
        }
        await tester.pump(const Duration(milliseconds: 40));
        for (final (controller, generation) in geometries) {
          expect(controller.layoutGeneration, generation);
        }
        await tester.pumpAndSettle();
        final view = active(tester);
        expect(view.content.key, h.key(commit ? 1 : 0));
        final native = tester.widget<PagedReaderViewport>(
          find.byType(PagedReaderViewport),
        );
        final block = view.content.blocks.single as ImageBlock;
        expect(native.imageExtent!(block), greaterThan(180));
        expect(
          tester.widget<ReaderImage>(find.byType(ReaderImage)).block.media,
          fixtureMediaRef(commit ? 1 : 0),
        );
        expect(
          tester.getSize(find.byType(ReaderImage)).height,
          greaterThan(180),
        );
        await h.close(tester);
      },
    );
  }
  testWidgets('offline body and image candidates never use online modes', (
    tester,
  ) async {
    final h = Harness();
    h.images.forbidOnline = true;
    h.repository.forbidOnline = true;
    for (var i = 0; i < 2; i++) {
      h.repository.contents[h.key(i)] = ChapterContent(
        key: h.key(i),
        title: 'Offline $i',
        blocks: [ImageBlock(media: fixtureMediaRef(i))],
      );
    }
    final token = CancellationSource().token;
    await h.env.novels.loadCatalog(
      h.key(0).novelKey,
      mode: ReadMode.cacheFirst,
      cancellation: token,
    );
    await h.env.novels.loadDetail(
      h.key(0).novelKey,
      mode: ReadMode.cacheFirst,
      cancellation: token,
    );
    await h.open(tester, offline: true);
    final gesture = await drag(tester, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(active(tester).content.key, h.key(1));
    expect(
      h.repository.requests.every((r) => r.$2 == ReadMode.cacheOnly),
      isTrue,
    );
    expect(h.images.requests.every((r) => r.$2 == ReadMode.cacheOnly), isTrue);
    await h.close(tester);
  });
  for (final event in ['cover', 'background', 'dispose']) {
    testWidgets('$event cancels pending turn and ignores late target', (
      tester,
    ) async {
      final h = Harness();
      final pending = Completer<Result<LoadResult<ChapterContent>>>();
      h.repository.holds[h.key(1)] = pending;
      await h.open(tester);
      final old = active(tester);
      final gesture = await drag(tester, 1);
      await gesture.up();
      await layoutFrames(tester);
      if (event == 'cover') {
        unawaited(
          Navigator.of(tester.element(find.byType(BookReaderScreen))).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover')),
            ),
          ),
        );
      } else if (event == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpAndSettle();
      pending.complete(h.repository.result(h.key(1)));
      await tester.pumpAndSettle();
      expect(h.library.sessions, 1);
      if (event == 'cover') {
        Navigator.of(tester.element(find.text('Cover'))).pop();
        await tester.pumpAndSettle();
      }
      if (event == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      if (event != 'dispose') expect(active(tester).session, same(old.session));
      await h.close(tester);
    });
  }
  testWidgets(
    'cancelled failure cannot reject a newer candidate and ready callbacks are idempotent',
    (tester) async {
      final h = Harness();
      final stale = Completer<Result<LoadResult<ChapterContent>>>();
      h.repository.holds[h.key(1)] = stale;
      await h.open(tester);
      final first = await drag(tester, 1);
      await first.cancel();
      await tester.pumpAndSettle();
      h.repository.holds.remove(h.key(1));
      final second = await drag(tester, 1);
      final target = tester
          .widgetList<ReaderContentView>(find.byType(ReaderContentView))
          .singleWhere((v) => !v.appearanceActive!);
      stale.complete(
        Failure(
          AppFailure(
            kind: FailureKind.network,
            operation: Operation.chapter,
            retryPolicy: RetryPolicy.manual,
          ),
        ),
      );
      target.onReady!();
      target.onReady!();
      await tester.pump();
      expect(frame(tester).progress, greaterThan(0));
      expect(find.text('Retry'), findsNothing);
      await second.up();
      await tester.pumpAndSettle();
      expect(active(tester).session, same(target.session));
      expect(h.library.sessions, 2);
      await h.close(tester);
    },
  );
  testWidgets(
    'failed foreground preparation preserves source and manual retry works',
    (tester) async {
      final h = Harness();
      final load = Completer<Result<LoadResult<ChapterContent>>>();
      h.repository.holds[h.key(1)] = load;
      await h.open(tester);
      final old = active(tester).session;
      final gesture = await drag(tester, 1);
      await gesture.up();
      load.complete(
        Failure(
          AppFailure(
            kind: FailureKind.network,
            operation: Operation.chapter,
            retryPolicy: RetryPolicy.manual,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(active(tester).session, same(old));
      expect(h.library.sessions, 1);
      h.repository.holds.remove(h.key(1));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(active(tester).content.key, h.key(1));
      expect(h.library.sessions, 2);
      await h.close(tester);
    },
  );
  testWidgets(
    'pending preparation deadline releases resources and late readiness is inert',
    (tester) async {
      final h = Harness();
      final load = Completer<Result<LoadResult<ChapterContent>>>();
      h.repository.holds[h.key(1)] = load;
      await h.open(tester);
      final old = active(tester).session;
      final gesture = await drag(tester, 1);
      await gesture.up();
      await tester.pump(const Duration(seconds: 46));
      await tester.pumpAndSettle();
      expect(active(tester).session, same(old));
      expect(h.cache.pins, {h.key(0)});
      load.complete(h.repository.result(h.key(1)));
      await tester.pumpAndSettle();
      expect(h.library.sessions, 1);
      expect(find.text('Retry'), findsOneWidget);
      await h.close(tester);
    },
  );
  testWidgets(
    'book invalidation retires both sessions while candidate is pending',
    (tester) async {
      final h = Harness();
      final load = Completer<Result<LoadResult<ChapterContent>>>();
      h.repository.holds[h.key(1)] = load;
      await h.open(tester);
      final gesture = await drag(tester, 1);
      await gesture.up();
      h.repository.events.add(h.key(0).novelKey);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderContentView), findsNothing);
      expect(h.cache.pins, isEmpty);
      load.complete(h.repository.result(h.key(1)));
      await tester.pumpAndSettle();
      expect(h.library.sessions, 1);
      await h.close(tester);
    },
  );
  testWidgets(
    'pure paper change retains candidate, boundary cache and body widgets during drag',
    (tester) async {
      final h = Harness();
      await h.open(tester);
      final source = active(tester);
      final count = h.repository.requests.length;
      final generation = source.viewportController!.layoutGeneration;
      source.preferences!.update(
        h.settings.value.copyWith(paper: ReaderPaper.warm),
      );
      await tester.pumpAndSettle();
      expect(h.repository.requests.length, count);
      expect(source.viewportController!.layoutGeneration, generation);
      final gesture = await drag(tester, 1);
      final views = tester
          .widgetList<ReaderContentView>(find.byType(ReaderContentView))
          .toList();
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(-10, 0));
        await tester.pump();
        final updated = tester
            .widgetList<ReaderContentView>(find.byType(ReaderContentView))
            .toList();
        for (var j = 0; j < views.length; j++) {
          expect(updated[j], same(views[j]));
        }
        expect(h.repository.requests.length, count);
      }
      await gesture.cancel();
      await tester.pumpAndSettle();
      await h.close(tester);
    },
  );
  testWidgets(
    'previous long chapter exposes canonical last page, not first provisional page',
    (tester) async {
      final h = Harness();
      h.repository.contents[h.key(0)] = ChapterContent(
        key: h.key(0),
        title: 'Long prior',
        blocks: [
          for (var i = 0; i < 45; i++)
            ParagraphBlock(text: 'Paragraph $i ${"long body " * 55}'),
          ParagraphBlock(text: 'Actual last source text'),
        ],
      );
      await h.open(tester, index: 1);
      final gesture = await drag(tester, -1);
      for (var i = 0; i < 300 && frame(tester).progress == 0; i++) {
        await tester.pump();
      }
      expect(frame(tester).progress, greaterThan(0));
      final text = tester
          .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
          .map((v) => v.text)
          .join();
      expect(text, contains('Actual last source text'));
      expect(text, isNot(contains('Paragraph 0')));
      expect(h.library.sessions, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(active(tester).content.key, h.key(0));
      expect(
        tester
            .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
            .map((v) => v.text)
            .join(),
        contains('Actual last source text'),
      );
      await h.close(tester);
    },
  );
  testWidgets(
    'temporary page zero after a deep seek does not prepare previous chapter',
    (tester) async {
      final h = Harness();
      h.repository.contents[h.key(1)] = ChapterContent(
        key: h.key(1),
        title: 'Middle',
        blocks: [
          for (var i = 0; i < 30; i++)
            ParagraphBlock(text: 'Body $i ${"segment " * 80}'),
        ],
      );
      await h.open(tester, index: 1);
      final view = active(tester);
      final block = view.content.blocks[15];
      view.viewportController!.restore(
        ReaderPosition(
          contentRevision: view.content.contentRevision,
          blockKey: block.blockKey,
          blockIndex: 15,
          blockFraction: .2,
          chapterFraction: .5,
        ),
      );
      await tester.pumpAndSettle();
      expect(h.cache.pins, {h.key(1)});
      final count = h.repository.requests.length;
      final gesture = await drag(tester, -1);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(h.repository.requests.length, count);
      expect(h.library.sessions, 1);
      await h.close(tester);
    },
  );
  for (final table in [false, true]) {
    testWidgets(
      'native ${table ? "table" : "rich text"} participates in held boundary',
      (tester) async {
        final h = Harness();
        h.repository.contents[h.key(1)] = ChapterContent(
          key: h.key(1),
          title: 'Rich target',
          blocks: [
            ParagraphBlock(
              text: 'Name Value text',
              tableRow: table
                  ? TableRowLayout(
                      group: 0,
                      leftEnd: 4,
                      rightStart: 5,
                      leftWidthEm: 3,
                      leftPaddingEm: 0,
                      rightPaddingEm: 1,
                      dividerWidth: 1,
                      dividerColor: 0xff000000,
                    )
                  : null,
              inlineStyles: table
                  ? []
                  : [
                      InlineTextStyle(
                        start: 5,
                        length: 5,
                        bold: true,
                        fontScale: 1.2,
                      ),
                    ],
            ),
          ],
        );
        await h.open(tester);
        final gesture = await drag(tester, 1);
        expect(frame(tester).progress, inExclusiveRange(0, 1));
        expect(
          tester
              .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
              .map((v) => v.text)
              .join(),
          contains('Value text'),
        );
        expect(h.library.sessions, 1);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(active(tester).content.key, h.key(1));
        await h.close(tester);
      },
    );
  }
  testWidgets(
    'native to WebView never creates a hidden platform preview on preparation or drag',
    (tester) async {
      final h = Harness();
      h.repository.presentations[h.key(1)] =
          '<html><body>Special target</body></html>';
      await h.open(tester);
      expect(h.repository.requests.length, 2);
      expect(find.byType(EpubLayoutPage, skipOffstage: false), findsNothing);
      final gesture = await drag(tester, 1);
      expect(frame(tester).progress, 0);
      expect(find.byType(EpubLayoutPage, skipOffstage: false), findsNothing);
      expect(h.library.sessions, 1);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(active(tester).content.key, h.key(0));
      await h.close(tester);
    },
  );
  testWidgets('reduced motion uses the same confirmation gate', (tester) async {
    final h = Harness();
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await h.open(tester);
    final gesture = await drag(tester, 1);
    expect(h.library.sessions, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(active(tester).content.key, h.key(1));
    expect(h.library.sessions, 2);
    await h.close(tester);
  });
  testWidgets(
    'waiting can be cancelled by system back without exiting Reader',
    (tester) async {
      final h = Harness();
      final load = Completer<Result<LoadResult<ChapterContent>>>();
      h.repository.holds[h.key(1)] = load;
      await h.open(tester);
      final old = active(tester).session;
      final gesture = await drag(tester, 1);
      await gesture.up();
      await layoutFrames(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(active(tester).session, same(old));
      expect(find.byKey(const ValueKey('cancel-chapter-turn')), findsNothing);
      load.complete(h.repository.result(h.key(1)));
      await tester.pumpAndSettle();
      expect(h.library.sessions, 1);
      await h.close(tester);
    },
  );
  testWidgets(
    'desktop escape cancels waiting even while page commands are disabled',
    (tester) async {
      final h = Harness();
      final load = Completer<Result<LoadResult<ChapterContent>>>();
      h.repository.holds[h.key(1)] = load;
      await h.open(tester);
      final old = active(tester).session;
      final gesture = await drag(tester, 1);
      await gesture.up();
      await layoutFrames(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cancel-chapter-turn')), findsNothing);
      load.complete(h.repository.result(h.key(1)));
      await tester.pumpAndSettle();
      expect(active(tester).session, same(old));
      expect(h.library.sessions, 1);
      await h.close(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets(
    'wide spread uses whole reader width and height for boundary progress and grip',
    (tester) async {
      final h = Harness();
      await h.open(tester);
      tester.view.physicalSize = const Size(1400, 800);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(1000, 660));
      await gesture.moveBy(const Offset(-24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-350, 0));
      await layoutFrames(tester);
      expect(frame(tester).progress, closeTo(.25, .001));
      expect(frame(tester).grip, closeTo(660 / 800, .015));
      expect(h.library.sessions, 1);
      await gesture.cancel();
      await tester.pumpAndSettle();
      await h.close(tester);
    },
  );
  testWidgets(
    'cancelling target releases its image leases while active lease survives',
    (tester) async {
      final h = Harness();
      h.images.succeed = true;
      for (var i = 0; i < 2; i++) {
        h.repository.contents[h.key(i)] = ChapterContent(
          key: h.key(i),
          title: 'Lease $i',
          blocks: [
            ImageBlock(media: fixtureMediaRef(i), width: 16, height: 16),
          ],
        );
      }
      await h.open(tester, settle: false);
      Future<void> decoded() async {
        for (var i = 0; i < 200; i++) {
          await tester.runAsync(() => Future<void>(() {}));
          await tester.pump();
          if (tester
                  .widgetList<RawImage>(
                    find.byType(RawImage, skipOffstage: false),
                  )
                  .where((v) => v.image != null)
                  .length >=
              2) {
            return;
          }
        }
        fail('Both live page images must decode');
      }

      await decoded();
      final source = h.images.leases.singleWhere(
        (v) => v.ref == fixtureMediaRef(0),
      );
      final gesture = await drag(tester, 1);
      await decoded();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(source.isClosed, isFalse);
      expect(
        h.images.leases
            .where((v) => v.ref == fixtureMediaRef(1))
            .every((v) => v.isClosed),
        isTrue,
      );
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      await h.close(tester);
      expect(h.images.leases.every((v) => v.isClosed), isTrue);
    },
  );
  testWidgets(
    'disposing during settle cancels ticker without a late state mutation',
    (tester) async {
      final h = Harness();
      await h.open(tester);
      final gesture = await drag(tester, 1);
      await gesture.up();
      await layoutFrames(tester);
      await tester.pump(const Duration(milliseconds: 40));
      expect(frame(tester).progress, inExclusiveRange(0, 1));
      await h.close(tester);
      expect(h.library.sessions, 1);
      expect(h.cache.pins, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final retryTime in [false, true]) {
    testWidgets(
      'rate limit with retry time $retryTime allows cached navigation without remote reads',
      (tester) async {
        final h = Harness();
        final load = Completer<Result<LoadResult<ChapterContent>>>();
        h.repository.cacheMisses.add(h.key(2));
        h.repository.holds[h.key(2)] = load;
        h.repository.contents[h.key(0)] = ChapterContent(
          key: h.key(0),
          title: 'Cached A',
          blocks: [
            ParagraphBlock(text: 'Cached A'),
            ImageBlock(media: fixtureMediaRef(0), width: 16, height: 16),
          ],
        );
        await h.open(tester, index: 1);
        final gesture = await drag(tester, 1);
        await gesture.up();
        await layoutFrames(tester);
        expect(
          h.repository.requests.any(
            (r) => r.$1 == h.key(2) && r.$2 == ReadMode.cacheFirst,
          ),
          isTrue,
        );
        load.complete(
          Failure(
            AppFailure(
              kind: FailureKind.rateLimited,
              operation: Operation.chapter,
              retryPolicy: RetryPolicy.manual,
              retryNotBefore: retryTime
                  ? DateTime.now().add(const Duration(hours: 1))
                  : null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final count = h.repository.requests.length;
        final imageCount = h.images.requests.length;
        final prefetchCount = h.cache.prefetch.entries.length;
        final positionCount = h.cache.prefetch.positions.length;
        h.repository.forbidOnline = true;
        h.images.forbidOnline = true;
        h.repository.holds.remove(h.key(2));
        if (retryTime) {
          // A later cache failure must not erase the Source cooldown.
          h.repository.holds[h.key(0)] = Completer()
            ..complete(
              Failure(
                AppFailure(
                  kind: FailureKind.cache,
                  operation: Operation.chapter,
                  retryPolicy: RetryPolicy.manual,
                ),
              ),
            );
          active(tester).actions.previousChapter!();
          await tester.pumpAndSettle();
          expect(active(tester).content.key, h.key(1));
          h.repository.holds.remove(h.key(0));
        }
        final back = await drag(tester, -1);
        await back.up();
        await tester.pumpAndSettle();
        expect(active(tester).content.key, h.key(0));
        expect(h.library.sessions, 2);
        active(tester).actions.nextChapter!();
        await tester.pumpAndSettle();
        expect(active(tester).content.key, h.key(1));
        active(tester).actions.nextChapter!();
        await tester.pumpAndSettle();
        expect(active(tester).content.key, h.key(1));
        expect(h.library.sessions, 3);
        expect(
          h.repository.requests
              .skip(count)
              .every((r) => r.$2 == ReadMode.cacheOnly),
          isTrue,
        );
        expect(h.cache.prefetch.entries.length, prefetchCount);
        expect(h.cache.prefetch.positions.length, positionCount);
        expect(h.images.requests.skip(imageCount), isNotEmpty);
        expect(
          h.images.requests
              .skip(imageCount)
              .every((r) => r.$2 == ReadMode.cacheOnly),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await h.close(tester);
      },
    );
  }
  for (final repeat in [false, true]) {
    testWidgets(
      'escape during settle preserves rebound with repeated cancel $repeat',
      (tester) async {
        final h = Harness();
        await h.open(tester);
        final old = active(tester).session;
        final gesture = await drag(tester, 1);
        await gesture.up();
        await layoutFrames(tester);
        await tester.pump(const Duration(milliseconds: 40));
        final before = frame(tester).progress;
        expect(before, inExclusiveRange(0, 1));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final rebound = frame(tester).progress;
        expect(rebound, inExclusiveRange(0, before));
        expect(h.cache.pins, {h.key(0), h.key(1)});
        if (repeat) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 20));
          expect(frame(tester).progress, inExclusiveRange(0, rebound));
          expect(h.cache.pins, {h.key(0), h.key(1)});
        }
        await tester.pumpAndSettle();
        expect(frame(tester).progress, 0);
        expect(active(tester).session, same(old));
        expect(h.library.sessions, 1);
        expect(h.cache.pins, {h.key(0)});
        await h.close(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
  for (final lateReady in [false, true]) {
    testWidgets(
      'ready drag outlives preparation deadline with late readiness $lateReady',
      (tester) async {
        final h = Harness();
        final load = Completer<Result<LoadResult<ChapterContent>>>();
        if (lateReady) h.repository.holds[h.key(1)] = load;
        await h.open(tester);
        final old = active(tester).session;
        final gesture = await drag(tester, 1);
        if (lateReady) {
          expect(frame(tester).progress, 0);
          await tester.pump(const Duration(seconds: 20));
          load.complete(h.repository.result(h.key(1)));
          await layoutFrames(tester);
        }
        final progress = frame(tester).progress;
        expect(progress, inExclusiveRange(0, 1));
        await tester.pump(const Duration(seconds: 46));
        await layoutFrames(tester);
        expect(frame(tester).progress, progress);
        expect(active(tester).session, same(old));
        expect(h.library.sessions, 1);
        expect(h.cache.pins, {h.key(0), h.key(1)});
        await gesture.up();
        await tester.pumpAndSettle();
        expect(active(tester).content.key, h.key(1));
        expect(h.library.sessions, 2);
        await h.close(tester);
      },
    );
  }
  for (final limited in [false, true]) {
    testWidgets(
      '${limited ? "rate limit" : "never retry"} survives candidate disposal',
      (tester) async {
        final h = Harness();
        final load = Completer<Result<LoadResult<ChapterContent>>>();
        h.repository.holds[h.key(1)] = load;
        await h.open(tester);
        final gesture = await drag(tester, 1);
        await gesture.up();
        load.complete(
          Failure(
            AppFailure(
              kind: limited ? FailureKind.rateLimited : FailureKind.unsupported,
              operation: Operation.chapter,
              retryPolicy: limited ? RetryPolicy.manual : RetryPolicy.never,
              retryNotBefore: limited
                  ? DateTime.now().add(const Duration(hours: 1))
                  : null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final count = h.repository.requests.length;
        h.repository.holds.remove(h.key(1));
        h.repository.cacheMisses.add(h.key(1));
        active(tester).actions.nextChapter!();
        await tester.pumpAndSettle();
        final again = await drag(tester, 1);
        await again.up();
        await tester.pumpAndSettle();
        expect(
          h.repository.requests
              .skip(count)
              .every((r) => r.$2 == ReadMode.cacheOnly),
          isTrue,
        );
        if (!limited) expect(h.repository.requests.length, count);
        expect(active(tester).content.key, h.key(0));
        expect(h.library.sessions, 1);
        await h.close(tester);
      },
    );
  }
}
