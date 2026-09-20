import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/app_controller.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/settings_panel.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/paper_turn.dart';
import 'package:shiori/features/reader/viewport/reader_viewport.dart';
import '../../support/reader_actions.dart';
import 'settings_test.dart' show Store;

Widget app(Store store, {AppController? controller}) => ShioriApp(
  createController: () => controller ?? AppController(),
  locale: const Locale('en'),
  routes: AppRoutes(
    home: (_) => ReaderContentView(
      settings: store,
      content: const FixtureData().content(FixtureScenario.extremeParagraph),
    ),
  ),
);

void main() {
  testWidgets(
    'legacy scroll preference has no scrolling viewport or mode selector',
    (tester) async {
      final store = Store()
        ..value = ReaderSettings(
          mode: ReaderMode.scroll,
          controlsHintSeen: true,
        );
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      expect(find.byType(PagedReaderViewport), findsOneWidget);
      expect(find.byType(ReaderViewport), findsNothing);
      await openReaderSettings(tester);
      await tester.pumpAndSettle();
      expect(find.text('Scroll'), findsNothing);
      expect(find.text('Paged'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'paper fold spans the full reader with safe-area content coordinates',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      addTearDown(tester.view.reset);
      final store = Store()..value = ReaderSettings(controlsHintSeen: true);
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      expect(viewport.pageSize, const Size(390, 844));
      expect(viewport.contentOrigin, const Offset(30, 100));
      expect(tester.getSize(find.byType(PaperTurnFold)), const Size(390, 844));
      final next = viewport.controller.next();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final fold = tester.widget<PaperTurnFold>(find.byType(PaperTurnFold));
      expect(fold.progress, greaterThan(0));
      final clip = tester
          .widgetList<ClipPath>(find.byType(ClipPath))
          .map((w) => w.clipper)
          .whereType<PaperTurnClipper>()
          .single;
      expect(clip.pageSize, const Size(390, 844));
      expect(clip.contentOrigin, const Offset(30, 100));
      expect(clip.progress, fold.progress);
      await tester.pumpAndSettle();
      await next;
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [ReaderMode.paged]) {
    testWidgets(
      'progress sheet seeks and center restores fully hidden chrome: $mode',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = Store()
          ..value = ReaderSettings(mode: mode, controlsHintSeen: true);
        await tester.pumpWidget(app(store));
        await tester.pumpAndSettle();
        expect(find.byType(IconButton), findsNothing);
        await tester.tapAt(tester.getCenter(find.byType(ReaderContentView)));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Chapter '));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(Slider), const Offset(140, 0));
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(Slider))).pop();
        await tester.pumpAndSettle();
        final position = mode == ReaderMode.paged
            ? tester
                  .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
                  .controller
                  .capture()!
            : tester
                  .widget<ReaderViewport>(find.byType(ReaderViewport))
                  .controller
                  .capture()!;
        expect(position.chapterFraction, greaterThan(.25));
        await tester.tapAt(tester.getCenter(find.byType(ReaderContentView)));
        await tester.pumpAndSettle();
        expect(find.byType(IconButton), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'reduced motion removes sheet transition without moving the reading anchor',
    (tester) async {
      final store = Store()..value = ReaderSettings(controlsHintSeen: true);
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: ReaderContentView(
                settings: store,
                content: const FixtureData().content(
                  FixtureScenario.shortChapter,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      final anchor = viewport.controller.capture();
      await openReaderSettings(tester);
      expect(
        ModalRoute.of(
          tester.element(find.byType(ReaderSettingsPanel)),
        )!.transitionDuration,
        Duration.zero,
      );
      expect(viewport.controller.capture(), anchor);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  test(
    'v1/v2 migrate to v3 paper without changing typography or theme; v3 round trips',
    () {
      final current = ReaderSettings(
        fontSize: 28,
        mode: ReaderMode.scroll,
        themeMode: ReaderThemeMode.dark,
        horizontalPadding: 44,
        lineHeight: 2,
        paragraphSpacing: 22,
        paper: ReaderPaper.warm,
        controlsHintSeen: true,
      );
      for (final version in [1, 2]) {
        final old = current.toJson()..['schemaVersion'] = version;
        old.remove('paper');
        old.remove('controlsHintSeen');
        if (version == 1) old.remove('mode');
        final migrated = ReaderSettings.fromJson(old);
        expect(
          migrated,
          current.copyWith(
            paper: ReaderPaper.paper,
            controlsHintSeen: false,
            mode: version == 1 ? ReaderMode.paged : ReaderMode.scroll,
          ),
        );
      }
      expect(ReaderSettings.fromJson(current.toJson()), current);
      expect(
        () =>
            ReaderSettings.fromJson(current.toJson()..['schemaVersion'] = 999),
        throwsFormatException,
      );
    },
  );

  test('all three reading palettes meet text contrast', () {
    for (final settings in [
      ReaderSettings(),
      ReaderSettings(paper: ReaderPaper.warm),
      ReaderSettings(themeMode: ReaderThemeMode.dark),
    ]) {
      final theme = readerTheme(settings, Brightness.light);
      final background = theme.scaffoldBackgroundColor.computeLuminance();
      for (final ink in [
        theme.colorScheme.onSurface,
        theme.colorScheme.onSurfaceVariant,
      ]) {
        final text = ink.computeLuminance();
        final ratio =
            (background > text ? background + .05 : text + .05) /
            (background > text ? text + .05 : background + .05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    }
  });

  test('bottom sheets adopt the reading paper in every palette', () {
    for (final settings in [
      ReaderSettings(),
      ReaderSettings(paper: ReaderPaper.warm),
      ReaderSettings(themeMode: ReaderThemeMode.dark),
    ]) {
      final theme = readerTheme(settings, Brightness.light);
      expect(
        theme.bottomSheetTheme.backgroundColor,
        theme.scaffoldBackgroundColor,
      );
      expect(
        theme.bottomSheetTheme.dragHandleColor,
        theme.colorScheme.onSurfaceVariant,
      );
    }
  });

  testWidgets(
    'app dark does not force reader dark; paper/system selection and width preserve anchor',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = Store()..value = ReaderSettings(controlsHintSeen: true);
      final controller = AppController()
        ..settings = AppSettings(themeMode: AppThemeMode.dark);
      await tester.pumpWidget(app(store, controller: controller));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PagedReaderViewport)).width, 680);
      expect(
        Theme.of(tester.element(find.byType(PagedReaderViewport))).brightness,
        Brightness.light,
      );
      expect(find.text('Scroll'), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      viewport.controller.restore(
        ReaderPosition(
          contentRevision: viewport.content.contentRevision,
          blockKey: viewport.content.blocks.first.blockKey,
          blockIndex: 0,
          blockFraction: .61,
          chapterFraction: .61,
        ),
      );
      await tester.pumpAndSettle();
      await openReaderSettings(tester);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Warm paper'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Warm paper'));
      await tester.pumpAndSettle();
      expect(store.value.paper, ReaderPaper.warm);
      expect(controller.settings.themeMode, AppThemeMode.dark);
      expect(viewport.controller.capture()!.blockFraction, closeTo(.61, .001));
      final system = find.byType(SwitchListTile);
      await tester.ensureVisible(system);
      await tester.tap(system);
      await tester.pumpAndSettle();
      expect(store.value.themeMode, ReaderThemeMode.system);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Night'))
            .selected,
        isTrue,
      );
      expect(
        Theme.of(tester.element(find.byType(PagedReaderViewport))).brightness,
        Brightness.dark,
      );
      Navigator.of(tester.element(find.byType(ReaderSettingsPanel))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(store.value.paper, ReaderPaper.warm);
    },
  );

  testWidgets(
    'large first-use hint can be dismissed and stays dismissed after reopening',
    (tester) async {
      tester.view.physicalSize = const Size(320, 400);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = Store();
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Got it'));
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(store.value.controlsHintSeen, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      expect(find.text('Got it'), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'hidden chrome supports keyboard and exposes failed settings save',
    (tester) async {
      final store = Store()..value = ReaderSettings(controlsHintSeen: true);
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      final before = viewport.controller.capture()!;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        viewport.controller.capture()!.blockFraction,
        greaterThan(before.blockFraction),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reading settings'), findsOneWidget);
      await openReaderSettings(tester);
      store.fail = true;
      tester
          .widget<ReaderSettingsPanel>(find.byType(ReaderSettingsPanel))
          .preferences
          .update(store.value.copyWith(fontSize: 26));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      Navigator.of(tester.element(find.byType(ReaderSettingsPanel))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide reading controls'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.sync_problem), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
