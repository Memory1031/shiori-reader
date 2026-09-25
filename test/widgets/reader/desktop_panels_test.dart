import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_contents.dart';
import 'package:shiori/features/reader/reader_panel.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/settings_panel.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/shared/widgets/state_views.dart';

import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import '../../domain/reparse_position_test.dart' as book;
import '../local_reparse_test.dart' show ReparseStore;
import 'settings_test.dart' show Store;

const desktop = Size(1600, 1000);
final windows = TargetPlatformVariant.only(TargetPlatform.windows);

final panel = find.byKey(const ValueKey('reader-panel'));

/// The desktop tooltip names the shortcut.
const settingsTip = 'Reading settings (Ctrl+,)';

Finder inPanel(Finder finder) => find.descendant(of: panel, matching: finder);

/// Whether [node] sits inside the single widget [finder] finds.
bool within(Finder finder, FocusNode? node) {
  final target = finder.evaluate().single;
  final context = node?.context;
  if (context == null) return false;
  if (context == target) return true;
  var found = false;
  context.visitAncestorElements((element) {
    found = element == target;
    return !found;
  });
  return found;
}

ChapterContent chapter([String title = 'Desktop panels']) => ChapterContent(
  key: fixtureChapterKey(FixtureScenario.longChapter),
  title: title,
  blocks: [
    HeadingBlock(text: 'Opening', level: 1),
    for (var i = 0; i < 40; i++)
      ParagraphBlock(text: '$i ${'中文与 English desktop reading。' * 30}'),
    HeadingBlock(text: 'Middle', level: 1),
    for (var i = 40; i < 80; i++)
      ParagraphBlock(text: '$i ${'中文与 English desktop reading。' * 30}'),
  ],
);

class Harness {
  final pages = PagedReaderController();
  final store = Store()..value = ReaderSettings(controlsHintSeen: true);
  final generation = ValueNotifier(0);
  var picked = 0, refreshes = 0, nexts = 0, previous = 0;

  ReaderContentsLayer book(BuildContext context) => ReaderContentsLayer(
    label: 'Book',
    action: IconButton(
      tooltip: 'Refresh',
      onPressed: () => refreshes++,
      icon: const Icon(Icons.refresh),
    ),
    build: (context, done) => ListView(
      children: [
        ListTile(
          title: const Text('Volume chapter'),
          onTap: () {
            done();
            picked++;
          },
        ),
      ],
    ),
  );

  Widget app({BookTerminalState? completion, bool disableAnimations = false}) =>
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: ValueListenableBuilder<int>(
              valueListenable: generation,
              builder: (context, value, _) => ReaderContentView(
                key: ValueKey(value),
                content: chapter(),
                viewportController: pages,
                settings: store,
                completion: completion,
                actions: ReaderActions(
                  bookContents: book,
                  nextChapter: () => nexts++,
                  previousChapter: () => previous++,
                ),
              ),
            ),
          ),
        ),
      );
}

