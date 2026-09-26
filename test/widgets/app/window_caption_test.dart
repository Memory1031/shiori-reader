import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/app_controller.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/app/theme.dart';
import 'package:shiori/app/window_caption.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/reader/reader_panel.dart';
import 'package:shiori/features/reader/reader_image_preview.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/shared/widgets/state_views.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/settings_panel.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/shared/capabilities.dart';

import '../reader/settings_test.dart' show Store;
import '../reader/completion_test.dart' show CompletionRepository;
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import '../../domain/reparse_position_test.dart' as book;
import '../local_reparse_test.dart' show ReparseStore;

const night = (color: Color(0xff101010), brightness: Brightness.dark);
const warm = (color: Color(0xffffeedd), brightness: Brightness.light);

class _CountingSettings extends Store {
  int loads = 0;
  @override
  Future<Result<ReaderSettings>> load({
    required CancellationToken cancellation,
  }) {
    loads++;
    return super.load(cancellation: cancellation);
  }
}

class _DelayedChapterRepository extends CompletionRepository {
  final gate = Completer<Result<LoadResult<ChapterContent>>>();
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => key == keys[1]
      ? gate.future
      : super.loadChapter(key, mode: mode, cancellation: cancellation);
}

CaptionAppearance appLook(Brightness brightness) {
  final theme = appTheme(brightness);
  return (color: theme.scaffoldBackgroundColor, brightness: brightness);
}

CaptionAppearance readerLook(ReaderSettings settings) {
  final theme = readerTheme(settings, Brightness.light);
  return (color: theme.scaffoldBackgroundColor, brightness: theme.brightness);
}

class Harness {
  final key = GlobalKey<NavigatorState>();
  final app = AppController();
  final sent = <CaptionAppearance>[];
  final appearance = ValueNotifier<CaptionAppearance?>(night);
  NavigatorState get nav => key.currentState!;

  Widget build({CaptionSender? sender}) => ShioriApp(
    navigatorKey: key,
    createController: () => app,
    captionSender:
        sender ??
        (value) async {
          sent.add(value);
        },
    locale: const Locale('en'),
    routes: AppRoutes(home: (_) => const Scaffold(body: Text('Shelf'))),
  );

  Route<void> reader() => platformPageRoute<void>(
    nav.context,
    builder: (_) => ValueListenableBuilder<CaptionAppearance?>(
      valueListenable: appearance,
      builder: (_, value, child) => WindowCaptionScope(
        enabled: value != null,
        appearance: value,
        child: child!,
      ),
      child: const Scaffold(body: Text('Reader')),
    ),
  );

