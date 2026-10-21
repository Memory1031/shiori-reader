import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/reading_statistics_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/data/local/record_codec.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/statistics/reading_statistics_controller.dart';
import 'package:shiori/features/statistics/statistics_view.dart';
import 'package:shiori/shared/widgets/reading_statistics_scope.dart';
import '../domain/reading_statistics/reading_clock_test.dart'
    show TestReadingClock;

class DelayedStatistics extends LocalReadingStatisticsRepository {
  DelayedStatistics(super.db);
  Completer<void>? gate;
  int reads = 0;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<Result<ReadingStatisticsSnapshot>> read({
    required int firstDay,
    required int lastDay,
    required int today,
  }) async {
    reads++;
    final waiting = gate;
    final result = await super.read(
      firstDay: firstDay,
      lastDay: lastDay,
      today: today,
    );
    if (waiting != null) await waiting.future;
    return result;
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
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

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
      await tester.tap(find.text('Clear reading statistics'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
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
      await tester.ensureVisible(find.text('Clear reading statistics').first);
      await tester.tap(find.text('Clear reading statistics').first);
      await settle(tester);
      expect(
        find.text('Reading after clearing will still be recorded.'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(TextButton, 'Clear reading statistics').last,
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
    expect(find.text('1 min · Total'), findsOneWidget);
    await tester.tap(find.text('30 days'));
    await settle(tester);
    expect(
      find.textContaining(
        MaterialLocalizations.of(
          tester.element(find.byType(StatisticsView)),
        ).formatShortDate(DateTime(2026, 9, 22)),
      ),
      findsOneWidget,
    );
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
    handle.dispose();
    final gate = repo.gate = Completer<void>();
    await tester.tap(find.text('12 months'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.runAsync(() => recorder.clear());
    repo.gate = null;
    gate.complete();
    await settle(tester);
    expect(find.text('1 min · Total'), findsNothing);
    expect(find.text('0 min · Total'), findsOneWidget);
    expect(
      find.textContaining(
        MaterialLocalizations.of(
          tester.element(find.byType(StatisticsView)),
        ).formatShortDate(DateTime(2025, 11, 1)),
      ),
      findsOneWidget,
    );
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
      expect(find.text('0 min · Total'), findsOneWidget);
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
