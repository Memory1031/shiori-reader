import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/app_controller.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/import/import_overlay.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_authored_colors.dart'
    show readerColorContrast;
import '../features/import/import_progress_test.dart'
    as imports
    show Harness, cleanup;
import 'reader/local_search_test.dart' show fonts;
import 'reader/search_highlight_test.dart' show screenshot;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/bookshelf/book_batch_views.dart';
import 'package:shiori/shared/widgets/shiori_feedback.dart';
import 'desktop_shell_test.dart' show ShellHarness;

Finder get card => find
    .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
    .first;

class FeedbackHarness {
  int underlayClicks = 0;
  final navigator = GlobalKey<NavigatorState>(),
      messenger = GlobalKey<ScaffoldMessengerState>(),
      boundary = GlobalKey();
  late BuildContext page;
  late MediaQueryData homeMedia, window;
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(900, 720),
    double scale = 1,
    bool reduceMotion = true,
    AppThemeMode theme = AppThemeMode.light,
    AppAccent accent = AppAccent.teal,
    Widget Function(BuildContext)? home,
    Widget Function(Widget)? overlay,
  }) async {
    await fonts(tester);
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ShioriApp(
          navigatorKey: navigator,
          scaffoldMessengerKey: messenger,
          locale: const Locale('en'),
          createController: () =>
              AppController()
                ..settings = AppSettings(themeMode: theme, accent: accent),
          overlayBuilder: (context, child) {
            window = MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduceMotion,
            );
            return MediaQuery(
              data: window,
              child: overlay?.call(child) ?? child,
            );
          },
          homeBuilder: (context, _) {
            homeMedia = MediaQuery.of(context);
            return home?.call(context) ??
                Scaffold(
                  body: Builder(
                    builder: (context) {
                      page = context;
                      return Stack(
                        children: [
                          const Center(
                            child: TextField(
                              decoration: InputDecoration(
                                labelText: 'Book title',
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            bottom: 0,
                            child: TextButton(
                              onPressed: () => underlayClicks++,
                              child: const Text('Underlying action'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> feedbackScreenshot(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (Platform.environment['SHIORI_RETURN_SCREENSHOTS'] == null) return;
  final oldShadows = debugDisableShadows;
  void repaint(RenderObject node) {
    node.markNeedsPaint();
    node.visitChildren(repaint);
  }

  try {
    debugDisableShadows = false;
    repaint(boundary.currentContext!.findRenderObject()!);
    await tester.pump();
    await screenshot(tester, boundary, name);
  } finally {
    debugDisableShadows = oldShadows;
    repaint(boundary.currentContext!.findRenderObject()!);
    await tester.pump();
  }
}

void record(String name, Rect rect, Size window) {
  final directory = Platform.environment['SHIORI_RETURN_SCREENSHOTS'];
  if (directory == null) return;
  final data = jsonEncode({
    'name': name,
    'window': [window.width, window.height],
    'card': [rect.left, rect.top, rect.right, rect.bottom],
    'expectedCenterX': window.width / 2,
  });
  File(
    '$directory/geometry.jsonl',
  ).writeAsStringSync('$data\n', mode: FileMode.append);
}

void main() {
  testWidgets(
    'one full-window host survives shell and root navigation',
    (tester) async {
      await fonts(tester);
      final h = ShellHarness(tester);
      await h.pump(size: const Size(1440, 900), onShelf: true);
      final source = tester.element(find.byType(BookshelfView));
      ShioriFeedback.show(
        source,
        message: 'Saved',
        kind: ShioriFeedbackKind.success,
      );
      await tester.pumpAndSettle();
      final host = tester.state(find.byType(ShioriFeedbackHost));
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      for (final width in [1440.0, 900.0, 390.0]) {
        await h.resize(width, 900);
        expect(find.byType(SnackBar, skipOffstage: false), findsOneWidget);
        expect(
          tester.state<ScaffoldState>(find.byType(Scaffold).first),
          same(scaffold),
        );
        expect(tester.getRect(card).center.dx, closeTo(width / 2, .1));
        expect(tester.getRect(card).width, lessThanOrEqualTo(480));
        record('shell-$width', tester.getRect(card), Size(width, 900));
        expect(tester.state(find.byType(ShioriFeedbackHost)), same(host));
      }
      await h.resize(1440, 900);
      await h.search();
      await h.openResult();
      expect(tester.state(find.byType(ShioriFeedbackHost)), same(host));
      h.root.push(
        MaterialPageRoute<void>(
          builder: (_) => BookReaderScreen(
            chapter: fixtureChapterKey(FixtureScenario.multiVolume),
            repository: h.env.novels,
            library: h.env.library,
            settings: h.env.settings,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(card).center.dx, closeTo(720, .1));
      expect(find.byType(SnackBar), findsOneWidget);
      h.root.pop();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ShioriFeedbackHost)), same(host));
      await h.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'feedback does not intercept a root sheet confirmation',
    (tester) async {
      await fonts(tester);
      final h = ShellHarness(tester);
      await h.pump(size: const Size(390, 844), onShelf: true);
      final source = tester.element(find.byType(BookshelfView));
      var retried = 0, confirmed = 0;
      ShioriFeedback.show(
        source,
        message: 'Unable to save',
        kind: ShioriFeedbackKind.error,
        actionLabel: 'Retry',
        onAction: () => retried++,
      );
      await tester.pumpAndSettle();
      h.root.push(
        bookBatchRoute<void>(
          source,
          (context) => BookBatchPanel(
            title: 'Remove book?',
            content: const Text('The book will be removed.'),
            actions: [
              BookBatchAction('Cancel', () => Navigator.pop(context)),
              BookBatchAction('Confirm', () {
                confirmed++;
                Navigator.pop(context);
              }, primary: true),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
      expect(retried, 0);
      expect(find.text('Unable to save'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(retried, 1);
      expect(tester.takeException(), isNull);
      await h.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'FIFO retains independent errors and coalesces repeated passive notices',
    (tester) async {
      final h = FeedbackHarness();
      await h.pump(tester);
      final semantics = tester.ensureSemantics();
      try {
        var retries = 0;
        ShioriFeedback.show(
          h.page,
          message: 'First failure',
          kind: ShioriFeedbackKind.error,
          actionLabel: 'Retry',
          onAction: () {
            retries++;
            showDialog<void>(
              context: h.navigator.currentContext!,
              builder: (context) => AlertDialog(
                title: const Text('Retry requested'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        );
        for (var i = 0; i < 30; i++) {
          ShioriFeedback.show(
            h.page,
            message: 'Copied',
            kind: ShioriFeedbackKind.success,
          );
        }
        ShioriFeedback.show(
          h.page,
          message: 'Second failure',
          kind: ShioriFeedbackKind.error,
        );
        await tester.pumpAndSettle();
        expect(find.text('First failure'), findsOneWidget);
        await tester.tap(find.text('Underlying action'));
        await tester.pump();
        expect(h.underlayClicks, 1);
        expect(
          tester
              .widgetList<Semantics>(
                find.descendant(
                  of: find.byType(SnackBar),
                  matching: find.byType(Semantics),
                ),
              )
              .any((w) => w.properties.liveRegion == true),
          isTrue,
        );
        expect(find.text('Copied'), findsNothing);
        await tester.pump(const Duration(seconds: 8));
        expect(find.text('Retry'), findsOneWidget);
        Focus.of(tester.element(find.text('Retry'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(retries, 1);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Copied'), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(find.text('Second failure'), findsOneWidget);
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'navigator-context update action and route-owned retry expire independently',
    (tester) async {
      final h = FeedbackHarness();
      await h.pump(tester);
      var opened = 0, staleRetries = 0;
      ShioriFeedback.show(
        h.navigator.currentContext!,
        message: 'Update available',
        actionLabel: 'View',
        onAction: () {
          opened++;
          h.navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Updates')),
            ),
          );
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text('Updates'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      late BuildContext temporary;
      h.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (context) {
            temporary = context;
            return const Scaffold(body: Text('Temporary page'));
          },
        ),
      );
      await tester.pumpAndSettle();
      ShioriFeedback.show(
        temporary,
        message: 'Old request',
        kind: ShioriFeedbackKind.error,
        actionLabel: 'Retry',
        onAction: () => staleRetries++,
      );
      ShioriFeedback.show(
        h.navigator.currentContext!,
        message: 'Save acknowledgement failed',
        kind: ShioriFeedbackKind.error,
      );
      await tester.pumpAndSettle();
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Save acknowledgement failed'), findsOneWidget);
      expect(staleRetries, 0);
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Save acknowledgement failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone card clears safe area and keyboard without changing child window metrics',
    (tester) async {
      final h = FeedbackHarness();
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
      await h.pump(tester, size: const Size(390, 844), scale: 2);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final focus = FocusManager.instance.primaryFocus;
      const message =
          'The reading position could not be saved. Keep this book open and retry when storage is available.';
      ShioriFeedback.show(
        h.page,
        message: message,
        kind: ShioriFeedbackKind.error,
        actionLabel: 'Retry',
        onAction: () {},
      );
      await tester.pumpAndSettle();
      final host = tester.state(find.byType(ShioriFeedbackHost));
      expect(h.homeMedia, h.window);
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(tester.getRect(card).left, greaterThanOrEqualTo(16));
      expect(tester.getRect(card).right, lessThanOrEqualTo(374));
      expect(tester.getRect(card).bottom, lessThanOrEqualTo(844 - 34 - 16));
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(h.homeMedia, h.window);
      expect(h.homeMedia.viewInsets.bottom, 300);
      expect(h.homeMedia.viewPadding.bottom, 34);
      final rect = tester.getRect(card);
      expect(rect.top, greaterThanOrEqualTo(24));
      expect(rect.bottom, lessThanOrEqualTo(844 - 300 - 16));
      expect(tester.state(find.byType(ShioriFeedbackHost)), same(host));
      record('phone-keyboard-large-text', rect, const Size(390, 844));
      await feedbackScreenshot(tester, h.boundary, 'phone-keyboard-large-text');
      tester.view.physicalSize = const Size(844, 390);
      tester.view.padding = const FakeViewPadding(left: 44, right: 44);
      tester.view.viewPadding = const FakeViewPadding(
        left: 44,
        right: 44,
        bottom: 21,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      expect(h.homeMedia, h.window);
      expect(tester.getRect(card).left, greaterThanOrEqualTo(44 + 16));
      expect(tester.getRect(card).right, lessThanOrEqualTo(844 - 44 - 16));
      expect(tester.getRect(card).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(card).bottom, lessThanOrEqualTo(390 - 180 - 16));
      expect(find.text('Retry').hitTestable(), findsOneWidget);
      record(
        'phone-landscape-keyboard',
        tester.getRect(card),
        const Size(844, 390),
      );
      await feedbackScreenshot(tester, h.boundary, 'phone-landscape-keyboard');
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(message),
      );
      expect(paragraph.maxLines, 2);
      expect(paragraph.overflow, TextOverflow.ellipsis);
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(Scrollbar),
        ),
        findsNothing,
      );
      final icon = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byIcon(Icons.error_outline),
      );
      expect(
        tester.getCenter(icon).dy,
        closeTo(tester.getCenter(find.text(message)).dy, .1),
      );
      final semantics = tester.ensureSemantics();
      try {
        expect(tester.getSemantics(find.text(message)).label, message);
      } finally {
        semantics.dispose();
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('feedback motion follows the current reduced-motion preference', (
    tester,
  ) async {
    final h = FeedbackHarness();
    await h.pump(tester);
    ShioriFeedback.show(h.page, message: 'Reduced motion');
    await tester.pump();
    final fade = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, 1);
    h.messenger.currentState!.removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await h.pump(tester, reduceMotion: false);
    ShioriFeedback.show(h.page, message: 'Normal motion');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final progress = tester.widget<FadeTransition>(fade.first).opacity.value;
    expect(progress, greaterThan(0));
    expect(progress, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real import popup takes priority and retains pending failure until dismissed',
    (tester) async {
      final h = FeedbackHarness(), importing = imports.Harness();
      imports.cleanup(tester, importing);
      // The production ImportOverlay owns a PopupRoute on this same root Navigator.
      await h.pump(
        tester,
        overlay: (child) => ImportOverlay(
          controller: importing.controller,
          navigatorKey: h.navigator,
          child: child,
        ),
      );
      ShioriFeedback.show(
        h.page,
        message: 'Import feedback waiting',
        kind: ShioriFeedbackKind.error,
      );
      await tester.pumpAndSettle();
      importing.source.stage('Book');
      await importing.controller.start();
      importing.controller.open();
      await tester.pumpAndSettle();
      expect(importing.controller.interactionOpen, isTrue);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Import feedback waiting'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in [
    (
      name: 'desktop-day',
      size: const Size(1440, 900),
      theme: AppThemeMode.light,
      accent: AppAccent.teal,
      scale: 1.0,
    ),
    (
      name: 'desktop-night',
      size: const Size(900, 720),
      theme: AppThemeMode.dark,
      accent: AppAccent.softPink,
      scale: 1.0,
    ),
    (
      name: 'phone-long-english',
      size: const Size(390, 844),
      theme: AppThemeMode.light,
      accent: AppAccent.blueGrey,
      scale: 2.0,
    ),
  ]) {
    testWidgets(
      'rendered feedback ${scenario.name}',
      (tester) async {
        await fonts(tester);
        final h = FeedbackHarness(), env = FixtureEnvironment();
        addTearDown(env.close);
        await h.pump(
          tester,
          size: scenario.size,
          theme: scenario.theme,
          accent: scenario.accent,
          scale: scenario.scale,
          home: (_) => ReadingHome(
            repository: env.novels,
            library: env.library,
            sources: [env.source.descriptor],
            onAppearance: () {},
          ),
        );
        final context = h.navigator.currentContext!;
        ShioriFeedback.show(
          context,
          message: scenario.scale > 1
              ? 'The reading position could not be saved. Keep this book open and retry when storage is available.'
              : 'The reading position could not be saved.',
          kind: ShioriFeedbackKind.error,
          actionLabel: 'Retry',
          onAction: () {},
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(card),
            material = tester.widget<Material>(card);
        final colors = Theme.of(context).colorScheme;
        expect(rect.center.dx, closeTo(scenario.size.width / 2, .1));
        expect(material.color, colors.surface);
        expect(
          readerColorContrast(colors.onSurface, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          readerColorContrast(colors.primary, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          readerColorContrast(colors.error, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(find.text('Retry').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        record(scenario.name, rect, scenario.size);
        await feedbackScreenshot(tester, h.boundary, scenario.name);
      },
      variant: TargetPlatformVariant.only(
        scenario.name.startsWith('phone')
            ? TargetPlatform.iOS
            : TargetPlatform.windows,
      ),
    );
  }
}