  Route<void> page(String name) => platformPageRoute<void>(
    nav.context,
    settings: RouteSettings(name: name),
    builder: (_) => Scaffold(body: Text(name)),
  );
}

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'visible BookReader keeps caption during delayed chapter (failure=$fail)',
      (tester) async {
        final h = Harness();
        final repository = _DelayedChapterRepository();
        final settings = Store()
          ..value = ReaderSettings(
            themeMode: ReaderThemeMode.dark,
            controlsHintSeen: true,
          );
        await tester.pumpWidget(h.build());
        await tester.pumpAndSettle();
        h.nav.push(
          platformPageRoute<void>(
            h.nav.context,
            builder: (_) => BookReaderScreen(
              chapter: repository.keys.first,
              repository: repository,
              settings: settings,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final oldState = tester.state(find.byType(ReaderContentView));
        final oldAppearance = h.sent.last;
        final count = h.sent.length;
        tester
            .widget<ReaderContentView>(find.byType(ReaderContentView))
            .actions
            .nextChapter!();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        final waiting = tester.widget<ReaderContentView>(
          find.byType(ReaderContentView),
        );
        expect(waiting.content.key, repository.keys.first);
        expect(waiting.active, isFalse);
        expect(waiting.appearanceActive, isTrue);
        expect(tester.state(find.byType(ReaderContentView)), same(oldState));
        expect(h.sent.skip(count), isEmpty);
        if (fail) {
          repository.gate.complete(
            Failure(
              AppFailure(
                kind: FailureKind.network,
                operation: Operation.chapter,
                retryPolicy: RetryPolicy.manual,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final restored = tester.widget<ReaderContentView>(
            find.byType(ReaderContentView),
          );
          expect(restored.content.key, repository.keys.first);
          expect(restored.active, isTrue);
          expect(tester.state(find.byType(ReaderContentView)), same(oldState));
          expect(h.sent.skip(count), isEmpty);
        } else {
          // The pending session loads a different paper; it cannot claim that
          // appearance until BookReader commits it after layout/transition.
          settings.value = ReaderSettings(
            paper: ReaderPaper.warm,
            controlsHintSeen: true,
          );
          repository.gate.complete(
            repository.result(repository.content(repository.keys[1])),
          );
          await tester.pump();
          await tester.pump();
          final pages = tester.widgetList<ReaderContentView>(
            find.byType(ReaderContentView),
          );
          expect(pages.length, 2);
          expect(
            pages
                .singleWhere((p) => p.content.key == repository.keys[1])
                .appearanceActive,
            isFalse,
          );
          expect(h.sent.last, oldAppearance);
          expect(h.sent.skip(count), isEmpty);
          await tester.pumpAndSettle();
          final current = tester.widget<ReaderContentView>(
            find.byType(ReaderContentView),
          );
          expect(current.content.key, repository.keys[1]);
          expect(current.appearanceActive, isTrue);
          expect(h.sent.skip(count), [readerLook(settings.value)]);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await repository.updates.close();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'image preview declares true black and restores the live reader',
    (tester) async {
      final h = Harness();
      final env = FixtureEnvironment(scenario: FixtureScenario.singleImage);
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();
      h.nav.push(h.reader());
      await tester.pumpAndSettle();
      final block = const FixtureData()
          .content(FixtureScenario.singleImage)
          .blocks
          .whereType<ImageBlock>()
          .first;
      showReaderImagePreview(
        tester.element(find.text('Reader')),
        block: block,
        repository: env.images,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.sent.last, (color: Colors.black, brightness: Brightness.dark));
      h.appearance.value = warm;
      await tester.pump();
      expect(h.sent.last.color, Colors.black);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.sent.last, warm);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
  );

  testWidgets('active local reader invalidation returns to app appearance', (
    tester,
  ) async {
    final h = Harness();
    final local = ReparseStore();
    final library = FixtureLibraryRepository();
    await tester.pumpWidget(h.build());
    await tester.pumpAndSettle();
    h.nav.push(
      platformPageRoute<void>(
        h.nav.context,
        builder: (_) => BookReaderScreen(
          chapter: local.content.chapters.first.key,
          repository: LocalReadingRepository(
            local: local,
            online: ForbiddenOnline(),
          ),
          library: library,
          settings: Store()
            ..value = ReaderSettings(
              themeMode: ReaderThemeMode.dark,
              controlsHintSeen: true,
            ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReaderContentView), findsOneWidget);
    expect(h.sent.last.brightness, Brightness.dark);
    local.events.add(book.key);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderContentView), findsNothing);
    expect(h.sent.last, appLook(Brightness.light));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await local.events.close();
    await library.close();
  });

  testWidgets(
    'loading and failure do not load reader preferences or borrow another reader',
    (tester) async {
      final h = Harness();
      final env = FixtureEnvironment(scenario: FixtureScenario.deletedChapter);
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();
      h.nav.push(h.reader());
      await tester.pumpAndSettle();
      final store = _CountingSettings()
        ..value = ReaderSettings(themeMode: ReaderThemeMode.dark);
      h.nav.push(
        platformPageRoute<void>(
          h.nav.context,
          builder: (_) => BookReaderScreen(
            chapter: fixtureChapterKey(FixtureScenario.deletedChapter),
            repository: env.novels,
            settings: store,
          ),
        ),
      );
      await tester.pump();
      expect(h.sent.last, appLook(Brightness.light));
      await tester.pumpAndSettle();
      expect(find.byType(FailureView), findsOneWidget);
      expect(h.sent.last, appLook(Brightness.light));
      expect(store.writes, isEmpty);
      expect(store.loads, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
  );

  for (final appBrightness in Brightness.values) {
    testWidgets('reader restores $appBrightness app appearance', (
      tester,
    ) async {
      final h = Harness();
      h.app.setAppearance(
        appBrightness == Brightness.light
            ? AppThemeMode.light
            : AppThemeMode.dark,
      );
      h.appearance.value = appBrightness == Brightness.light ? night : warm;
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();
      expect(h.sent.last, appLook(appBrightness));
      h.nav.push(h.reader());
      await tester.pumpAndSettle();
      expect(h.sent.last, h.appearance.value);
      h.nav.pop();
      await tester.pumpAndSettle();
      expect(h.sent.last, appLook(appBrightness));
    });
  }

  testWidgets('unclaimed routes inherit; explicit popup appearance wins', (
    tester,
  ) async {
    final h = Harness();
    await tester.pumpWidget(h.build());
    await tester.pumpAndSettle();
    h.nav.push(h.reader());
    await tester.pumpAndSettle();
    final calls = h.sent.length;
    // Inheritance is independent of PopupRoute: a transparent page can inherit.
    h.nav.push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, _, _) => const SizedBox(),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.sent.length, calls);
    h.nav.pop();
    await tester.pumpAndSettle();
    for (final name in [
      'contents',
      'settings',
      'progress',
      'notes',
      'footnote',
    ]) {
      h.nav.push(
        ReaderPanelRoute<void>(
          placement: ReaderPanelPlacement.center,
          barrierLabel: name,
          duration: Duration.zero,
          builder: (_) => const SizedBox(height: 100),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.sent.length, calls, reason: name);
      h.nav.pop();
      await tester.pumpAndSettle();
    }
    h.nav.push(
      ReaderPanelRoute<void>(
        placement: ReaderPanelPlacement.center,
        barrierLabel: 'explicit',
        duration: Duration.zero,
        builder: (_) => const WindowCaptionScope(
          appearance: warm,
          child: SizedBox(height: 100),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.sent.last, warm);
    h.nav.pop();
    await tester.pumpAndSettle();
    expect(h.sent.last, night);
  });

  testWidgets(
    'detail/cache use live default; nested reader restores live owner',
    (tester) async {
      final h = Harness();
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();
      h.nav.push(h.reader());
      await tester.pumpAndSettle();
      for (final name in ['Detail', 'Cache']) {
        h.nav.push(h.page(name));
        await tester.pumpAndSettle();
        h.appearance.value = warm;
        h.app.setAppearance(AppThemeMode.dark);
        await tester.pumpAndSettle();
        expect(h.sent.last, appLook(Brightness.dark));
        h.nav.pop();
        await tester.pumpAndSettle();
        expect(h.sent.last, warm);
        h.app.setAppearance(AppThemeMode.light);
        await tester.pumpAndSettle();
        expect(h.sent.last, warm);
      }
      h.nav.push(
        platformPageRoute<void>(
          h.nav.context,
          builder: (_) =>
              const WindowCaptionScope(appearance: night, child: Scaffold()),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.sent.last, night);
      h.appearance.value = (color: Colors.blue, brightness: Brightness.light);
      await tester.pumpAndSettle();
      expect(h.sent.last, night);
      h.nav.pop();
      await tester.pumpAndSettle();
      expect(h.sent.last, h.appearance.value);
      h.appearance.value = null;
      await tester.pumpAndSettle();
      expect(h.sent.last, appLook(Brightness.light));
    },
  );

  testWidgets(
    'replace/remove and delayed disposal cannot restore retired colors',
    (tester) async {
      final h = Harness();
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();
      final old = h.reader();
      h.nav.push(old);
      await tester.pumpAndSettle();
      h.nav.push(h.page('Detail'));
      await tester.pumpAndSettle();
      h.nav.removeRoute(old);
      h.appearance.value = warm;
      await tester.pumpAndSettle();
      expect(h.sent.last, appLook(Brightness.light));
      final active = h.reader();
      h.nav.pushReplacement(active);
      await tester.pumpAndSettle();
      expect(h.sent.last, warm);
      h.nav.replace(oldRoute: active, newRoute: h.page('Cache'));
      await tester.pumpAndSettle();
      expect(h.sent.last, appLook(Brightness.light));
      h.nav.push(h.reader());
      h.nav.pop();
      await tester.pumpAndSettle();
      expect(h.sent.last, appLook(Brightness.light));
    },
  );

  testWidgets(
    'serial sender coalesces frames and keeps only latest pending color',
    (tester) async {
      final h = Harness();
      final gates = <Completer<void>>[];
      await tester.pumpWidget(
        h.build(
          sender: (value) {
            h.sent.add(value);
            final gate = Completer<void>();
            gates.add(gate);
            return gate.future;
          },
        ),
      );
      await tester.pumpAndSettle();
      h.nav.push(h.reader());
      await tester.pumpAndSettle();
      h.appearance.value = warm;
      await tester.pumpAndSettle();
      h.appearance.value = night;
      h.appearance.value = warm;
      await tester.pumpAndSettle();
      expect(h.sent, [appLook(Brightness.light)]);
      gates.first.complete();
      await tester.pump();
      expect(h.sent, [appLook(Brightness.light), warm]);
      h.nav.pop();
      await tester.pumpAndSettle();
      gates.last.complete();
      await tester.pump();
      expect(h.sent.last, appLook(Brightness.light));
      gates.last.complete();
      await tester.pumpAndSettle();
      expect(h.sent.length, 3);
    },
  );

  testWidgets(
    'native channel serializes ARGB and tolerates unsupported runner',
    (tester) async {
      const channel = MethodChannel('dev.shiori.reader/app');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        throw PlatformException(code: 'unsupported');
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final controller = WindowCaptionController();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [controller],
          builder: (_, child) =>
              WindowCaptionSync(controller: controller, child: child!),
          home: const WindowCaptionScope(appearance: night, child: Scaffold()),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.single.method, 'setCaption');
      expect(calls.single.arguments, {
        'color': night.color.toARGB32(),
        'dark': true,
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'real reader settings/completion update caption without remount or page-turn sends',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = Harness();
      final store = Store()..value = ReaderSettings(controlsHintSeen: true);
      final completed = ValueNotifier(false);
      final active = ValueNotifier(true);
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();
      h.nav.push(
        platformPageRoute<void>(
          h.nav.context,
          builder: (_) => ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, enabled, _) => ValueListenableBuilder<bool>(
              valueListenable: completed,
              builder: (_, done, _) => ReaderContentView(
                active: enabled,
                settings: store,
                content: const FixtureData().content(
                  FixtureScenario.longChapter,
                ),
                completion: done ? BookTerminalState.finished : null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(ReaderContentView));
      final viewport = tester.state(find.byType(PagedReaderViewport));
      final count = h.sent.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(h.sent.length, count);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reading settings (Ctrl+,)'));
      await tester.pumpAndSettle();
      final preferences = tester
          .widget<ReaderSettingsPanel>(find.byType(ReaderSettingsPanel))
          .preferences;
      for (final value in [
        store.value.copyWith(paper: ReaderPaper.warm),
        store.value.copyWith(themeMode: ReaderThemeMode.dark),
      ]) {
        preferences.update(value);
        await tester.pumpAndSettle();
        expect(h.sent.last, readerLook(value));
        expect(tester.state(find.byType(ReaderContentView)), same(state));
        expect(tester.state(find.byType(PagedReaderViewport)), same(viewport));
      }
      h.nav.pop();
      await tester.pumpAndSettle();
      completed.value = true;
      await tester.pumpAndSettle();
      expect(h.sent.last.brightness, Brightness.dark);
      active.value = false;
      await tester.pumpAndSettle();
      expect(h.sent.last, appLook(Brightness.light));
      active.value = true;
      await tester.pumpAndSettle();
      expect(h.sent.last.brightness, Brightness.dark);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
