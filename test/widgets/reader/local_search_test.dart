import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/search/local_search_session.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/local_chapter_progress.dart';
import 'package:shiori/features/reader/reader_search_controller.dart';
import 'package:shiori/features/reader/reader_search_highlight.dart';
import 'package:shiori/features/reader/reader_search_panel.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_location_transition.dart';
import 'package:shiori/features/reader/viewport/page_turn.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'link_return_test.dart' as f;
import 'local_reading_test.dart' show MemoryBooks;

/// Real bounded production scanner, with only stored snapshot validation stubbed.
class ReaderSearchRepository extends f.ReturnRepository {
  ReaderSearchRepository(this.store) : super(store);
  final MemoryBooks store;
  final sessions = <LocalSearchSessionImpl>[];
  bool valid = true;
  Completer<void>? queryGate;
  bool logicalIndexAvailable = true;
  @override
  Future<Result<LocalChapterProgressIndex?>> loadLogicalChapters(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => logicalIndexAvailable
      ? super.loadLogicalChapters(key, cancellation: cancellation)
      : Future.value(const Success(null));
  ChapterKey? changingTarget;
  int targetLoads = 0, changeAfter = 3;
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    final result = await super.loadChapter(
      key,
      mode: mode,
      cancellation: cancellation,
    );
    if (key == changingTarget &&
        ++targetLoads >= changeAfter &&
        result is Success<LoadResult<ChapterContent>>) {
      return Success(
        LoadResult(
          value: ChapterContent(
            key: key,
            title: result.value.value.title,
            blocks: [
              ...result.value.value.blocks,
              ParagraphBlock(text: 'Changed after validation'),
            ],
          ),
          origin: result.value.origin,
          fetchedAt: result.value.fetchedAt,
        ),
      );
    }
    return result;
  }

  int released = 0;
  @override
  Future<Result<LocalSearchSession>> openLocalSearch(
    NovelKey book, {
    required CancellationToken cancellation,
  }) async {
    final session = LocalSearchSessionImpl(
      content: store.record.content,
      snapshot: LocalSearchSnapshotId('reader-snapshot'),
      sessionId: 'reader-${sessions.length}',
      check: (_) async => Success(valid),
      release: () {
        released++;
      },
    );
    sessions.add(session);
    return Success(
      queryGate == null ? session : DelayedSearchSession(session, queryGate!),
    );
  }
}

class DelayedSearchSession implements LocalSearchSession {
  DelayedSearchSession(this.delegate, this.gate);
  final LocalSearchSession delegate;
  final Completer<void> gate;
  @override
  LocalSearchSnapshotId get snapshot => delegate.snapshot;
  @override
  bool get isValid => delegate.isValid;
  @override
  Future<Result<LocalSearchPage>> search(
    String query, {
    required CancellationToken cancellation,
  }) async {
    await gate.future;
    return delegate.search(query, cancellation: cancellation);
  }

  @override
  Future<Result<LocalSearchPage>> nextPage(
    LocalSearchCursor cursor, {
    required CancellationToken cancellation,
  }) => delegate.nextPage(cursor, cancellation: cancellation);
  @override
  Future<Result<void>> validate(
    LocalSearchSnapshotId snapshot, {
    required CancellationToken cancellation,
  }) => delegate.validate(snapshot, cancellation: cancellation);
  @override
  Future<void> cancel() => delegate.cancel();
  @override
  Future<void> close() => delegate.close();
}

ReaderSearchController search(f.ReturnReader reader, WidgetTester tester) =>
    reader.view(tester).search!;
Future<void> submit(
  WidgetTester tester,
  ReaderSearchController state,
  String text,
) async {
  if (find.byKey(const ValueKey('reader-search-input')).evaluate().isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('reader-search-input')),
      text,
    );
  }
  await tester.runAsync(() => state.submit(text));
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  expect(find.byType(ReaderSearchPanel), findsOneWidget);
}

