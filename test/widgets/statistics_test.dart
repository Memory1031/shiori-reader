import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/reading_statistics_repository.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/data/local/record_codec.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/statistics/reading_statistics_controller.dart';
import 'package:shiori/features/statistics/statistics_view.dart';
import 'package:shiori/shared/widgets/reading_statistics_scope.dart';
import '../domain/reading_statistics/reading_clock_test.dart'
    show TestReadingClock;

class DelayedStatistics extends LocalReadingStatisticsRepository {
  DelayedStatistics(super.db);
  Completer<void>? gate;
  int reads = 0, inFlight = 0, peak = 0;
  bool liveChanges = false;
  @override
  Stream<void> get changes =>
      liveChanges ? super.changes : const Stream.empty();
  @override
  Future<Result<ReadingStatisticsSnapshot>> read({
    required int firstDay,
    required int lastDay,
    required int today,
  }) async {
    reads++;
    inFlight++;
    if (inFlight > peak) peak = inFlight;
    try {
      final waiting = gate;
      final result = await super.read(
        firstDay: firstDay,
        lastDay: lastDay,
        today: today,
      );
      if (waiting != null) await waiting.future;
      return result;
    } finally {
      inFlight--;
    }
  }
}

class UnavailableStatistics implements ReadingStatisticsRepository {
  bool failing = true;
  int reads = 0;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<Result<ReadingRecordSettings>> settings() async => failing
      ? Failure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.libraryRead,
          ),
        )
      : const Success(ReadingRecordSettings());
  @override
  Future<Result<ReadingStatisticsSnapshot>> read({
    required int firstDay,
    required int lastDay,
    required int today,
  }) async {
    reads++;
    return Success(
      ReadingStatisticsSnapshot(
        settings: const ReadingRecordSettings(),
        lifetime: 0,
        today: 0,
        days: const {},
        books: const [],
        anonymous: 0,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CacheImages implements ImageRepository {
  final modes = <ReadMode>[];
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    modes.add(mode);
    return Failure(
      AppFailure(
        kind: FailureKind.cache,
        operation: Operation.media,
        context: FailureContext.cacheMiss,
      ),
    );
  }
}

void main() {
  late UserDatabase db;
  late DelayedStatistics repo;
  late ReadingStatisticsController recorder;
  setUp(() {
    db = UserDatabase(NativeDatabase.memory());
    repo = DelayedStatistics(db);
    recorder = ReadingStatisticsController(
      repo,
      clock: TestReadingClock(),
      schedule: false,
    );
  });
  tearDown(() async {
    await recorder.close();
    recorder.dispose();
    await db.close();
  });
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Finder periodDuration(String value) => find.descendant(
    of: find.byKey(const ValueKey('statistics-period-total')),
    matching: find.text(value),
  );

  testWidgets(
    'hidden home defers statistics while progress and recording continue',
    (tester) async {
      // Exercise mobile tabs and the desktop nested navigator.
      final pointer = defaultTargetPlatform == TargetPlatform.windows;
      tester.view
        ..physicalSize = pointer ? const Size(1200, 900) : const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final env = FixtureEnvironment(), navigation = HomeNavigation();
      final navigator = GlobalKey<NavigatorState>();
      final library = LocalLibraryRepository(db);
      final clock = TestReadingClock(DateTime(2026, 10, 21, 23, 59, 58));
      await tester.runAsync(() async {
        await recorder.ready;
        await recorder.close();
        recorder.dispose();
        repo.liveChanges = true;
        recorder = ReadingStatisticsController(
          repo,
          clock: clock,
          schedule: false,
        );
        await recorder.ready;
        await recorder.dismissNotice();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.runAsync(env.close);
        navigation.dispose();
      });
      await tester.pumpWidget(
        ShioriApp(
          navigatorKey: navigator,
          locale: const Locale('en'),
          homeBuilder: (_, _) => ReadingStatisticsScope(
            controller: recorder,
            child: ReadingHome(
              repository: env.novels,
              library: library,
              sources: const [],
              navigation: navigation,
            ),
          ),
        ),
      );
      await settle(tester);
      expect(repo.reads, 0);
      Future<void> section(HomeSection section) async {
        if (pointer) {
          navigation.select(section);
        } else {
          await tester.tap(
            find.widgetWithText(
              NavigationDestination,
              section == HomeSection.statistics ? 'Statistics' : 'Bookshelf',
            ),
          );
        }
        await settle(tester);
      }

      await section(HomeSection.statistics);
      expect(repo.reads, greaterThan(0));
      await section(HomeSection.shelf);
      final before = repo.reads;
      await tester.runAsync(() => recorder.setEnabled(false));
      final book = env.source.data.summary(FixtureScenario.shortChapter);
      final token = CancellationSource().token;
      late int generation;
      await tester.runAsync(() async {
        generation =
            (await library.beginProgressSession(book.key, cancellation: token)
                    as Success<int>)
                .value;
      });
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() async {
          expect(
            await library.saveProgress(
              ReadingProgress(
                snapshot: book,
                chapterKey: ChapterKey(
                  novelKey: book.key,
                  chapterId: 'chapter',
                ),
                chapterOrdinalSnapshot: 0,
                catalogRevision: 'catalog',
                position: ReaderPosition(
                  contentRevision: 'content',
                  blockKey: 'block',
                  blockIndex: 0,
                  blockFraction: i / 10,
                  chapterFraction: i / 10,
                ),
                completed: false,
                lastReadAt: clock.now,
              ),
              stamp: ProgressWriteStamp(generation: generation, sequence: i),
              cancellation: token,
            ),
            isA<Success<bool>>().having((r) => r.value, 'saved', true),
          );
        });
        await settle(tester);
        expect(repo.reads, before);
      }
      await tester.runAsync(() async {
        final saved =
            await library.getProgress(book.key, cancellation: token)
                as Success<ReadingProgress?>;
        expect(saved.value!.position.blockFraction, .9);
      });
      final owner = Object();
      await tester.runAsync(() => recorder.setEnabled(true));
      recorder.source(owner, book.key, visible: true, activity: true);
      await settle(tester);
      expect(recorder.recording, true);
      clock.advance(const Duration(seconds: 10));
      await tester.runAsync(recorder.tick);
      recorder.release(owner);
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(repo.reads, before);
      await section(HomeSection.statistics);
      expect(periodDuration('Less than 1 minute'), findsOneWidget);
      expect(find.text('Oct 16 – 22'), findsOneWidget);

      final covered = repo.reads;
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Reader overlay')),
          ),
        ),
      );
      await settle(tester);
      for (var i = 0; i < 10; i++) {
        recorder.environment(focused: i.isOdd);
        await settle(tester);
      }
      expect(repo.reads, covered);
      navigator.currentState!.pop();
      await settle(tester);
      expect(repo.reads, greaterThan(covered));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = repo.reads;
      for (var i = 0; i < 10; i++) {
        recorder.environment(focused: i.isEven);
        await settle(tester);
      }
      clock.advance(const Duration(days: 1));
      await tester.pump(const Duration(days: 1));
      await settle(tester);
      expect(repo.reads, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(repo.reads, greaterThan(paused));
      expect(find.text('Oct 17 – 23'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'slow statistics reads coalesce changes and reject hidden results',
    (tester) async {
      final key = NovelKey(sourceId: SourceId('s'), novelId: 'n');
      late ReadingRecordSession session;
      await tester.runAsync(() async {
        await recorder.ready;
        session =
            (await repo.begin(key) as Success<ReadingRecordSession?>).value!;
        await repo.submit(ReadingCheckpoint(session, 1, {20261021: 90000}));
      });
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ShioriApp(
          navigatorKey: navigator,
          locale: const Locale('en'),
          homeBuilder: (_, _) =>
              Scaffold(body: StatisticsView(controller: recorder)),
        ),
      );
      await settle(tester);
      final before = repo.reads;
      final gate = repo.gate = Completer<void>();
      final hiddenGate = Completer<void>();
      addTearDown(() async {
        repo.gate = null;
        if (!gate.isCompleted) gate.complete();
        if (!hiddenGate.isCompleted) hiddenGate.complete();
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      });
      await tester.tap(find.text('30 days'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(repo.inFlight, 1);
      for (var i = 0; i < 10; i++) {
        recorder.environment(focused: i.isOdd);
        await tester.pump();
      }
      await tester.tap(find.text('12 months'));
      await tester.pump();
      expect(repo.reads, before + 1);
      repo.gate = null;
      await tester.runAsync(() async {
        await repo.submit(ReadingCheckpoint(session, 2, {20261021: 90000}));
        gate.complete();
      });
      await settle(tester);
      expect(repo.reads, before + 2);
      expect(repo.peak, 1);
      expect(periodDuration('3 min'), findsOneWidget);
      expect(find.text('Nov 2025 – Oct 2026'), findsOneWidget);

      repo.gate = hiddenGate;
      await tester.tap(find.text('7 days'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(repo.inFlight, 1);
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Reader overlay')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repo.gate = null;
      await tester.runAsync(() async {
        await repo.submit(ReadingCheckpoint(session, 3, {20261021: 60000}));
        hiddenGate.complete();
      });
      await settle(tester);
      expect(repo.inFlight, 0);
      expect(repo.reads, before + 3);
      expect(periodDuration('3 min'), findsNothing);
      final hiddenTotal = find.byKey(
        const ValueKey('statistics-period-total'),
        skipOffstage: false,
      );
      expect(
        find.descendant(
          of: hiddenTotal,
          matching: find.text('3 min', skipOffstage: false),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      navigator.currentState!.pop();
      await settle(tester);
      expect(repo.reads, before + 4);
      expect(repo.peak, 1);
      expect(periodDuration('4 min'), findsOneWidget);
      expect(find.text('Oct 15 – 21'), findsOneWidget);
    },
  );

  testWidgets('duration groups stay readable at large phone text sizes', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await recorder.ready;
      final key = NovelKey(sourceId: SourceId('s'), novelId: 'n');
      final session =
          (await repo.begin(key) as Success<ReadingRecordSession?>).value!;
      await repo.submit(ReadingCheckpoint(session, 1, {20261021: 112 * 60000}));
    });
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        overlayBuilder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child,
        ),
        homeBuilder: (_, _) =>
            Scaffold(body: StatisticsView(controller: recorder)),
      ),
    );
    await settle(tester);
    for (final text in ['1 h', '52 min']) {
      final group = find.text(text).first;
      final rect = tester.getRect(group);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: group, matching: find.byType(RichText)),
      );
      final painter = TextPainter(
        text: paragraph.text,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
      )..layout(maxWidth: paragraph.size.width);
      addTearDown(painter.dispose);
      expect(painter.computeLineMetrics(), hasLength(1));
    }
    final l = AppLocalizations.of(tester.element(find.byType(StatisticsView)));
    expect(readingDuration(l, 26 * 3600000), '26 h');
    expect(readingDuration(l, 30000), 'Less than 1 minute');
    expect(find.text('120'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('Oct 15 – 21'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('book list expands from five and keeps removed time separate', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 1100)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await recorder.ready;
      for (var i = 0; i < 8; i++) {
        final key = NovelKey(sourceId: SourceId('s'), novelId: 'book$i');
        await db.customStatement("INSERT INTO bookshelf VALUES('s',?,?,0,0)", [
          key.novelId,
          RecordCodec.summary(NovelSummary(key: key, title: 'Book $i')),
        ]);
        final session =
            (await repo.begin(key) as Success<ReadingRecordSession?>).value!;
        await repo.submit(
          ReadingCheckpoint(session, 1, {20261021: (8 - i) * 60000}),
        );
      }
    });
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        homeBuilder: (_, _) =>
            Scaffold(body: StatisticsView(controller: recorder)),
      ),
    );
    await settle(tester);
    expect(find.text('Book 4'), findsOneWidget);
    expect(find.text('Book 5'), findsNothing);
    expect(find.text('Removed books'), findsNothing);
    await tester.tap(find.text('Show all 8 books'));
    await settle(tester);
    expect(find.text('Book 7'), findsOneWidget);
    await tester.tap(find.text('Show less'));
    await settle(tester);
    expect(find.text('Book 5'), findsNothing);
    await tester.tap(find.text('Show all 8 books'));
    await settle(tester);
    tester.view.physicalSize = const Size(1280, 700);
    await settle(tester);
    final heading = find.text('Read in this period');
    final headingTop = tester.getTopLeft(heading);
    final list = find.byType(CustomScrollView);
    await tester.scrollUntilVisible(
      find.text('Show less'),
      150,
      scrollable: find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first,
    );
    await settle(tester);
    expect(tester.getTopLeft(heading), headingTop);
    final timeRight = tester.getRect(find.text('1 min').last).right;
    expect(tester.getRect(list).right - timeRight, greaterThanOrEqualTo(12));
    await tester.tap(find.text('Show less'));
    await settle(tester);
    expect(find.text('Book 5'), findsNothing);
    expect(find.text('Show all 8 books').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Show all 8 books'));
    await settle(tester);
    await tester.tap(find.text('30 days'));
    await settle(tester);
    expect(find.text('Book 5'), findsNothing);
    expect(find.text('Show all 8 books'), findsOneWidget);
    await tester.runAsync(() async {
      final key = NovelKey(sourceId: SourceId('s'), novelId: 'removed');
      final session =
          (await repo.begin(key) as Success<ReadingRecordSession?>).value!;
      await repo.submit(ReadingCheckpoint(session, 1, {20261021: 4 * 60000}));
      await db.removeReadingStatistics('s', 'removed');
      await recorder.reload();
    });
    await settle(tester);
    final removedRow = find
        .ancestor(of: find.text('Removed books'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: removedRow, matching: find.text('4 min')),
      findsOneWidget,
    );
    await tester.tap(find.text('Show all 8 books'));
    await settle(tester);
    expect(
      find.descendant(of: removedRow, matching: find.text('4 min')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('30-day labels retain readable size at phone widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => recorder.ready);
    for (final width in [320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          overlayBuilder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child,
          ),
          homeBuilder: (_, _) =>
              Scaffold(body: StatisticsView(controller: recorder)),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('30 days'));
      await settle(tester);
      final labels = ['9/22', '10/6', '10/21'].map(find.text).toList();
      final rects = labels.map((label) {
        final box = tester.renderObject<RenderBox>(label);
        expect(
          find.ancestor(of: label, matching: find.byType(FittedBox)),
          findsNothing,
        );
        return MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        );
      }).toList();
      final chart = tester.getRect(
        find
            .descendant(
              of: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.slider == true,
              ),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      for (final rect in rects) {
        expect(rect.width, greaterThan(40));
        expect(rect.height, greaterThanOrEqualTo(27));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
      }
      expect(rects[0].right, lessThan(rects[1].left));
      expect(rects[1].right, lessThan(rects[2].left));
      expect(rects.first.left, closeTo(chart.left, .01));
      expect(rects.last.right, closeTo(chart.right, .01));
      expect(
        rects[1].center.dx,
        closeTo(chart.left + chart.width * 14.5 / 30, .01),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets(
    'desktop record management is a centered bounded dialog',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => recorder.ready);
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          homeBuilder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showStatisticsSettings(context, recorder),
                child: const Text('Open management'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open management'));
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      final panel = find.byWidget(dialog.child!);
      expect(tester.getSize(panel).width, lessThanOrEqualTo(560));
      expect(tester.getCenter(panel), const Offset(640, 450));
      await tester.tap(find.text('Clear statistics'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Clear statistics'),
      );
      final scheme = Theme.of(
        tester.element(find.byType(AlertDialog)),
      ).colorScheme;
      expect(confirm.style!.backgroundColor!.resolve({}), scheme.error);
      expect(confirm.style!.foregroundColor!.resolve({}), scheme.onError);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await tester.tap(find.byType(SwitchListTile));
      await settle(tester);
      expect(recorder.enabled, false);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(Dialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'three real tabs, once-only notice and record management keep navigation',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final env = FixtureEnvironment();
      addTearDown(env.close);
      await tester.runAsync(() => recorder.ready);
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          overlayBuilder: (_, child) =>
              ReadingStatisticsScope(controller: recorder, child: child),
          homeBuilder: (_, _) => ReadingHome(
            repository: env.novels,
            library: env.library,
            sources: [env.source.descriptor],
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      expect(find.text('Reading statistics are on'), findsOneWidget);
      await tester.tap(find.text('Manage records').first);
      await settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('Reading statistics are on'), findsNothing);
      await tester.tap(find.byType(SwitchListTile));
      await settle(tester);
      expect(recorder.enabled, false);
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.tap(
        find.widgetWithText(NavigationDestination, 'Statistics'),
      );
      await settle(tester);
      expect(find.text('Recording is paused.'), findsWidgets);
      await tester.tap(find.text('Resume recording').first);
      await settle(tester);
      expect(recorder.enabled, true);
      await tester.tap(find.byTooltip('Manage records').first);
      await settle(tester);
      await tester.ensureVisible(find.text('Clear statistics').first);
      await tester.tap(find.text('Clear statistics').first);
      await settle(tester);
      expect(
        find.text('Reading after clearing will still be recorded.'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Clear statistics').last,
      );
      await settle(tester);
      expect(recorder.enabled, true);
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Bookshelf'));
      await settle(tester);
      expect(find.text('Reading statistics are on'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets('range, chart keyboard/semantics and clear reject a late query', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await recorder.ready;
      final key = NovelKey(sourceId: SourceId('s'), novelId: 'n');
      final session =
          (await repo.begin(key) as Success<ReadingRecordSession?>).value!;
      await repo.submit(ReadingCheckpoint(session, 1, {20261021: 90000}));
    });
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        homeBuilder: (_, _) =>
            Scaffold(body: StatisticsView(controller: recorder)),
      ),
    );
    await settle(tester);
    expect(periodDuration('1 min'), findsOneWidget);
    await tester.tap(find.text('30 days'));
    await settle(tester);
    expect(find.text('Sep 22 – Oct 21'), findsOneWidget);
    final chart = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.slider == true,
    );
    expect(
      tester
          .getSize(
            find
                .descendant(of: chart, matching: find.byType(GestureDetector))
                .first,
          )
          .width,
      greaterThan(200),
    );
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(chart).getSemanticsData().value,
      contains('1 min'),
    );
    final focus = find
        .descendant(of: chart, matching: find.byType(Focus))
        .first;
    tester.widget<Focus>(focus).focusNode?.requestFocus();
    Focus.of(
      tester.element(
        find
            .descendant(of: chart, matching: find.byType(GestureDetector))
            .first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      tester.getSemantics(chart).getSemanticsData().value,
      contains('0 min'),
    );
    await tester.pumpAndSettle();
    final frame = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('reading-chart-focus')),
    );
    final border = (frame.decoration as BoxDecoration).border! as Border;
    expect(
      border.top.color,
      Theme.of(tester.element(chart)).colorScheme.primary,
    );
    handle.dispose();
    final gate = repo.gate = Completer<void>();
    await tester.tap(find.text('12 months'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.runAsync(() => recorder.clear());
    repo.gate = null;
    gate.complete();
    await settle(tester);
    expect(periodDuration('1 min'), findsNothing);
    expect(periodDuration('0 min'), findsOneWidget);
    expect(find.text('Nov 2025 – Oct 2026'), findsOneWidget);
    (recorder.clock as TestReadingClock).wall = DateTime(2027, 1, 3, 12);
    await tester.tap(find.text('7 days'));
    await settle(tester);
    expect(find.text('Dec 28, 2026 – Jan 3, 2027'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
  testWidgets(
    'statistics covers use cache only and missing metadata stays associated',
    (tester) async {
      final images = CacheImages();
      await tester.runAsync(() async {
        await recorder.ready;
        final key = NovelKey(sourceId: SourceId('s'), novelId: 'n');
        await db
            .customStatement("INSERT INTO bookshelf VALUES('s','n',?,0,0)", [
              RecordCodec.summary(
                NovelSummary(
                  key: key,
                  title: 'A long book title in local metadata',
                  cover: MediaRef(
                    sourceId: key.sourceId,
                    mediaId: 'cached-cover',
                  ),
                ),
              ),
            ]);
        final session =
            (await repo.begin(key) as Success<ReadingRecordSession?>).value!;
        await repo.submit(ReadingCheckpoint(session, 1, {20261021: 1000}));
      });
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          homeBuilder: (_, _) => Scaffold(
            body: StatisticsView(controller: recorder, images: images),
          ),
        ),
      );
      await settle(tester);
      expect(images.modes, [ReadMode.cacheOnly]);
      expect(find.text('Removed books'), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
      await settle(tester);
      expect(find.text('A long book title in local metadata'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'unknown preference failure does not query repeatedly or show zero statistics',
    (tester) async {
      await tester.runAsync(() => recorder.ready);
      await tester.runAsync(() => recorder.close());
      recorder.dispose();
      final unavailable = UnavailableStatistics();
      recorder = ReadingStatisticsController(
        unavailable,
        clock: TestReadingClock(),
        schedule: false,
      );
      await recorder.ready;
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          homeBuilder: (_, _) =>
              Scaffold(body: StatisticsView(controller: recorder)),
        ),
      );
      await settle(tester);
      expect(unavailable.reads, 0);
      expect(
        find.text(
          'Reading statistics are temporarily unavailable. Please retry.',
        ),
        findsOneWidget,
      );
      expect(find.text('0 min'), findsNothing);
      unavailable.failing = false;
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(unavailable.reads, greaterThan(0));
      expect(periodDuration('0 min'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'notice stays visible until dismissed but is not shown again after remount',
    (tester) async {
      await tester.runAsync(() => recorder.ready);
      Widget page(Key key) => ShioriApp(
        locale: const Locale('en'),
        homeBuilder: (_, _) => Scaffold(
          body: StatisticsNotice(key: key, controller: recorder),
        ),
      );
      await tester.pumpWidget(page(const ValueKey(1)));
      await settle(tester);
      expect(find.text('Reading statistics are on'), findsOneWidget);
      expect(recorder.enabled, true);
      expect(recorder.settings!.noticeSeen, true);
      await tester.pumpWidget(page(const ValueKey(2)));
      await settle(tester);
      expect(find.text('Reading statistics are on'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
}