Future<Harness> pumpReader(
  WidgetTester tester, {
  Size size = desktop,
  BookTerminalState? completion,
  bool disableAnimations = false,
  bool chrome = true,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = Harness();
  addTearDown(harness.generation.dispose);
  await tester.pumpWidget(
    harness.app(completion: completion, disableAnimations: disableAnimations),
  );
  await tester.pumpAndSettle();
  if (chrome) await key(tester, LogicalKeyboardKey.f2);
  return harness;
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> wheel(WidgetTester tester, Offset position) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: position,
      scrollDelta: const Offset(0, 120),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The three entries: how to open them, and a spot on the page outside
/// the panel.
final entries = <(String, Finder, Offset)>[
  ('contents', find.byIcon(Icons.list), const Offset(1400, 400)),
  ('settings', find.byTooltip(settingsTip), const Offset(200, 400)),
  (
    'progress',
    find.textContaining(RegExp(r'^Chapter \d+%$')),
    const Offset(800, 200),
  ),
];

Future<void> open(WidgetTester tester, Finder control) async {
  await tester.tap(control);
  await tester.pumpAndSettle();
  expect(panel, findsOneWidget);
}

bool chromeVisible(WidgetTester tester) =>
    find.byTooltip(settingsTip).evaluate().isNotEmpty;

void main() {
  group('desktop reader panels', () {
    for (final (name, control, outside) in entries) {
      testWidgets('$name blocks page input and restores it after closing', (
        tester,
      ) async {
        final harness = await pumpReader(tester);
        final pages = harness.pages;
        final start = pages.capture()!;
        final viewport = find.byType(PagedReaderViewport);
        final viewportSize = tester.getSize(viewport);
        final columns = tester.widget<PagedReaderViewport>(viewport).columns;

        await open(tester, control);
        expect(find.byType(BottomSheet), findsNothing);
        // The page keeps its size and spread under the panel.
        expect(tester.getSize(viewport), viewportSize);
        expect(tester.widget<PagedReaderViewport>(viewport).columns, columns);

        for (final key in [
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.pageDown,
          LogicalKeyboardKey.pageUp,
          LogicalKeyboardKey.f2,
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }
        await wheel(tester, outside);
        expect(pages.capture(), start, reason: 'page input is blocked');
        expect(panel, findsOneWidget);

        // A click on the page closes the panel, and only closes it.
        await tester.tapAt(outside);
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(pages.capture(), start);
        expect(chromeVisible(tester), isTrue);

        await key(tester, LogicalKeyboardKey.arrowRight);
        expect(
          pages.capture()!.chapterFraction,
          greaterThan(start.chapterFraction),
          reason: 'reader focus returns after closing',
        );
        expect(tester.takeException(), isNull);
      }, variant: windows);
    }

    testWidgets('Space turns the page, but not under an open panel', (
      tester,
    ) async {
      final harness = await pumpReader(tester);
      final start = harness.pages.capture()!;
      await key(tester, LogicalKeyboardKey.space);
      final next = harness.pages.capture()!;
      expect(next.chapterFraction, greaterThan(start.chapterFraction));
      for (final (_, control, _) in entries) {
        await open(tester, control);
        await key(tester, LogicalKeyboardKey.space);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await key(tester, LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(harness.pages.capture(), next);
        expect(chromeVisible(tester), isTrue);
        await key(tester, LogicalKeyboardKey.escape);
        expect(panel, findsNothing);
      }
      // Closed, the page has focus again and Shift+Space turns back.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await key(tester, LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(harness.pages.capture(), start);
    }, variant: windows);

    for (final (name, control, _) in entries.take(2)) {
      testWidgets('$name traps keyboard traversal in a closed loop', (
        tester,
      ) async {
        await pumpReader(tester);
        final reader = find.byType(ReaderContentView);
        await open(tester, control);
        await key(tester, LogicalKeyboardKey.tab);
        final first = FocusManager.instance.primaryFocus;
        expect(within(panel, first), isTrue);
        final visited = <FocusNode?>[first];
        for (var i = 0; i < 100; i++) {
          await key(tester, LogicalKeyboardKey.tab);
          final focus = FocusManager.instance.primaryFocus;
          expect(within(panel, focus), isTrue);
          expect(within(reader, focus), isFalse);
          if (focus == first) break;
          visited.add(focus);
        }
        expect(
          FocusManager.instance.primaryFocus,
          first,
          reason: 'Tab from the last control wraps to the first',
        );
        expect(visited.length, greaterThan(1));
        final last = visited.last;

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await key(tester, LogicalKeyboardKey.tab);
        expect(
          FocusManager.instance.primaryFocus,
          last,
          reason: 'Shift+Tab from the first control wraps to the last',
        );
        for (var i = 0; i < visited.length; i++) {
          await key(tester, LogicalKeyboardKey.tab);
          expect(within(panel, FocusManager.instance.primaryFocus), isTrue);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(FocusManager.instance.primaryFocus, last);

        await key(tester, LogicalKeyboardKey.escape);
        expect(panel, findsNothing);
        expect(
          within(reader, FocusManager.instance.primaryFocus),
          isTrue,
          reason: 'focus goes back to the reader',
        );
      }, variant: windows);
    }

    testWidgets(
      'the page underneath leaves the semantics tree while a panel is open',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpReader(tester);
        // Searched in the live semantics tree, where blocked nodes drop out.
        final dismiss = find.semantics.byLabel('Dismiss');
        // Flutter keeps the barrier out of semantics on Windows and Linux;
        // there Esc and the panels' own controls close them.
        final barrierNode = defaultTargetPlatform == TargetPlatform.macOS;
        for (final (control, hidden) in [
          (find.byTooltip(settingsTip), 'Desktop panels'),
          (find.text('Chapter 0%'), 'Reading settings'),
        ]) {
          final page = find.semantics.byLabel(RegExp(hidden));
          expect(page, findsWidgets);
          expect(dismiss, findsNothing);
          await open(tester, control);
          final route = ModalRoute.of(tester.element(panel))!;
          expect(route.barrierLabel, 'Dismiss');
          expect(page, findsNothing);
          if (barrierNode) {
            expect(dismiss, findsOneWidget);
            tester.semantics.tap(dismiss);
          } else {
            expect(dismiss, findsNothing);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          }
          await tester.pumpAndSettle();
          expect(panel, findsNothing);
          expect(page, findsWidgets);
          expect(dismiss, findsNothing);
        }
        semantics.dispose();
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
      }),
    );

    for (final close in ['escape', 'close button', 'barrier']) {
      testWidgets('settings closed by $close flushes edits once', (
        tester,
      ) async {
        final harness = await pumpReader(tester);
        final store = harness.store;
        await open(tester, find.byTooltip(settingsTip));
        await tester.tap(inPanel(find.text('Warm paper')));
        await tester.pump(const Duration(milliseconds: 20));
        expect(store.writes, isEmpty, reason: 'still debouncing');
        switch (close) {
          case 'escape':
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          case 'close button':
            await tester.tap(inPanel(find.byTooltip('Close')));
          default:
            await tester.tapAt(const Offset(200, 400));
        }
        await tester.pump(const Duration(milliseconds: 20));
        expect(store.writes, hasLength(1), reason: 'flushed on close');
        expect(store.writes.single.paper, ReaderPaper.warm);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        expect(panel, findsNothing);
        expect(store.writes, hasLength(1));
      }, variant: windows);
    }

    testWidgets('settings panel follows live reading-theme edits', (
      tester,
    ) async {
      await pumpReader(tester);
      await open(tester, find.byTooltip(settingsTip));
      Material surface() =>
          tester.widget<Material>(inPanel(find.byType(Material)).first);
      ThemeData theme() =>
          Theme.of(tester.element(inPanel(find.text('Night'))));
      final light = surface().color;
      expect(light, theme().scaffoldBackgroundColor);
      await tester.tap(inPanel(find.text('Night')));
      await tester.pumpAndSettle();
      expect(theme().brightness, Brightness.dark);
      expect(surface().color, theme().colorScheme.surface);
      expect(surface().color, isNot(light));
      final title = tester.widget<Text>(inPanel(find.text('Reading settings')));
      final color =
          DefaultTextStyle.of(
            tester.element(inPanel(find.text('Reading settings'))),
          ).style.merge(title.style).color ??
          theme().textTheme.titleMedium!.color;
      expect(
        ThemeData.estimateBrightnessForColor(color!),
        Brightness.light,
        reason: 'text follows the night paper',
      );
      await key(tester, LogicalKeyboardKey.escape);
    }, variant: windows);

    testWidgets('side panels size to the window and keep the page in view', (
      tester,
    ) async {
      for (final (width, contents, settings) in [
        (1600.0, 360.0, 400.0),
        (1000.0, 320.0, 360.0),
        (840.0, 320.0, 360.0),
      ]) {
        expect(
          ReaderPanelRoute.sideWidth(ReaderPanelPlacement.start, width),
          contents,
        );
        expect(
          ReaderPanelRoute.sideWidth(ReaderPanelPlacement.end, width),
          settings,
        );
      }
      expect(ReaderPanelRoute.sideWidth(ReaderPanelPlacement.end, 440), 416);
      await pumpReader(tester, size: const Size(1000, 700));
      await open(tester, find.byIcon(Icons.list));
      expect(tester.getRect(panel), const Rect.fromLTWH(12, 12, 320, 676));
      await key(tester, LogicalKeyboardKey.escape);
      await open(tester, find.byTooltip(settingsTip));
      expect(tester.getRect(panel), const Rect.fromLTWH(628, 12, 360, 676));
      await key(tester, LogicalKeyboardKey.escape);
    }, variant: windows);

    testWidgets(
      'side panels slide and fade in, and appear at once with reduced motion',
      (tester) async {
        await pumpReader(tester);
        await tester.tap(find.byIcon(Icons.list));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final moving = tester.getRect(panel).left;
        expect(moving, lessThan(12));
        expect(moving, greaterThanOrEqualTo(12 - ReaderPanelRoute.slide));
        await tester.pumpAndSettle();
        expect(tester.getRect(panel).left, 12);
        await key(tester, LogicalKeyboardKey.escape);

        await tester.pumpWidget(const SizedBox());
        await pumpReader(tester, disableAnimations: true);
        await tester.tap(find.byIcon(Icons.list));
        await tester.pump();
        await tester.pump();
        expect(tester.getRect(panel).left, 12);
        final fade = tester.widget<FadeTransition>(
          find.ancestor(of: panel, matching: find.byType(FadeTransition)).first,
        );
        expect(fade.opacity.value, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(panel, findsNothing);
      },
      variant: windows,
    );

    testWidgets(
      'progress popover follows its control while the window resizes',
      (tester) async {
        final harness = await pumpReader(tester);
        final target = find.ancestor(
          of: find.text('Chapter 0%'),
          matching: find.byType(TextButton),
        );
        void expectAnchored() {
          final anchor = tester.getRect(target);
          final popover = tester.getRect(panel);
          expect(popover.center.dx, moreOrLessEquals(anchor.center.dx));
          expect(
            popover.bottom,
            moreOrLessEquals(anchor.top - ReaderPanelRoute.anchorGap),
          );
          expect(
            popover.width,
            ReaderPanelRoute.popoverWidth(tester.view.physicalSize.width),
          );
        }

        await open(tester, find.text('Chapter 0%'));
        expectAnchored();
        for (final size in [
          const Size(1000, 700),
          const Size(840, 600),
          const Size(2200, 1300),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(panel, findsOneWidget, reason: 'stays open across resize');
          expectAnchored();
        }

        // The scrubber seeks; the stepper closes the popover and steps.
        final start = harness.pages.capture()!;
        await tester.drag(inPanel(find.byType(Slider)), const Offset(120, 0));
        await tester.pumpAndSettle();
        expect(
          harness.pages.capture()!.chapterFraction,
          greaterThan(start.chapterFraction),
        );
        await tester.tap(inPanel(find.text('Next chapter')));
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(harness.nexts, 1);
      },
      variant: windows,
    );

    testWidgets('a mouse hovering the progress popover shows its tooltip', (
      tester,
    ) async {
      await pumpReader(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final button = find.ancestor(
        of: find.text('Chapter 0%'),
        matching: find.byType(TextButton),
      );
      await mouse.moveTo(tester.getCenter(button));
      await tester.pump();
      await mouse.down(tester.getCenter(button));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);

      // A tooltip lays out against the overlay, so the popover must not
      // sit under a layer whose transform is only known after layout.
      final tooltip = inPanel(find.byType(Tooltip)).first;
      final message = tester.widget<Tooltip>(tooltip).message!;
      await mouse.moveTo(tester.getCenter(tooltip));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(message), findsWidgets);

      // The popover keeps following its control with the tooltip up.
      tester.view.physicalSize = const Size(1000, 700);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(panel).bottom,
        moreOrLessEquals(
          tester.getRect(button).top - ReaderPanelRoute.anchorGap,
        ),
      );

      await mouse.moveTo(tester.getCenter(inPanel(find.byType(Slider))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, variant: windows);

    testWidgets('contents header ends with refresh and close in one row', (
      tester,
    ) async {
      final harness = await pumpReader(tester);
      await open(tester, find.byIcon(Icons.list));
      expect(inPanel(find.text('Contents')), findsOneWidget);
      await tester.tap(inPanel(find.text('Book')));
      await tester.pumpAndSettle();
      final title = tester.getCenter(inPanel(find.text('Contents')));
      final refresh = tester.getCenter(inPanel(find.byTooltip('Refresh')));
      final close = tester.getCenter(inPanel(find.byTooltip('Close')));
      expect(refresh.dy, moreOrLessEquals(title.dy, epsilon: 1));
      expect(close.dy, moreOrLessEquals(title.dy, epsilon: 1));
      expect(title.dx, lessThan(refresh.dx));
      expect(refresh.dx, lessThan(close.dx));
      await tester.tap(inPanel(find.byTooltip('Refresh')));
      expect(harness.refreshes, 1);

      await tester.tap(inPanel(find.byTooltip('Close')));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);

      // A selection closes the panel before it applies.
      await open(tester, find.byIcon(Icons.list));
      await tester.tap(inPanel(find.text('Middle')));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(harness.pages.capture()!.chapterFraction, greaterThan(.3));
      await open(tester, find.byIcon(Icons.list));
      await tester.tap(inPanel(find.text('Book')));
      await tester.pumpAndSettle();
      await tester.tap(inPanel(find.text('Volume chapter')));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(harness.picked, 1);
    }, variant: windows);

    testWidgets('completion contents open on the book layer', (tester) async {
      await pumpReader(
        tester,
        completion: BookTerminalState.finished,
        chrome: false,
      );
      await tester.tap(find.text('View contents'));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(inPanel(find.text('Volume chapter')), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      expect(panel, findsNothing);
    }, variant: windows);

    for (final (name, control, _) in entries) {
      testWidgets('a reader going away with $name open removes it cleanly', (
        tester,
      ) async {
        final harness = await pumpReader(tester);
        final navigator = Navigator.of(
          tester.element(find.byType(ReaderContentView)),
        );
        await open(tester, control);
        if (name == 'settings') {
          await tester.tap(inPanel(find.text('Warm paper')));
          await tester.pump();
        }
        // A chapter change replaces the view under the open panel.
        harness.generation.value++;
        await tester.pump();
        await tester.pump();
        expect(panel, findsNothing);
        expect(navigator.canPop(), isFalse);
        expect(tester.takeException(), isNull);
        if (name == 'settings') {
          await tester.pump(const Duration(milliseconds: 20));
          expect(
            harness.store.writes.single.paper,
            ReaderPaper.warm,
            reason: 'the preferences flush on their own dispose',
          );
        }

        // The new view opens panels as usual.
        await tester.pumpAndSettle();
        await key(tester, LogicalKeyboardKey.f2);
        await open(tester, control);
        // One already closing finishes its exit on its own.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        harness.generation.value++;
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(navigator.canPop(), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }, variant: windows);
    }

    testWidgets(
      'failure page contents open as a side panel in the app theme',
      (tester) async {
        tester.view
          ..physicalSize = desktop
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final env = FixtureEnvironment(
          scenario: FixtureScenario.deletedChapter,
        );
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (_) => BookReaderScreen(
                chapter: fixtureChapterKey(FixtureScenario.deletedChapter),
                repository: env.novels,
                library: env.library,
                settings: Store()
                  ..value = ReaderSettings(
                    controlsHintSeen: true,
                    themeMode: ReaderThemeMode.dark,
                  ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(FailureView), findsOneWidget);
        final app = Theme.of(tester.element(find.byType(FailureView)));
        final back = find.widgetWithText(TextButton, 'Back');
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(panel, findsOneWidget);
        expect(inPanel(find.byType(ReaderContentsPanel)), findsOneWidget);
        expect(
          tester.widget<Material>(inPanel(find.byType(Material)).first).color,
          app.scaffoldBackgroundColor,
        );
        expect(
          Theme.of(tester.element(find.byType(ReaderContentsPanel))).brightness,
          app.brightness,
        );
        await tester.tap(inPanel(find.byTooltip('Close')));
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(find.byType(FailureView), findsOneWidget);

        await tester.tapAt(tester.getCenter(back));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(1400, 500));
        await tester.pumpAndSettle();
        expect(panel, findsNothing);

        // Leaving with the panel open takes it down too.
        await tester.tap(back);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await env.close();
      },
      variant: windows,
    );

    testWidgets('failure page contents close when the book is invalidated', (
      tester,
    ) async {
      tester.view
        ..physicalSize = desktop
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = _CountingStore();
      addTearDown(store.events.close);
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              // Not in the book, so the chapter fails to load.
              chapter: LocalBookIdentity.chapter(book.key, 'missing'),
              repository: LocalReadingRepository(
                local: store,
                online: ForbiddenOnline(),
              ),
              library: FixtureLibraryRepository(),
              settings: Store()..value = ReaderSettings(controlsHintSeen: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FailureView), findsOneWidget);
      final back = find.widgetWithText(TextButton, 'Back');
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);

      // Keep the old panel's callbacks to act on after it is gone.
      final contents = tester.widget<ReaderContentsPanel>(
        inPanel(find.byType(ReaderContentsPanel)),
      );
      final row = tester.widget<InkWell>(
        find
            .ancestor(
              of: inPanel(find.text('Chapter 0')),
              matching: find.byType(InkWell),
            )
            .first,
      );
      final route = ModalRoute.of(
        tester.element(find.byType(ReaderContentsPanel)),
      )!;
      final reads = store.reads;

      store.events.add(book.key);
      await tester.pump();
      expect(find.byType(BookReaderScreen), findsOneWidget);
      expect(
        find.text(
          'This book is being reparsed. Return to the library and reopen it.',
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(route.isActive, isFalse);

      // The retired panel no longer acts on the reader.
      contents.onDone();
      row.onTap!();
      await tester.pumpAndSettle();
      expect(store.reads, reads);
      expect(panel, findsNothing);
      expect(find.byType(FailureView), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: windows);
  });

  testWidgets(
    'touch platforms keep the reader sheets',
    (tester) async {
      await pumpReader(tester, size: const Size(800, 1200), chrome: false);
      await tester.tapAt(tester.getCenter(find.byType(PagedReaderViewport)));
      await tester.pumpAndSettle();
      for (final control in [
        find.byIcon(Icons.list),
        find.byTooltip('Reading settings'),
        find.text('Chapter 0%'),
      ]) {
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(panel, findsNothing);
        expect(find.byTooltip('Close'), findsNothing);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();
      }
      expect(find.byType(ReaderSettingsPanel), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

class _CountingStore extends ReparseStore {
  int reads = 0;

  @override
  Future<Result<LocalBookRecord?>> read(
    NovelKey key, {
    required CancellationToken cancellation,
  }) {
    reads++;
    return super.read(key, cancellation: cancellation);
  }
}