Future<void> select(
  WidgetTester tester,
  ReaderSearchController state,
  int index,
) async {
  final panel = tester.widget<ReaderSearchPanel>(
    find.byType(ReaderSearchPanel),
  );
  unawaited(
    state.select(
      index,
      accepts: panel.accepts,
      closePanel: panel.closeForNavigation,
    ),
  );
  await tester.pumpAndSettle();
  // Repository/worker checks use the real event loop.
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Future<void> fonts(WidgetTester tester) async {
  if (Platform.environment['SHIORI_RETURN_SCREENSHOTS'] == null) return;
  await tester.runAsync(() async {
    final material = await File(
      '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(material)))).load();
    final cjk = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (await cjk.exists()) {
      final bytes = await cjk.readAsBytes();
      for (final family in [
        'Microsoft YaHei UI',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
  });
}

void main() {
  List<double> reveals(WidgetTester tester) => tester
      .widgetList<Opacity>(
        find.descendant(
          of: find.byType(ReaderLocationTransition),
          matching: find.byType(Opacity),
        ),
      )
      .map((o) => o.opacity)
      .toList();
  Future<void> drive(
    WidgetTester tester,
    Future<void> work,
    FutureOr<void> Function() inspect,
  ) async {
    var done = false;
    Object? failure;
    work.then(
      (_) => done = true,
      onError: (Object e) {
        failure = e;
        done = true;
      },
    );
    for (var i = 0; i < 400 && !done; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 16));
      await inspect();
    }
    expect(done, isTrue);
    await tester.pump();
    await inspect();
    if (failure != null) throw failure!;
  }

  Future<void> choose(
    WidgetTester tester,
    ReaderSearchController state,
    int index,
    FutureOr<void> Function() inspect,
  ) async {
    final panel = tester.widget<ReaderSearchPanel>(
      find.byType(ReaderSearchPanel),
    );
    await drive(
      tester,
      state.select(
        index,
        accepts: panel.accepts,
        closePanel: panel.closeForNavigation,
      ),
      inspect,
    );
  }

  testWidgets(
    'cross chapter search and return already use the configured page turn',
    (tester) async {
      await fonts(tester);
      final reader = await f.mount(
        tester,
        size: const Size(1040, 780),
        pageTurn: PageTurnStyle.slide,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester), origin = reader.position(tester);
      await open(tester);
      await submit(tester, state, 'later');
      final index = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)!.chapter == reader.key('b'));
      var midframes = 0;
      var phase = 'forward';
      Future<void> inspect() async {
        if (tester
            .widgetList<PageTurnSlot>(find.byType(PageTurnSlot))
            .any(
              (s) => s.frame.style == PageTurnStyle.slide && s.frame.turning,
            )) {
          midframes++;
          if (midframes == 5) {
            await f.snapshot(
              tester,
              reader,
              'cross-chapter-$phase-middle',
              pump: false,
            );
          }
        }
        expect(reveals(tester).every((o) => o == 1), isTrue);
      }

      await choose(tester, state, index, inspect);
      await tester.pumpAndSettle();
      expect(midframes, greaterThan(0));
      expect(reader.view(tester).content.key, reader.key('b'));
      midframes = 0;
      phase = 'return';
      await drive(tester, state.returnToOrigin!(), inspect);
      await tester.pumpAndSettle();
      expect(midframes, greaterThan(0));
      expect(reader.view(tester).content.key, reader.key('a'));
      expect(reader.position(tester), origin);
      expect(state.canReturn.value, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'same chapter search reveals only changed pages and preserves the single A origin',
    (tester) async {
      await fonts(tester);
      final reader = await f.mount(
        tester,
        size: const Size(1040, 780),
        pageTurn: PageTurnStyle.slide,
        paper: ReaderPaper.warm,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester),
          origin = reader.position(tester),
          viewport = tester.state(find.byType(PagedReaderViewport));
      await open(tester);
      await submit(tester, state, 'later');
      final b = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)!.chapter == reader.key('a'));
      final c = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)!.chapter == reader.key('b'));
      final repository = reader.repository as ReaderSearchRepository;
      repository.blocked = reader.key('a');
      final preparation = repository.wait = Completer<void>();
      var preparationFrames = 0;
      await choose(tester, state, b, () {
        if (!preparation.isCompleted) {
          expect(reader.position(tester), origin);
          expect(state.canReturn.value, isFalse);
          expect(reveals(tester).every((o) => o == 1), isTrue);
          if (++preparationFrames == 4) preparation.complete();
        }
      });
      repository.blocked = null;
      repository.wait = null;
      expect(preparationFrames, 4);
      expect(reveals(tester).single, lessThan(1));
      expect(tester.state(find.byType(PagedReaderViewport)), same(viewport));
      final page = reader
              .view(tester)
              .viewportController!
              .inspectDisplayedPage()!
              .page,
          generation = reader.view(tester).viewportController!.layoutGeneration;
      await f.snapshot(
        tester,
        reader,
        'same-chapter-reveal-start',
        pump: false,
      );
      await tester.pump(const Duration(milliseconds: 64));
      expect(reveals(tester).single, inExclusiveRange(.88, 1));
      expect(
        reader.view(tester).viewportController!.layoutGeneration,
        generation,
      );
      expect(
        reader.view(tester).viewportController!.inspectDisplayedPage()!.page,
        same(page),
      );
      await f.snapshot(
        tester,
        reader,
        'same-chapter-reveal-middle',
        pump: false,
      );
      await tester.pumpAndSettle();
      expect(reveals(tester).single, 1);
      // The same hit stays on the displayed page and needs no surface reveal.
      await open(tester);
      await choose(
        tester,
        state,
        b,
        () => expect(reveals(tester).every((o) => o == 1), isTrue),
      );
      await tester.pumpAndSettle();
      await drive(tester, state.returnToOrigin!(), () {});
      expect(reveals(tester).single, lessThan(1));
      await tester.pump(const Duration(milliseconds: 64));
      await f.snapshot(
        tester,
        reader,
        'same-chapter-return-middle',
        pump: false,
      );
      await tester.pumpAndSettle();
      expect(reader.position(tester), origin);
      expect(state.highlight.value, isNull);
      // A -> B -> C -> A consumes one origin, with no intermediate B return.
      await open(tester);
      await choose(tester, state, b, () {});
      await tester.pumpAndSettle();
      await open(tester);
      await choose(tester, state, c, () {});
      await tester.pumpAndSettle();
      await drive(tester, state.returnToOrigin!(), () {});
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, reader.key('a'));
      expect(reader.position(tester), origin);
      expect(state.canReturn.value, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  for (final disabled in [
    (PageTurnStyle.none, false),
    (PageTurnStyle.slide, true),
  ]) {
    testWidgets(
      'search position reveal respects animation settings $disabled',
      (tester) async {
        final reader = await f.mount(
          tester,
          size: const Size(1040, 780),
          pageTurn: disabled.$1,
          reduceMotion: disabled.$2,
          repositoryFactory: ReaderSearchRepository.new,
        );
        final state = search(reader, tester), origin = reader.position(tester);
        await open(tester);
        await submit(tester, state, 'later');
        final b = List.generate(
          state.loadedCount,
          (i) => i,
        ).firstWhere((i) => state.hitAt(i)!.chapter == reader.key('a'));
        void inspect() => expect(reveals(tester).every((o) => o == 1), isTrue);
        await choose(tester, state, b, inspect);
        await drive(tester, state.returnToOrigin!(), inspect);
        await tester.pumpAndSettle();
        expect(reader.position(tester), origin);
        expect(state.canReturn.value, isFalse);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.windows}),
    );
  }

  testWidgets(
    'search opening and delayed query retain the body in every intermediate frame',
    (tester) async {
      await fonts(tester);
      final mobile = defaultTargetPlatform == TargetPlatform.iOS;
      if (mobile) {
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
      }
      final reader = await f.mount(
        tester,
        size: mobile ? const Size(400, 800) : const Size(1040, 780),
        pageTurn: PageTurnStyle.slide,
        paper: ReaderPaper.warm,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final repository = reader.repository as ReaderSearchRepository;
      final gate = repository.queryGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final state = search(reader, tester);
      if (mobile) {
        unawaited(reader.view(tester).viewportController!.next());
        await tester.pumpAndSettle();
        expect(reader.position(tester).blockIndex, greaterThan(0));
        await f.toggle(tester);
      }
      final view = tester.state(find.byType(ReaderContentView));
      final viewport = tester.state(find.byType(PagedReaderViewport));
      final controller = reader.view(tester).viewportController!;
      final generation = controller.layoutGeneration;
      final position = reader.position(tester);
      final page = controller.inspectDisplayedPage()!.page;
      final sample = reader.view(tester).session!.currentPosition;
      final writes = reader.library.controls.calls[Operation.progressWrite];
      Future<void> frameSnapshot(String name) =>
          f.snapshot(tester, reader, name, pump: false);
      if (mobile) {
        await frameSnapshot('ios-second-page-before-search');
      }
      void unchanged() {
        expect(reveals(tester).every((o) => o == 1), isTrue);
        expect(tester.state(find.byType(ReaderContentView)), same(view));
        expect(tester.state(find.byType(PagedReaderViewport)), same(viewport));
        expect(controller.layoutGeneration, generation);
        expect(controller.isRestoring, isFalse);
        expect(controller.inspectDisplayedPage()!.page, same(page));
        expect(reader.position(tester), position);
        expect(reader.view(tester).session!.currentPosition, same(sample));
        expect(reader.library.controls.calls[Operation.progressWrite], writes);
        expect(
          find.descendant(
            of: find.byType(PagedReaderViewport),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );
      }

      Future<List<int>> bodyPixels() async => (await tester.runAsync(() async {
        final boundary =
            reader.boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final bytes = data.buffer.asUint8List();
        final region = <int>[];
        for (var y = 80; y < (mobile ? 100 : 650); y++) {
          region.addAll(
            bytes.sublist(
              (y * image.width + (mobile ? 40 : 100)) * 4,
              (y * image.width + (mobile ? 360 : 580)) * 4,
            ),
          );
        }
        image.dispose();
        return region;
      }))!;

      if (mobile) {
        await tester.tap(find.byKey(const ValueKey('reader-search-open')));
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.pump();
      final route = ModalRoute.of(
        tester.element(find.byType(ReaderSearchPanel)),
      )!;
      var openingFrame = 0;
      for (
        var elapsed = Duration.zero;
        elapsed <= route.transitionDuration;
        elapsed += const Duration(milliseconds: 16)
      ) {
        await tester.pump(const Duration(milliseconds: 16));
        unchanged();
        if (mobile) {
          await frameSnapshot(
            'ios-opening-${(openingFrame++).toString().padLeft(2, '0')}',
          );
        }
      }
      final beforeKeyboard = await bodyPixels();
      if (mobile) {
        // A real keyboard consumes bottom padding, while viewPadding survives.
        tester.view.padding = const FakeViewPadding(top: 24);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump(const Duration(milliseconds: 16));
        await frameSnapshot('ios-keyboard-first-frame');
        unchanged();
        expect(await bodyPixels(), beforeKeyboard);
        await frameSnapshot('ios-keyboard-open');
      }
      final pixels = await bodyPixels();
      await tester.enterText(
        find.byKey(const ValueKey('reader-search-input')),
        'later',
      );
      await tester.pump();
      unchanged();
      late Future<void> pending;
      await tester.runAsync(() async {
        pending = state.submit('later');
      });
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(state.loading, isTrue);
        unchanged();
        expect(await bodyPixels(), pixels);
        await frameSnapshot(
          '${mobile ? 'mobile' : 'desktop'}-query-loading-${i.toString().padLeft(2, '0')}',
        );
      }
      await tester.runAsync(() async {
        gate.complete();
        await pending;
      });
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        unchanged();
        expect(await bodyPixels(), pixels);
      }
      if (mobile) await frameSnapshot('ios-query-results');
      if (mobile) {
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
        tester.view.viewInsets = const FakeViewPadding();
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          unchanged();
          expect(await bodyPixels(), pixels);
        }
      }
      tester
          .widget<ReaderSearchPanel>(find.byType(ReaderSearchPanel))
          .onClose();
      await tester.pumpAndSettle();
      unchanged();
      if (mobile) {
        await frameSnapshot('ios-search-closed');
        await tester.tap(find.byKey(const ValueKey('reader-search-open')));
        await tester.pumpAndSettle();
      } else {
        await open(tester);
      }
      await select(tester, state, 0);
      expect(state.selectedIndex, 0);
      expect(reader.view(tester).content.key, state.hitAt(0)!.chapter);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'compact result rows preserve their anchor across reopening, reflow and cache eviction',
    (tester) async {
      final reader = await f.mount(
        tester,
        size: const Size(1040, 780),
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester);
      await open(tester);
      await submit(tester, state, 'later');
      final first = find.byKey(const ValueKey('reader-search-result-0'));
      final second = find.byKey(const ValueKey('reader-search-result-1'));
      expect(tester.getSize(first).height, lessThan(100));
      expect(
        tester.getTopLeft(second).dy - tester.getBottomLeft(first).dy,
        closeTo(0, .01),
      );
      await submit(tester, state, 'fixture');
      ScrollController scroll() => tester
          .widget<CustomScrollView>(
            find.byKey(const ValueKey('reader-search-results')),
          )
          .controller!;
      scroll().jumpTo(scroll().position.maxScrollExtent / 2);
      await tester.pumpAndSettle();
      final resultList = find.byKey(const ValueKey('reader-search-results'));
      final listElement = tester.element(resultList);
      final scrollState = tester.state(
        find.descendant(of: resultList, matching: find.byType(Scrollable)),
      );
      final middle = state.scrollPosition.floor();
      final row = tester.element(
        find.byKey(ValueKey('reader-search-result-$middle')),
      );
      final offset = scroll().offset;
      for (final draft in ['f', 'fixture误', 'fixture']) {
        await tester.enterText(
          find.byKey(const ValueKey('reader-search-input')),
          draft,
        );
        await tester.pump();
        expect(tester.element(resultList), same(listElement));
        expect(
          tester.state(
            find.descendant(of: resultList, matching: find.byType(Scrollable)),
          ),
          same(scrollState),
        );
        expect(
          tester.element(find.byKey(ValueKey('reader-search-result-$middle'))),
          same(row),
        );
        expect(scroll().offset, offset);
      }
      Future<void> settleSearch() async {
        for (var i = 0; i < 200; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (!state.loading) {
            await tester.pump(const Duration(milliseconds: 100));
            if (!state.loading && !tester.binding.hasScheduledFrame) return;
          }
        }
        fail('Search did not settle');
      }

      for (var page = 0; state.canContinue && page < 20; page++) {
        scroll().jumpTo(scroll().position.maxScrollExtent);
        await tester.pump();
        await settleSearch();
        expect(state.retainedHits, lessThanOrEqualTo(256));
      }
      expect(state.totalMatches, greaterThan(256));
      scroll().jumpTo(scroll().position.maxScrollExtent);
      await tester.pumpAndSettle();
      final anchor = state.scrollPosition.floor();
      expect(anchor, greaterThan(256));
      final hit = state.hitAt(anchor);
      tester
          .widget<ReaderSearchPanel>(find.byType(ReaderSearchPanel))
          .onClose();
      await tester.pumpAndSettle();
      await open(tester);
      expect(state.scrollPosition.floor(), anchor);
      expect(state.hitAt(anchor), hit);
      tester.view.physicalSize = const Size(580, 780);
      await tester.pumpAndSettle();
      expect(state.scrollPosition.floor(), anchor);
      scroll().jumpTo(scroll().position.minScrollExtent);
      await tester.pump();
      await settleSearch();
      expect(state.scrollPosition.floor(), 0);
      expect(state.hitAt(0), isNotNull);
      expect(state.retainedHits, lessThanOrEqualTo(256));
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  for (final logicalIndexAvailable in [true, false]) {
    testWidgets(
      'result titles use the hit section within one EPUB document (logical index: $logicalIndexAvailable)',
      (tester) async {
        final reader = await f.mount(
          tester,
          size: const Size(1040, 780),
          repositoryFactory: (store) =>
              ReaderSearchRepository(store)
                ..logicalIndexAvailable = logicalIndexAvailable,
        );
        await reader.link(tester, 'Same file');
        await open(tester);
        final state = search(reader, tester);
        Future<String?> title(LocalSearchHit hit) => tester.runAsync<String?>(
          () => tester
              .widget<ReaderSearchPanel>(find.byType(ReaderSearchPanel))
              .titleFor(hit, CancellationSource().token),
        );
        await submit(tester, state, 'a 0');
        final before = List.generate(state.loadedCount, state.hitAt)
            .whereType<LocalSearchHit>()
            .firstWhere((h) => h.chapter == reader.key('a'));
        expect(await title(before), 'a opening');
        await submit(tester, state, 'later');
        final after = List.generate(state.loadedCount, state.hitAt)
            .whereType<LocalSearchHit>()
            .firstWhere((h) => h.chapter == reader.key('a'));
        expect(await title(after), 'a later');
        expect(before.blockIndex, lessThan(after.blockIndex));
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.windows}),
    );
  }

  for (final palette in ['paper', 'warm', 'night']) {
    testWidgets(
      'search field follows reading palette $palette',
      (tester) async {
        await fonts(tester);
        final reader = await f.mount(
          tester,
          size: const Size(1040, 780),
          paper: palette == 'warm' ? ReaderPaper.warm : ReaderPaper.paper,
          dark: palette == 'night',
          repositoryFactory: ReaderSearchRepository.new,
        );
        await open(tester);
        await submit(tester, search(reader, tester), 'later');
        final input = tester.element(
          find.byKey(const ValueKey('reader-search-input')),
        );
        final theme = Theme.of(input);
        final fill = theme.inputDecorationTheme.fillColor!;
        expect(
          fill,
          Color.lerp(
            theme.scaffoldBackgroundColor,
            theme.colorScheme.outlineVariant,
            .22,
          ),
        );
        for (final foreground in [
          theme.colorScheme.onSurface,
          theme.inputDecorationTheme.hintStyle!.color!,
          theme.inputDecorationTheme.suffixIconColor!,
        ]) {
          final a = foreground.computeLuminance(), b = fill.computeLuminance();
          expect(
            (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(
          (theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder)
              .borderSide
              .color,
          theme.colorScheme.primary,
        );
        expect(theme.textTheme.bodyLarge!.color, theme.colorScheme.onSurface);
        final appTheme = shioriTheme(theme.brightness);
        if (palette == 'warm') {
          expect(fill, isNot(appTheme.inputDecorationTheme.fillColor));
        }
        await f.snapshot(tester, reader, 'search-palette-$palette');
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.windows}),
    );
  }

  testWidgets(
    'toolbar, explicit submit, same/main navigation and independent original link history',
    (tester) async {
      await fonts(tester);
      final reader = await f.mount(
        tester,
        size: const Size(1040, 780),
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester);
      final origin = reader.position(tester);
      await reader.link(
        tester,
        'B',
      ); // Existing link history must survive search.
      final before = reader.position(tester),
          chapter = reader.view(tester).content.key;
      await f.toggle(tester);
      expect(find.byKey(const ValueKey('reader-search-open')), findsOneWidget);
      final top = tester.widget<ReaderTopBar>(find.byType(ReaderTopBar));
      expect(top.showSearch, isTrue);
      await open(tester);
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('reader-search-input')),
        'later',
      );
      expect(state.loadedCount, 0);
      await submit(tester, state, 'later');
      expect(reader.position(tester), before);
      expect(reader.view(tester).content.key, chapter);
      final same = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)!.chapter == chapter);
      await select(tester, state, same);
      expect(reader.view(tester).content.key, chapter);
      expect(state.highlight.value, state.hitAt(same));
      await open(tester);
      final hit = state.hitAt(0)!;
      await f.snapshot(tester, reader, 'desktop-search-results');
      await select(tester, state, 0);
      expect(state.selectedIndex, 0);
      expect(state.highlight.value, hit);
      expect(reader.view(tester).content.key, hit.chapter);
      final highlighted = reader.position(tester);
      final geometry = tester
          .renderObjectList<ReaderSearchTextRender>(
            find.byType(ReaderPaintedSearchText),
          )
          .expand((r) => r.selectedBoxes)
          .toList();
      expect(geometry, isNotEmpty);
      await f.snapshot(tester, reader, 'desktop-selected-highlight');
      state.clearHighlight();
      await tester.pump();
      expect(reader.position(tester), highlighted);
      expect(state.canReturn.value, isTrue);
      reader.view(tester).actions.previousLocation!();
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, chapter);
      expect(reader.position(tester), before);
      expect(state.canReturn.value, isFalse);
      await reader.back(tester);
      expect(reader.view(tester).content.key, reader.key('a'));
      expect(reader.position(tester), origin);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'multiple hits keep first origin, auxiliary route borrows session, footnote uses source marker',
    (tester) async {
      final reader = await f.mount(
        tester,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester),
          repository = reader.repository as ReaderSearchRepository;
      final origin = reader.position(tester);
      await open(tester);
      await submit(tester, state, 'later');
      final auxiliary = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)?.chapter == reader.key('notes'));
      await select(tester, state, 0);
      await open(tester);
      await select(tester, state, auxiliary);
      expect(reader.view(tester).content.key, reader.key('notes'));
      expect(identical(reader.view(tester).search, state), isTrue);
      expect(repository.sessions, hasLength(1));
      reader.view(tester).actions.previousLocation!();
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, reader.key('a'));
      expect(reader.position(tester), origin);
      await open(tester);
      await submit(tester, state, 'annotation');
      expect(state.hitAt(0), isA<LocalSearchFootnoteHit>());
      await select(tester, state, 0);
      expect(
        find.textContaining('Fixture annotation.', findRichText: true),
        findsOneWidget,
      );
      expect(state.highlight.value, isNull);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'late validation, failure and maintenance preserve source and retire highlights',
    (tester) async {
      final reader = await f.mount(
        tester,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester),
          repository = reader.repository as ReaderSearchRepository;
      final origin = reader.position(tester);
      await open(tester);
      await submit(tester, state, 'later');
      repository.valid = false;
      await select(tester, state, 0);
      expect(reader.position(tester), origin);
      expect(state.canReturn.value, isFalse);
      expect(state.error, ReaderSearchError.expired);
      repository.invalidationsController.add(reader.key('a').novelKey);
      await tester.pumpAndSettle();
      expect(state.highlight.value, isNull);
      expect(state.loadedCount, 0);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'failed target and invalidation during panel close cannot commit a search origin',
    (tester) async {
      final reader = await f.mount(
        tester,
        pageTurn: PageTurnStyle.slide,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester),
          repository = reader.repository as ReaderSearchRepository;
      final origin = reader.position(tester),
          chapter = reader.view(tester).content.key;
      await open(tester);
      await submit(tester, state, 'later');
      repository.blocked = state.hitAt(0)!.chapter;
      repository.fail = true;
      await select(tester, state, 0);
      expect(reader.view(tester).content.key, chapter);
      expect(reader.position(tester), origin);
      expect(state.canReturn.value, isFalse);
      expect(state.error, ReaderSearchError.failed);
      repository.blocked = null;
      repository.fail = false;
      await open(tester);
      final panel = tester.widget<ReaderSearchPanel>(
        find.byType(ReaderSearchPanel),
      );
      unawaited(
        state.select(
          0,
          accepts: panel.accepts,
          closePanel: panel.closeForNavigation,
        ),
      );
      await tester
          .pump(); // validate has returned; the close transition has not completed.
      repository.invalidationsController.add(chapter.novelKey);
      await tester.pumpAndSettle();
      expect(state.canReturn.value, isFalse);
      expect(state.selectedIndex, isNull);
      expect(state.highlight.value, isNull);
      expect(state.navigating, isFalse);
      expect(reveals(tester).every((o) => o == 1), isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'auxiliary target revision changes after validation settles failure and returns source',
    (tester) async {
      final reader = await f.mount(
        tester,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester),
          repository = reader.repository as ReaderSearchRepository;
      final origin = reader.position(tester),
          chapter = reader.view(tester).content.key;
      await open(tester);
      await submit(tester, state, 'later');
      final auxiliary = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)!.chapter == reader.key('notes'));
      repository.changingTarget = reader.key('notes');
      await select(tester, state, auxiliary);
      expect(state.navigating, isFalse);
      expect(state.canReturn.value, isFalse);
      expect(state.selectedIndex, isNull);
      expect(state.highlight.value, isNull);
      expect(reader.view(tester).content.key, chapter);
      expect(reader.position(tester), origin);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'search started inside auxiliary content restores its exact semantic origin',
    (tester) async {
      final reader = await f.mount(
        tester,
        repositoryFactory: ReaderSearchRepository.new,
      );
      await reader.link(tester, 'Auxiliary');
      final linkOrigin = reader.position(tester);
      await reader.link(tester, 'Same file');
      unawaited(reader.view(tester).viewportController!.next());
      await tester.pumpAndSettle();
      final origin = reader.position(tester),
          chapter = reader.view(tester).content.key;
      final state = search(reader, tester);
      await open(tester);
      await submit(tester, state, 'later');
      await select(tester, state, 0);
      expect(reader.view(tester).content.key, isNot(chapter));
      reader.view(tester).actions.previousLocation!();
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, chapter);
      expect(reader.position(tester), origin);
      expect(state.canReturn.value, isFalse);
      expect(state.highlight.value, isNull);
      await reader.back(tester);
      expect(reader.view(tester).content.key, chapter);
      expect(reader.position(tester), linkOrigin);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'failed main target restores the retired auxiliary source and its links',
    (tester) async {
      final reader = await f.mount(
        tester,
        repositoryFactory: ReaderSearchRepository.new,
      );
      await reader.link(tester, 'Auxiliary');
      await reader.link(tester, 'Same file');
      final source = reader.view(tester).content.key,
          position = reader.position(tester);
      final state = search(reader, tester),
          repository = reader.repository as ReaderSearchRepository;
      await open(tester);
      await submit(tester, state, 'later');
      repository.changingTarget = state.hitAt(0)!.chapter;
      repository.changeAfter = 2;
      await select(tester, state, 0);
      expect(state.navigating, isFalse);
      expect(state.selectedIndex, isNull);
      expect(state.canReturn.value, isFalse);
      expect(reader.view(tester).content.key, source);
      expect(reader.position(tester), position);
      expect(reader.view(tester).actions.previousLocation, isNotNull);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'narrow desktop keeps focus and search geometry while editing an IME draft',
    (tester) async {
      await fonts(tester);
      final reader = await f.mount(
        tester,
        size: const Size(460, 780),
        scale: 1.2,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final origin = reader.position(tester), state = search(reader, tester);
      await open(tester);
      await submit(tester, state, 'later');
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('reader-search-input')),
      );
      input.controller!.value = const TextEditingValue(
        text: 'later中文',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 5, end: 7),
      );
      input.onChanged!(input.controller!.text);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSearchPanel), findsOneWidget);
      expect(find.textContaining('Showing results for'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(reader.position(tester), origin);
      await f.snapshot(tester, reader, 'narrow-desktop-search');
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'search from completion keeps completion and position until a confirmed result jump',
    (tester) async {
      final reader = await f.mount(
        tester,
        initial: 'd',
        repositoryFactory: ReaderSearchRepository.new,
      );
      final view = reader.view(tester),
          content = view.content,
          index = view.content.blocks.length - 1;
      final position = ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks[index].blockKey,
        blockIndex: index,
        blockFraction: 1,
        chapterFraction: 1,
      );
      view.viewportController!.restore(position);
      await tester.pumpAndSettle();
      view.actions.bookEnd!();
      await tester.pumpAndSettle();
      expect(reader.view(tester).completion, isNotNull);
      final saved = reader.position(tester), state = search(reader, tester);
      await open(tester);
      await submit(tester, state, 'later');
      expect(reader.view(tester).completion, isNotNull);
      expect(reader.position(tester), saved);
      await select(tester, state, 0);
      expect(state.selectedIndex, 0);
      expect(reader.view(tester).completion, isNull);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'touch sheet keyboard preserves underlying pagination and dismisses without navigation',
    (tester) async {
      await fonts(tester);
      final reader = await f.mount(
        tester,
        size: const Size(400, 800),
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester), origin = reader.position(tester);
      await f.toggle(tester);
      await tester.tap(find.byKey(const ValueKey('reader-search-open')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSearchPanel), findsOneWidget);
      final size = tester.getSize(
        find.byKey(const ValueKey('reader-search-results')),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await submit(tester, state, 'later');
      await f.snapshot(tester, reader, 'mobile-keyboard-search');
      expect(reader.position(tester), origin);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('reader-search-results')))
            .height,
        lessThan(size.height),
      );
      final panel = tester.widget<ReaderSearchPanel>(
        find.byType(ReaderSearchPanel),
      );
      panel.onClose();
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(reader.position(tester), origin);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
