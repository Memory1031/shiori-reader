import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_completion_page.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/reader_chrome.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_contents.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'cross_chapter_drag_test.dart' show Images;
import 'package:shiori/features/reader/viewport/page_turn.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'completion_test.dart' show CompletionRepository;
import 'restore_test.dart' show ObservedLibrary;
import 'settings_test.dart' show Store;

class EndRepository extends CompletionRepository
    implements LocalBookInvalidation {
  EndRepository({super.local, super.status});
  final invalidated = StreamController<NovelKey>.broadcast();
  @override
  Stream<NovelKey> get invalidations => invalidated.stream;
  @override
  Stream<NovelKey> get changes => const Stream.empty();
  List<ContentBlock>? blocks;
  int chapterLoads = 0;
  @override
  ChapterContent content(ChapterKey key) => ChapterContent(
    key: key,
    title: 'Last chapter',
    blocks: blocks ?? [ParagraphBlock(text: 'Visible final sentence.')],
  );
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    chapterLoads++;
    return super.loadChapter(key, mode: mode, cancellation: cancellation);
  }
}

class EndLibrary extends ObservedLibrary {
  EndLibrary(super.inner);
  bool fail = false;
  @override
  Future<Result<bool>> saveProgress(
    ReadingProgress progress, {
    required ProgressWriteStamp stamp,
    required CancellationToken cancellation,
  }) {
    if (fail) {
      return Future.value(
        Failure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.progressWrite,
            retryPolicy: RetryPolicy.manual,
          ),
        ),
      );
    }
    return super.saveProgress(
      progress,
      stamp: stamp,
      cancellation: cancellation,
    );
  }
}

