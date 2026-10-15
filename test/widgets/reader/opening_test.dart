import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/continue_reading.dart';
import 'package:shiori/features/reader/reader_loading_page.dart';
import 'package:shiori/features/reader/reader_preferences.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/shared/widgets/state_views.dart';

class _FontMedia implements ImageRepository {
  final gate = Completer<Result<LoadResult<MediaLease>>>();

  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => Future.any([
    gate.future,
    cancellation.whenCancelled.then(
      (_) => Failure<LoadResult<MediaLease>>(
        AppFailure.cancelled(Operation.media),
      ),
    ),
  ]);
}

Future<void> _screenshot(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final directory = Platform.environment['SHIORI_OPENING_SCREENSHOTS'];
  if (directory == null) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void _loading(WidgetTester tester, Color paper) {
  expect(find.byType(LoadingView), findsOneWidget);
  final element = tester.element(find.byType(LoadingView));
  expect(Theme.of(element).scaffoldBackgroundColor, paper);
  final text = find.descendant(
    of: find.byType(LoadingView),
    matching: find.byType(Text),
  );
  final style = DefaultTextStyle.of(tester.element(text)).style;
  expect(style.fontSize, lessThan(24));
  expect(style.decoration, isNot(TextDecoration.underline));
  expect(tester.getCenter(find.byType(LoadingView)), const Offset(195, 422));
}

void main() {
  setUpAll(() async {
    final font = Platform.environment['SHIORI_OPENING_FONT'];
    if (font == null) return;
    final bytes = ByteData.sublistView(await File(font).readAsBytes());
    for (final family in [
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Microsoft YaHei UI',
      'serif',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    final icons = ByteData.sublistView(
      await File(
        '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes(),
    );
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
  });

  testWidgets(
    'continue, chapter failure, retry and ready keep warm paper; back cancels',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final env = FixtureEnvironment();
      addTearDown(env.close);
      await env.settings.save(
        ReaderSettings(paper: ReaderPaper.warm, controlsHintSeen: true),
        cancellation: CancellationSource().token,
      );
      final preferences = ReaderPreferences(env.settings);
      await preferences.ready;
      addTearDown(preferences.dispose);
      env.library.controls.delays[Operation.progressRead] = const Duration(
        seconds: 1,
      );
      env.source.controls.delays[Operation.chapter] = const Duration(
        seconds: 1,
      );
      env.source.controls.failNext(
        AppFailure(
          kind: FailureKind.network,
          operation: Operation.chapter,
          retryPolicy: RetryPolicy.manual,
        ),
      );
      final boundary = GlobalKey();
      late final AppRoutes routes;
      routes = AppRoutes(
        home: (context) => Scaffold(
          body: TextButton(
            onPressed: () => routes.open(
              context,
              ContinueDestination(
                fixtureNovelKey(FixtureScenario.shortChapter),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
        continueReader: (_, key) => ContinueReadingScreen(
          novel: key,
          repository: env.novels,
          library: env.library,
          settings: env.settings,
          preferences: preferences,
        ),
      );
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('zh'),
          routes: routes,
          overlayBuilder: (_, child) =>
              RepaintBoundary(key: boundary, child: child),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      _loading(tester, ShioriReaderPaper.warm);
      await _screenshot(tester, boundary, 'warm-continue');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(BookReaderScreen), findsOneWidget);
      _loading(tester, ShioriReaderPaper.warm);
      await _screenshot(tester, boundary, 'warm-chapter');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(FailureView), findsOneWidget);
      expect(
        Theme.of(
          tester.element(find.byType(FailureView)),
        ).scaffoldBackgroundColor,
        ShioriReaderPaper.warm,
      );
      await _screenshot(tester, boundary, 'warm-failure');
      await tester.tap(find.text('重试'));
      await tester.pump();
      _loading(tester, ShioriReaderPaper.warm);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(PagedReaderViewport), findsOneWidget);
      expect(find.byType(LoadingView), findsNothing);
      await _screenshot(tester, boundary, 'warm-ready');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      preferences.update(
        preferences.value.copyWith(themeMode: ReaderThemeMode.dark),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      _loading(tester, ShioriReaderPaper.night);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ContinueReadingScreen), findsNothing);
      expect(env.settings.controls.calls[Operation.settingsRead], 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'font wait preserves paper and anchor, reveal reduced=$reducedMotion',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reducedMotion);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final settings = FixtureSettingsStore();
        await settings.save(
          ReaderSettings(
            paper: ReaderPaper.warm,
            themeMode: reducedMotion
                ? ReaderThemeMode.dark
                : ReaderThemeMode.light,
            controlsHintSeen: true,
          ),
          cancellation: CancellationSource().token,
        );
        final preferences = ReaderPreferences(settings);
        await preferences.ready;
        addTearDown(preferences.dispose);
        final images = _FontMedia();
        final family = EmbeddedFontFamily([
          MediaRef(sourceId: SourceId('local'), mediaId: 'waiting-font'),
        ]);
        final content = ChapterContent(
          key: ChapterKey(
            novelKey: LocalBookIdentity.book('a' * 64),
            chapterId: 'opening',
          ),
          title: '合成正文 / Opening',
          blocks: List.generate(
            50,
            (i) => ParagraphBlock(
              text: '段落 $i ${'合成正文用于检查阅读位置。' * 8}',
              inlineStyles: [
                InlineTextStyle(start: 0, length: 2, fonts: [family]),
              ],
            ),
          ),
        );
        final position = ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks[25].blockKey,
          blockIndex: 25,
          blockFraction: 0,
          chapterFraction: .5,
        );
        final viewport = PagedReaderController();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('zh'),
            overlayBuilder: (_, child) =>
                RepaintBoundary(key: boundary, child: child),
            routes: AppRoutes(
              home: (_) => ReaderContentView(
                content: content,
                preferences: preferences,
                images: images,
                initialPosition: position,
                viewportController: viewport,
              ),
            ),
          ),
        );
        await tester.pump();
        _loading(
          tester,
          reducedMotion ? ShioriReaderPaper.night : ShioriReaderPaper.warm,
        );
        await _screenshot(tester, boundary, 'font-wait-$reducedMotion');
        images.gate.complete(
          Failure(
            AppFailure(kind: FailureKind.notFound, operation: Operation.media),
          ),
        );
        // The optional font falls back, then the real viewport restores underneath.
        for (
          var i = 0;
          i < 20 && find.byType(PagedReaderViewport).evaluate().isEmpty;
          i++
        ) {
          await tester.pump();
        }
        expect(find.byType(PagedReaderViewport), findsOneWidget);
        final state = tester.state(find.byType(PagedReaderViewport));
        for (
          var i = 0;
          i < 20 &&
              !tester
                  .widget<ReaderOpeningTransition>(
                    find.byType(ReaderOpeningTransition),
                  )
                  .ready
                  .value;
          i++
        ) {
          await tester.pump();
        }
        expect(
          tester
              .widget<ReaderOpeningTransition>(
                find.byType(ReaderOpeningTransition),
              )
              .ready
              .value,
          isTrue,
        );
        final restored = viewport.capture();
        expect(restored?.blockIndex, greaterThanOrEqualTo(24));
        expect(restored?.blockIndex, lessThanOrEqualTo(25));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        await _screenshot(tester, boundary, 'reveal-$reducedMotion');
        final mask = tester.renderObject<RenderAnimatedOpacity>(
          find.byType(AnimatedOpacity).last,
        );
        expect(
          mask.opacity.value,
          reducedMotion ? 0 : allOf(greaterThan(0), lessThan(1)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LoadingView), findsNothing);
        expect(tester.state(find.byType(PagedReaderViewport)), same(state));
        expect(viewport.capture(), restored);
        await _screenshot(tester, boundary, 'font-ready-$reducedMotion');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  for (final scene in [
    (TargetPlatform.android, const Size(320, 850), 1.5, ReaderThemeMode.light),
    (TargetPlatform.windows, const Size(1200, 900), 1.0, ReaderThemeMode.dark),
  ]) {
    testWidgets(
      'opening fits English and scaled text on ${scene.$1}',
      (tester) async {
        tester.view.physicalSize = scene.$2;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scene.$3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final env = FixtureEnvironment();
        addTearDown(env.close);
        await env.settings.save(
          ReaderSettings(
            paper: ReaderPaper.warm,
            themeMode: scene.$4,
            controlsHintSeen: true,
          ),
          cancellation: CancellationSource().token,
        );
        final preferences = ReaderPreferences(env.settings);
        await preferences.ready;
        addTearDown(preferences.dispose);
        env.source.controls.delays[Operation.chapter] = const Duration(
          seconds: 1,
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            overlayBuilder: (_, child) =>
                RepaintBoundary(key: boundary, child: child),
            routes: AppRoutes(
              home: (_) => BookReaderScreen(
                chapter: fixtureChapterKey(FixtureScenario.shortChapter),
                repository: env.novels,
                preferences: preferences,
              ),
            ),
          ),
        );
        expect(find.byType(LoadingView), findsOneWidget);
        await _screenshot(tester, boundary, '${scene.$1.name}-en-loading');
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.byType(LoadingView), findsNothing);
        expect(find.byType(PagedReaderViewport), findsOneWidget);
        await _screenshot(tester, boundary, '${scene.$1.name}-en-ready');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(scene.$1),
    );
  }
}