class Harness {
  Harness({bool local = false, NovelStatus status = NovelStatus.ongoing})
    : repo = EndRepository(local: local, status: status);
  final EndRepository repo;
  final storage = FixtureLibraryRepository();
  late final library = EndLibrary(storage);
  ImageRepository? images;
  final settings = Store()..value = ReaderSettings(controlsHintSeen: true);
  ReaderContentView view(WidgetTester tester) => tester
      .widgetList<ReaderContentView>(
        find.byType(ReaderContentView, skipOffstage: false),
      )
      .singleWhere((v) => v.appearanceActive == true);
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(600, 800),
    double scale = 1,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShioriApp(
        locale: locale,
        routes: AppRoutes(
          home: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: BookReaderScreen(
              chapter: repo.order.last,
              repository: repo,
              library: library,
              settings: settings,
              images: images,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester) async {
    await view(tester).viewportController!.next();
    await tester.pumpAndSettle();
    expect(view(tester).completion, isNotNull);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await repo.updates.close();
    await repo.invalidated.close();
    await storage.close();
  }
}

PageTurnFrame frame(WidgetTester tester) => tester
    .widget<PageTurnSlot>(
      find
          .descendant(
            of: find
                .byKey(
                  const ValueKey('completion-reader-layer'),
                  skipOffstage: false,
                )
                .first,
            matching: find.byType(PageTurnSlot, skipOffstage: false),
            skipOffstage: false,
          )
          .first,
    )
    .frame;
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

Future<TestGesture> drag(
  WidgetTester tester,
  bool entering, {
  double distance = 240,
  double y = 400,
  double width = 600,
}) async {
  final sign = entering ? -1.0 : 1.0;
  final gesture = await tester.startGesture(
    Offset(entering ? width * .75 : width * .25, y),
  );
  await gesture.moveBy(Offset(sign * 24, 0));
  await tester.pump(const Duration(milliseconds: 40));
  await gesture.moveBy(Offset(sign * distance, 0));
  await frames(tester);
  return gesture;
}

int terminals(Harness h) => h.library.writes
    .where((p) => p.bookProgress?.terminal != BookTerminalState.reading)
    .length;

void main() {
  for (final style in PageTurnStyle.values) {
    testWidgets(
      '$style previews both directions without terminal writes and commits once',
      (tester) async {
        final h = Harness();
        h.settings.value = h.settings.value.copyWith(pageTurn: style);
        await h.open(tester);
        final original = h.view(tester).session;
        final viewport = tester.state(find.byType(PagedReaderViewport));
        final position = h.view(tester).viewportController!.capture();
        final loads = h.repo.chapterLoads;
        final measured = h.view(tester).viewportController!.measuredChunks;
        final gesture = await drag(tester, true, y: 620);
        expect(frame(tester).progress, closeTo(.4, .001));
        expect(frame(tester).grip, closeTo(620 / 800, .01));
        expect(h.view(tester).completion, isNull);
        expect(terminals(h), 0);
        expect(h.library.sessions, 1);
        expect(h.view(tester).viewportController!.measuredChunks, measured);
        await gesture.up();
        await frames(tester);
        if (style != PageTurnStyle.none) {
          expect(frame(tester).progress, closeTo(.4, .001));
          expect(h.view(tester).completion, isNull);
          await tester.pump(const Duration(milliseconds: 30));
          expect(frame(tester).progress, inExclusiveRange(.4, 1));
        }
        await tester.pumpAndSettle();
        expect(h.view(tester).completion, BookTerminalState.caughtUp);
        expect(terminals(h), 1);
        expect(frame(tester).progress, 1);
        final back = await drag(tester, false, y: 140);
        expect(frame(tester).progress, closeTo(.4, .001));
        expect(frame(tester).direction, -1);
        expect(frame(tester).grip, closeTo(140 / 800, .01));
        expect(h.view(tester).completion, isNotNull);
        await back.up();
        await tester.pumpAndSettle();
        expect(h.view(tester).completion, isNull);
        expect(h.view(tester).session, same(original));
        expect(tester.state(find.byType(PagedReaderViewport)), same(viewport));
        expect(h.view(tester).viewportController!.capture(), position);
        expect(h.repo.chapterLoads, loads);
        expect(h.library.sessions, 1);
        expect(terminals(h), 1);
        expect(
          h.view(tester).session!.progress!.bookProgress!.terminal,
          BookTerminalState.caughtUp,
        );
        expect(find.text('Visible final sentence.'), findsOneWidget);
        await h.close(tester);
      },
    );
  }
  for (final entering in [true, false]) {
    for (final kind in ['small', 'reverse', 'pointer', 'endpoint']) {
      testWidgets(
        '$kind cancels completion direction $entering without changing persisted terminal',
        (tester) async {
          final h = Harness();
          await h.open(tester);
          if (!entering) await h.enter(tester);
          final initial = h.view(tester).completion;
          final count = terminals(h);
          final gesture = await drag(
            tester,
            entering,
            distance: kind == 'small'
                ? 70
                : kind == 'endpoint'
                ? 650
                : 250,
          );
          if (kind == 'endpoint') {
            expect(frame(tester).progress, 1);
            await tester.pump(const Duration(seconds: 46));
            expect(h.view(tester).completion, initial);
            expect(terminals(h), count);
          }
          if (kind == 'pointer' || kind == 'endpoint') {
            await gesture.cancel();
          } else if (kind == 'reverse') {
            final sign = entering ? 1.0 : -1.0;
            for (var i = 0; i < 4; i++) {
              await tester.pump(const Duration(milliseconds: 5));
              await gesture.moveBy(
                Offset(sign * 12, 0),
                timeStamp: Duration(milliseconds: 100 + i * 10),
              );
            }
            await gesture.up(timeStamp: const Duration(milliseconds: 145));
          } else {
            await tester.pump(const Duration(milliseconds: 200));
            await gesture.up();
          }
          await tester.pumpAndSettle();
          expect(h.view(tester).completion, initial);
          expect(terminals(h), count);
          expect(h.library.sessions, 1);
          await h.close(tester);
        },
      );
    }
    testWidgets(
      'escape and repeated cancellation preserve intermediate rebound $entering',
      (tester) async {
        final h = Harness();
        await h.open(tester);
        if (!entering) await h.enter(tester);
        final initial = h.view(tester).completion;
        final count = terminals(h);
        final gesture = await drag(tester, entering);
        await gesture.up();
        await frames(tester);
        await tester.pump(const Duration(milliseconds: 30));
        final before = frame(tester).progress;
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final rebound = frame(tester).progress;
        expect(rebound, inExclusiveRange(0, before));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        expect(frame(tester).progress, inExclusiveRange(0, rebound));
        await tester.pumpAndSettle();
        expect(h.view(tester).completion, initial);
        expect(terminals(h), count);
        await h.close(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'completion chrome uses shared commands without a progress control',
    (tester) async {
      final h = Harness();
      await h.open(tester);
      await h.enter(tester);
      final session = h.view(tester).session;
      final viewport = tester.state(
        find.byType(PagedReaderViewport, skipOffstage: false),
      );
      final count = terminals(h);
      await tester.tapAt(const Offset(300, 110));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderToolbars), findsOneWidget);
      expect(
        tester.widget<ReaderTopBar>(find.byType(ReaderTopBar)).title,
        'Book',
      );
      expect(
        tester
            .widget<ReaderBottomBar>(find.byType(ReaderBottomBar))
            .showProgress,
        isFalse,
      );
      expect(find.textContaining('Chapter '), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(ReaderStatusRow), findsNothing);
      await tester.tap(find.text('Aa'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.view(tester).completion, isNotNull);
      await tester.tap(
        find.descendant(
          of: find.byType(ReaderBottomBar),
          matching: find.byIcon(Icons.list),
        ),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.view(tester).completion, isNotNull);
      await tester.tapAt(const Offset(30, 110));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderToolbars), findsNothing);
      expect(h.view(tester).completion, isNotNull);
      expect(
        find.byType(ReaderStatusRow),
        defaultTargetPlatform == TargetPlatform.windows
            ? findsNothing
            : findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderToolbars), findsOneWidget);
      expect(h.view(tester).session, same(session));
      expect(
        tester.state(find.byType(PagedReaderViewport, skipOffstage: false)),
        same(viewport),
      );
      expect(terminals(h), count);
      await h.close(tester);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'catalog growth cancels a held terminal preview before any terminal write',
    (tester) async {
      final h = Harness();
      await h.open(tester);
      final gesture = await drag(tester, true);
      h.repo.count = 3;
      h.repo.updates.add(h.repo.result(h.repo.catalog));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(h.view(tester).completion, isNull);
      expect(terminals(h), 0);
      expect(h.view(tester).content.key, h.repo.keys[1]);
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );

  for (final event in [
    'background',
    'route',
    'resize',
    'dispose',
    'invalidate',
  ]) {
    testWidgets('$event invalidates held completion without late commit', (
      tester,
    ) async {
      final h = Harness();
      await h.open(tester);
      final gesture = await drag(tester, true);
      switch (event) {
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        case 'route':
          Navigator.of(
            tester.element(find.byType(ReaderContentView).first),
          ).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover')),
            ),
          );
        case 'resize':
          tester.view.physicalSize = const Size(700, 850);
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
        case 'invalidate':
          h.repo.invalidated.add(h.repo.key);
      }
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(terminals(h), 0);
      expect(tester.takeException(), isNull);
      if (event == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await h.close(tester);
    });
  }
  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      'short completion scroll survives chrome toggles at 2x ${locale.languageCode}',
      (tester) async {
        final h = Harness();
        await h.open(
          tester,
          size: const Size(320, 480),
          scale: 2,
          locale: locale,
        );
        await h.enter(tester);
        final completion = tester.state(find.byType(ReaderCompletionPage));
        final scroll = find.descendant(
          of: find.byType(ReaderCompletionPage),
          matching: find.byType(Scrollable),
        );
        final scrollState = tester.state<ScrollableState>(scroll);
        await tester.drag(
          find.byType(ReaderCompletionPage),
          const Offset(0, -260),
        );
        await tester.pumpAndSettle();
        final offset = scrollState.position.pixels;
        expect(offset, greaterThan(0));
        for (var i = 0; i < 4; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.f2);
          await tester.pumpAndSettle();
          expect(scrollState.position.pixels, offset);
          expect(
            tester.state(find.byType(ReaderCompletionPage)),
            same(completion),
          );
        }
        expect(h.view(tester).completion, isNotNull);
        expect(tester.takeException(), isNull);
        await h.close(tester);
      },
    );
  }
  testWidgets(
    'resize and typography prepare canonical final spread behind completion',
    (tester) async {
      final h = Harness(local: true);
      h.repo.blocks = [
        for (var i = 0; i < 45; i++)
          ParagraphBlock(text: 'Paragraph $i ${'synthetic prose ' * 14}'),
        ParagraphBlock(text: 'UNIQUE EOF MARKER'),
      ];
      await h.open(tester);
      final view = h.view(tester);
      final content = view.content;
      view.viewportController!.restore(
        ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks.last.blockKey,
          blockIndex: content.blocks.length - 1,
          blockFraction: 1,
          chapterFraction: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('UNIQUE EOF MARKER'), findsOneWidget);
      await h.enter(tester);
      final viewport = tester.state(
        find.byType(PagedReaderViewport, skipOffstage: false),
      );
      final loads = h.repo.chapterLoads;
      final saved = h.library.writes.last;
      for (final size in [
        const Size(1400, 700),
        const Size(420, 850),
        const Size(1500, 800),
      ]) {
        tester.view.physicalSize = size;
        view.preferences!.update(
          view.preferences!.value.copyWith(fontSize: 27, lineHeight: 1.9),
        );
        await tester.pump();
        // A return request during any pending reflow must keep completion visible.
        if (view.viewportController!.isRestoring) {
          await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
          await tester.pump();
          expect(h.view(tester).completion, isNotNull);
        }
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(PagedReaderViewport, skipOffstage: false)),
          same(viewport),
        );
        expect(h.library.writes.last, saved);
        expect(
          h.view(tester).session!.restoreStatus,
          ReaderRestoreStatus.ready,
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(h.view(tester).completion, isNull);
      expect(find.text('UNIQUE EOF MARKER'), findsOneWidget);
      expect(
        tester
            .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
            .columns,
        2,
      );
      expect(h.repo.chapterLoads, loads);
      expect(h.library.sessions, 1);
      expect(h.library.writes.last, saved);
      // Reading further backwards is a real navigation, and clears terminal.
      unawaited(h.view(tester).viewportController!.previous());
      await tester.pumpAndSettle();
      await h.view(tester).session!.flushProgress();
      expect(
        h.library.writes.last.bookProgress!.terminal,
        BookTerminalState.reading,
      );
      await h.close(tester);
    },
  );
  for (final entering in [true, false]) {
    for (final commit in [true, false]) {
      testWidgets(
        'late image geometry stays frozen through completion direction $entering commit $commit',
        (tester) async {
          final h = Harness();
          h.repo.blocks = [
            ImageBlock(
              media: MediaRef(sourceId: h.repo.key.sourceId, mediaId: 'image'),
            ),
            ParagraphBlock(text: 'EOF after image'),
          ];
          h.images = Images();
          await h.open(tester);
          if (!entering) await h.enter(tester);
          final viewport = h.view(tester).viewportController!;
          final generation = viewport.layoutGeneration;
          final gesture = await drag(tester, entering);
          final image = tester.widget<ReaderImage>(
            find.byType(ReaderImage, skipOffstage: false),
          );
          image.onIntrinsicSize(const Size(200, 100));
          await frames(tester);
          expect(viewport.layoutGeneration, generation);
          if (commit) {
            await gesture.up();
          } else {
            await gesture.cancel();
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 30));
          expect(viewport.layoutGeneration, generation);
          await tester.pumpAndSettle();
          expect(viewport.layoutGeneration, greaterThan(generation));
          expect(
            h.view(tester).completion != null,
            commit ? entering : !entering,
          );
          if (h.view(tester).completion != null) {
            await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
            await tester.pumpAndSettle();
          }
          expect(find.text('EOF after image'), findsOneWidget);
          expect(h.library.sessions, 1);
          await h.close(tester);
        },
      );
    }
  }
  testWidgets('wide final spread uses whole-page drag progress', (
    tester,
  ) async {
    final h = Harness();
    await h.open(tester, size: const Size(1400, 800));
    expect(
      tester
          .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
          .columns,
      2,
    );
    final gesture = await drag(
      tester,
      true,
      width: 1400,
      distance: 350,
      y: 660,
    );
    expect(frame(tester).progress, closeTo(.25, .001));
    expect(frame(tester).grip, closeTo(660 / 800, .01));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(h.view(tester).completion, isNull);
    expect(terminals(h), 0);
    await h.close(tester);
  });
  testWidgets('reduced motion still requires release at the held endpoint', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = Harness();
    await h.open(tester);
    final gesture = await drag(tester, true, distance: 650);
    expect(frame(tester).progress, 1);
    expect(terminals(h), 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(terminals(h), 1);
    await h.close(tester);
  });
  testWidgets('completion exposes progress and settings failure recovery', (
    tester,
  ) async {
    final h = Harness();
    await h.open(tester);
    h.library.fail = true;
    await h.enter(tester);
    expect(h.view(tester).session!.progress!.unsaved, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(
      find.text('Reading progress not saved. Tap to retry.'),
      findsOneWidget,
    );
    h.library.fail = false;
    await tester.tap(find.text('Reading progress not saved. Tap to retry.'));
    await tester.pumpAndSettle();
    expect(h.view(tester).session!.progress!.unsaved, isFalse);
    h.settings.fail = true;
    final prefs = h.view(tester).preferences!;
    prefs.update(prefs.value.copyWith(paper: ReaderPaper.warm));
    await prefs.flush();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load or save reading settings.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Could not load or save reading settings.'));
    await tester.pumpAndSettle();
    h.settings.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(prefs.failure, isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.view(tester).completion, isNotNull);
    expect(h.library.sessions, 1);
    await h.close(tester);
  });
  testWidgets(
    'system back cancels a completion turn before hiding shared chrome',
    (tester) async {
      final h = Harness();
      await h.open(tester);
      h.view(tester).chrome!.value = true;
      await tester.pumpAndSettle();
      final gesture = await drag(tester, true);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(h.view(tester).completion, isNull);
      expect(h.view(tester).chrome!.value, isTrue);
      expect(terminals(h), 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.view(tester).chrome!.value, isFalse);
      await h.close(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  for (final table in [false, true]) {
    testWidgets(
      'completion preserves native ${table ? "table" : "rich text"} final page',
      (tester) async {
        final h = Harness();
        h.repo.blocks = [
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
        ];
        await h.open(tester);
        final viewport = tester.state(find.byType(PagedReaderViewport));
        final gesture = await drag(tester, true);
        expect(frame(tester).progress, inExclusiveRange(0, 1));
        await gesture.up();
        await tester.pumpAndSettle();
        final back = await drag(tester, false);
        await back.up();
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(PagedReaderViewport)), same(viewport));
        expect(
          tester
              .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
              .map((v) => v.text)
              .join(),
          contains('Value text'),
        );
        await h.close(tester);
      },
    );
  }
  for (final toShelf in [false, true]) {
    testWidgets(
      'completion ${toShelf ? "shelf button" : "top back"} invokes only its navigation',
      (tester) async {
        final h = Harness();
        var shelfCalls = 0;
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BookReaderScreen(
                        chapter: h.repo.order.last,
                        repository: h.repo,
                        library: h.library,
                        settings: h.settings,
                        onReturnToShelf: () {
                          shelfCalls++;
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ),
                  child: const Text('Open reader'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open reader'));
        await tester.pumpAndSettle();
        await h.enter(tester);
        if (toShelf) {
          await tester.tap(find.text('Back to bookshelf'));
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.f2);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(BackButton));
        }
        await tester.pumpAndSettle();
        expect(find.text('Open reader'), findsOneWidget);
        expect(find.byType(ReaderContentView), findsNothing);
        expect(shelfCalls, toShelf ? 1 : 0);
        expect(h.library.sessions, 1);
        await h.close(tester);
      },
    );
  }
  for (final key in [LogicalKeyboardKey.space, LogicalKeyboardKey.enter]) {
    testWidgets(
      'focused completion button owns ${key.keyLabel}',
      (tester) async {
        final h = Harness();
        await h.open(tester);
        await h.enter(tester);
        final before = terminals(h);
        Focus.of(tester.element(find.text('View contents'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(find.byType(ReaderContentsPanel), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(h.view(tester).completion, isNotNull);
        expect(terminals(h), before);
        await h.close(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
