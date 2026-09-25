import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_commands.dart';
import 'package:shiori/features/reader/reader_contents.dart';
import 'package:shiori/features/reader/reader_panel.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/settings_panel.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/shared/widgets/shiori_menu.dart';

import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import '../../domain/reparse_position_test.dart' as book;
import '../local_reparse_test.dart' show ReparseStore;
import 'desktop_panels_test.dart'
    show chapter, inPanel, key, panel, settingsTip;
import 'settings_test.dart' show Store;

final windows = TargetPlatformVariant.only(TargetPlatform.windows);
final android = TargetPlatformVariant.only(TargetPlatform.android);

const unsaved = 'Reading progress not saved. Tap to retry.';

/// A reader page on its own, with every command it can offer.
class Reader {
  final pages = PagedReaderController();
  final store = Store()..value = ReaderSettings(controlsHintSeen: true);
  final generation = ValueNotifier(0);
  final active = ValueNotifier(true);
  var links = 0, details = 0;

  Widget app({BookTerminalState? completion, double textScale = 1}) =>
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: ListenableBuilder(
              listenable: Listenable.merge([generation, active]),
              builder: (context, _) => ReaderContentView(
                key: ValueKey(generation.value),
                content: chapter(),
                viewportController: pages,
                settings: store,
                completion: completion,
                active: active.value,
                actions: ReaderActions(
                  bookContents: (context) => ReaderContentsLayer(
                    label: 'Book',
                    build: (context, done) => ListView(
                      children: [
                        ListTile(
                          title: const Text('Volume chapter'),
                          onTap: done,
                        ),
                      ],
                    ),
                  ),
                  links: (_) => links++,
                  details: () => details++,
                  completionPrevious: () {},
                  nextChapter: () {},
                  previousChapter: () {},
                ),
              ),
            ),
          ),
        ),
      );

  double get fraction => pages.capture()!.chapterFraction;
}

Future<Reader> pumpReader(
  WidgetTester tester, {
  Size size = const Size(1600, 1000),
  BookTerminalState? completion,
  double textScale = 1,
  bool chrome = false,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final reader = Reader();
  addTearDown(reader.generation.dispose);
  addTearDown(reader.active.dispose);
  await tester.pumpWidget(
    reader.app(completion: completion, textScale: textScale),
  );
  await tester.pumpAndSettle();
  if (chrome) await key(tester, LogicalKeyboardKey.f2);
  return reader;
}

/// [key] with modifiers held; without waiting for frames when [settle] is
/// false.
Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
  bool settle = true,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (settle) await tester.pumpAndSettle();
}

/// Presses [key], holds it for a few repeats and lets go.
Future<void> hold(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.sendKeyRepeatEvent(key);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

Future<void> rightClick(WidgetTester tester, Offset at) async {
  await tester.tapAt(
    at,
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

final menuItems = find.byType(ShioriMenuItem<ReaderCommand>);

Finder menuItem(String label) =>
    find.descendant(of: menuItems, matching: find.text(label));

List<String> menuLabels(WidgetTester tester) => [
  for (final item in tester.widgetList<ShioriMenuItem<ReaderCommand>>(
    menuItems,
  ))
    item.label,
];

Future<void> choose(WidgetTester tester, String label) async {
  await tester.tap(menuItem(label));
  await tester.pumpAndSettle();
}

bool chromeVisible() => find.byTooltip(settingsTip).evaluate().isNotEmpty;

final progressLabel = find.textContaining(RegExp(r'^Chapter \d+%$'));

final progressButton = find.ancestor(
  of: progressLabel,
  matching: find.byType(TextButton),
);

// TextButton.icon builds a private subtype.
final contentsButton = find.ancestor(
  of: find.byIcon(Icons.list),
  matching: find.byWidgetPredicate((widget) => widget is TextButton),
);

final contentsPanel = inPanel(find.byType(ReaderContentsPanel));
final progressPanel = inPanel(find.byType(Slider));
final settingsPanel = inPanel(find.byType(ReaderSettingsPanel));

void expectAnchored(WidgetTester tester) {
  expect(progressPanel, findsOneWidget);
  expect(
    tester.getRect(panel).bottom,
    moreOrLessEquals(
      tester.getRect(progressButton).top - ReaderPanelRoute.anchorGap,
    ),
  );
}

/// A [BookReaderScreen] pushed over a home page, as the app opens it.
class Book {
  Book(this.tester, {this.scenario = FixtureScenario.longChapter});
  final WidgetTester tester;
  final FixtureScenario scenario;
  late final env = FixtureEnvironment(scenario: scenario);
  final navigator = GlobalKey<NavigatorState>();
  var details = 0;

  Future<void> pump() async {
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        navigatorKey: navigator,
        routes: AppRoutes(home: (_) => const Scaffold(body: Text('home'))),
      ),
    );
    open();
    await tester.pumpAndSettle();
  }

  void open({int linkDepth = 0}) => navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => BookReaderScreen(
        chapter: fixtureChapterKey(scenario),
        repository: env.novels,
        library: env.library,
        settings: Store()..value = ReaderSettings(controlsHintSeen: true),
        linkDepth: linkDepth,
        onDetails: linkDepth > 0
            ? null
            : (_, _) async {
                details++;
              },
      ),
    ),
  );

  Finder get readers => find.byType(BookReaderScreen, skipOffstage: false);

  ChapterKey get showing => tester
      .widget<ReaderContentView>(find.byType(ReaderContentView).last)
      .content
      .key;

  Future<(int, String, double)?> saved() async {
    final result = await env.library.getProgress(
      fixtureNovelKey(scenario),
      cancellation: CancellationSource().token,
    );
    final position = (result as Success<ReadingProgress?>).value?.position;
    if (position == null) return null;
    return (position.blockIndex, position.blockKey, position.blockFraction);
  }

  void failWrites(int count) {
    for (var i = 0; i < count; i++) {
      env.library.controls.failNext(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.progressWrite,
        ),
      );
    }
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await env.close();
  }
}

void main() {
  group('one command, every input', () {
    testWidgets('buttons, shortcuts and the context menu open the same '
        'panels, and the tooltips name the shortcuts', (tester) async {
      await pumpReader(tester, chrome: true);
      expect(find.byTooltip(RegExp(r' \(Ctrl\+T\)$')), findsOneWidget);
      expect(find.byTooltip('Progress (Ctrl+G)'), findsOneWidget);
      expect(find.byTooltip(settingsTip), findsOneWidget);

      for (final (button, shortcut, label, opened) in [
        (contentsButton, LogicalKeyboardKey.keyT, 'Contents', contentsPanel),
        (progressButton, LogicalKeyboardKey.keyG, 'Progress', progressPanel),
        (
          find.byTooltip(settingsTip),
          LogicalKeyboardKey.comma,
          'Reading settings',
          settingsPanel,
        ),
      ]) {
        for (final input in ['button', 'shortcut', 'context menu']) {
          switch (input) {
            case 'button':
              await tester.tap(button);
              await tester.pumpAndSettle();
            case 'shortcut':
              await chord(tester, shortcut, control: true);
            default:
              await rightClick(tester, const Offset(800, 500));
              await choose(tester, label);
          }
          expect(opened, findsOneWidget, reason: '$label from $input');
          if (label == 'Progress') expectAnchored(tester);
          await key(tester, LogicalKeyboardKey.escape);
          expect(panel, findsNothing);
          expect(chromeVisible(), isTrue, reason: 'Esc only closes the panel');
        }
      }
      expect(tester.takeException(), isNull);
    }, variant: windows);

    testWidgets('the overflow menu runs the same commands, and Esc closes '
        'only the menu', (tester) async {
      final reader = await pumpReader(tester, chrome: true);
      Future<void> more() async {
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
      }

      await more();
      expect(menuLabels(tester), [
        'Chapter notes',
        'Novel details',
        'Hide reading controls',
      ]);
      await choose(tester, 'Chapter notes');
      expect(reader.links, 1);
      await more();
      await choose(tester, 'Novel details');
      expect(reader.details, 1);
      await more();
      await choose(tester, 'Hide reading controls');
      expect(chromeVisible(), isFalse);

      await key(tester, LogicalKeyboardKey.f2);
      await more();
      await key(tester, LogicalKeyboardKey.escape);
      expect(menuItems, findsNothing);
      expect(chromeVisible(), isTrue);
    }, variant: windows);

    testWidgets('a held shortcut opens its panel once', (tester) async {
      await pumpReader(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await hold(tester, LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(panel, findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      expect(panel, findsNothing);
      final navigator = Navigator.of(
        tester.element(find.byType(ReaderContentView)),
      );
      expect(navigator.canPop(), isFalse);
    }, variant: windows);
  });

  group('Space and focused controls', () {
    testWidgets('on a focused button Space presses it and the arrows still '
        'turn', (tester) async {
      final reader = await pumpReader(tester, chrome: true);
      final button = Focus.of(tester.element(find.text('Aa')));
      button.requestFocus();
      await tester.pump();

      var last = reader.fraction;
      for (final turn in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.pageDown,
      ]) {
        await key(tester, turn);
        expect(reader.fraction, greaterThan(last), reason: '$turn');
        last = reader.fraction;
      }
      expect(FocusManager.instance.primaryFocus, button);

      // Shift+Space neither turns nor presses the button.
      await chord(tester, LogicalKeyboardKey.space, shift: true);
      expect(reader.fraction, last);
      expect(panel, findsNothing);

      await key(tester, LogicalKeyboardKey.space);
      expect(settingsPanel, findsOneWidget);
      expect(reader.fraction, last);
      await key(tester, LogicalKeyboardKey.escape);
      expect(panel, findsNothing);
      expect(reader.fraction, last);

      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(reader.fraction, lessThan(last));
    }, variant: windows);

    testWidgets('on the page Space and Shift+Space turn', (tester) async {
      final reader = await pumpReader(tester, chrome: true);
      final start = reader.fraction;
      await key(tester, LogicalKeyboardKey.space);
      expect(reader.fraction, greaterThan(start));
      await chord(tester, LogicalKeyboardKey.space, shift: true);
      expect(reader.fraction, start);
      expect(panel, findsNothing);
    }, variant: windows);
  });

  group('context menu', () {
    testWidgets('a right click opens the menu and never turns or toggles', (
      tester,
    ) async {
      final reader = await pumpReader(tester);
      final start = reader.fraction;
      // Left, middle and right: the zones a primary click turns or toggles.
      for (final x in [100.0, 800.0, 1500.0]) {
        await rightClick(tester, Offset(x, 500));
        expect(menuLabels(tester), [
          'Contents',
          'Progress',
          'Reading settings',
          'Chapter notes',
          'Novel details',
          'Show reading controls',
        ]);
        final item = tester.getTopLeft(menuItems.first);
        expect(item.dx, inInclusiveRange(x - 320, x + 24), reason: 'at $x');
        expect(item.dy, inInclusiveRange(500 - 320, 500 + 24), reason: 'at $x');
        await key(tester, LogicalKeyboardKey.escape);
        expect(menuItems, findsNothing);
        expect(reader.fraction, start, reason: 'at $x');
        expect(chromeVisible(), isFalse, reason: 'at $x');
      }
      await rightClick(tester, const Offset(800, 500));
      await choose(tester, 'Show reading controls');
      expect(chromeVisible(), isTrue);
      await rightClick(tester, const Offset(800, 500));
      expect(menuItem('Hide reading controls'), findsOneWidget);
      await choose(tester, 'Chapter notes');
      expect(reader.links, 1);
      await rightClick(tester, const Offset(800, 500));
      await choose(tester, 'Novel details');
      expect(reader.details, 1);
      expect(reader.fraction, start);
      expect(chromeVisible(), isTrue);
    }, variant: windows);

    for (final (name, shift) in [('Menu key', false), ('Shift+F10', true)]) {
      testWidgets('the $name opens the menu in the middle of the page', (
        tester,
      ) async {
        await pumpReader(tester);
        await chord(
          tester,
          shift ? LogicalKeyboardKey.f10 : LogicalKeyboardKey.contextMenu,
          shift: shift,
        );
        expect(menuItems, findsNWidgets(6));
        final item = tester.getTopLeft(menuItems.first);
        expect(item.dx, inInclusiveRange(800, 824));
        expect(item.dy, inInclusiveRange(500, 524));
        await choose(tester, 'Progress');
        expectAnchored(tester);
        await key(tester, LogicalKeyboardKey.escape);
      }, variant: windows);
    }

    testWidgets('a choice made after the page is replaced does nothing', (
      tester,
    ) async {
      final reader = await pumpReader(tester);
      await rightClick(tester, const Offset(800, 500));
      reader.generation.value++;
      await tester.pump();
      await choose(tester, 'Reading settings');
      expect(panel, findsNothing);
      expect(tester.takeException(), isNull);
      // The new page has its own menu.
      await rightClick(tester, const Offset(800, 500));
      await choose(tester, 'Reading settings');
      expect(settingsPanel, findsOneWidget);
    }, variant: windows);
  });

  testWidgets('the completion page offers contents and settings but no '
      'progress or toolbars', (tester) async {
    await pumpReader(tester, completion: BookTerminalState.finished);
    await rightClick(tester, const Offset(800, 500));
    expect(menuLabels(tester), [
      'Contents',
      'Reading settings',
      'Novel details',
    ]);
    await key(tester, LogicalKeyboardKey.escape);

    await chord(tester, LogicalKeyboardKey.keyG, control: true);
    await key(tester, LogicalKeyboardKey.f2);
    expect(panel, findsNothing);
    expect(chromeVisible(), isFalse);

    await chord(tester, LogicalKeyboardKey.keyT, control: true);
    expect(inPanel(find.text('Volume chapter')), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    await chord(tester, LogicalKeyboardKey.comma, control: true);
    expect(settingsPanel, findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    expect(tester.takeException(), isNull);
  }, variant: windows);

  group('progress from the keyboard', () {
    testWidgets('shows the toolbars and opens over its control', (
      tester,
    ) async {
      await pumpReader(tester);
      expect(chromeVisible(), isFalse);
      await chord(tester, LogicalKeyboardKey.keyG, control: true);
      expect(chromeVisible(), isTrue);
      expectAnchored(tester);
      await key(tester, LogicalKeyboardKey.escape);
      // With the toolbars shown it opens at once.
      await chord(tester, LogicalKeyboardKey.keyG, control: true);
      expectAnchored(tester);
    }, variant: windows);

    for (final cancel in [
      'chapter change',
      'inactive page',
      'hidden toolbars',
      'covering route',
    ]) {
      testWidgets('a request still waiting is dropped on $cancel', (
        tester,
      ) async {
        final reader = await pumpReader(tester);
        await chord(
          tester,
          LogicalKeyboardKey.keyG,
          control: true,
          settle: false,
        );
        switch (cancel) {
          case 'chapter change':
            reader.generation.value++;
          case 'inactive page':
            reader.active.value = false;
          case 'hidden toolbars':
            await chord(tester, LogicalKeyboardKey.f2, settle: false);
          default:
            showDialog<void>(
              context: tester.element(find.byType(ReaderContentView)),
              builder: (_) => const AlertDialog(content: Text('covering')),
            );
        }
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        if (cancel == 'covering route') {
          Navigator.of(tester.element(find.text('covering'))).pop();
          await tester.pumpAndSettle();
          expect(panel, findsNothing);
        }
        expect(tester.takeException(), isNull);
      }, variant: windows);
    }

    testWidgets('an inactive page takes no commands', (tester) async {
      final reader = await pumpReader(tester);
      final start = reader.fraction;
      reader.active.value = false;
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowRight);
      await chord(tester, LogicalKeyboardKey.keyT, control: true);
      await rightClick(tester, const Offset(800, 500));
      expect(reader.fraction, start);
      expect(panel, findsNothing);
      expect(menuItems, findsNothing);
      // Active again, it takes focus back and the keys work.
      reader.active.value = true;
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(reader.fraction, greaterThan(start));
    }, variant: windows);

    testWidgets('a request still waiting is dropped when the book is '
        'invalidated', (tester) async {
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = ReparseStore();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: LocalBookIdentity.chapter(book.key, '0'),
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
      expect(find.byType(ReaderContentView), findsOneWidget);
      await chord(
        tester,
        LogicalKeyboardKey.keyG,
        control: true,
        settle: false,
      );
      store.events.add(book.key);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(
        find.text(
          'This book is being reparsed. Return to the library and reopen it.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }, variant: windows);
  });

  group('Esc in the book reader', () {
    testWidgets('hides the toolbars, then leaves; held, it takes one step', (
      tester,
    ) async {
      final b = Book(tester);
      await b.pump();
      await key(tester, LogicalKeyboardKey.f2);
      expect(chromeVisible(), isTrue);
      await hold(tester, LogicalKeyboardKey.escape);
      expect(chromeVisible(), isFalse);
      expect(b.readers, findsOneWidget);
      await hold(tester, LogicalKeyboardKey.escape);
      expect(b.readers, findsNothing);
      expect(find.text('home'), findsOneWidget);
      await b.close();
    }, variant: windows);

    testWidgets('closes only an open menu or panel', (tester) async {
      final b = Book(tester);
      await b.pump();
      await key(tester, LogicalKeyboardKey.f2);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      expect(menuItems, findsNothing);
      expect(chromeVisible(), isTrue);
      await chord(tester, LogicalKeyboardKey.comma, control: true);
      expect(settingsPanel, findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      expect(panel, findsNothing);
      expect(chromeVisible(), isTrue);
      await rightClick(tester, const Offset(800, 500));
      expect(menuItems, findsWidgets);
      await key(tester, LogicalKeyboardKey.escape);
      expect(menuItems, findsNothing);
      expect(chromeVisible(), isTrue);
      expect(b.readers, findsOneWidget);
      await b.close();
    }, variant: windows);

    testWidgets('leaving directly keeps the page being read, and a failed '
        'last save is reported underneath', (tester) async {
      final b = Book(tester);
      await b.pump();
      for (var i = 0; i < 3; i++) {
        await key(tester, LogicalKeyboardKey.arrowRight);
      }
      await tester.pump(const Duration(seconds: 1));
      final read = await b.saved();
      expect(read!.$1, greaterThan(0));
      await key(tester, LogicalKeyboardKey.escape);
      expect(b.readers, findsNothing);
      expect(await b.saved(), read);
      expect(find.text(unsaved), findsNothing);

      // The page turned to is still waiting to be written when Esc leaves,
      // and that write fails.
      b.open();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      b.failWrites(3);
      await key(tester, LogicalKeyboardKey.escape);
      expect(b.readers, findsNothing);
      expect(find.text(unsaved), findsOneWidget);
      await b.close();
    }, variant: windows);

    testWidgets('with progress known unsaved it saves first and stays when '
        'that fails', (tester) async {
      final b = Book(tester);
      await b.pump();
      b.failWrites(20);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      expect(b.readers, findsOneWidget);
      expect(find.text(unsaved), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
      await b.close();
    }, variant: windows);

    testWidgets('a linked reader takes the shortcuts and Esc returns to the '
        'reader it came from', (tester) async {
      final b = Book(tester, scenario: FixtureScenario.multiVolume);
      await b.pump();
      final origin = tester.element(find.byType(BookReaderScreen));
      b.open(linkDepth: 1);
      await tester.pumpAndSettle();
      expect(b.readers, findsNWidgets(2));

      await chord(tester, LogicalKeyboardKey.keyT, control: true);
      expect(contentsPanel, findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      await chord(tester, LogicalKeyboardKey.keyG, control: true);
      expectAnchored(tester);
      await key(tester, LogicalKeyboardKey.escape);
      await rightClick(tester, const Offset(800, 500));
      expect(menuItems, findsWidgets);
      expect(menuItem('Novel details'), findsNothing);
      await key(tester, LogicalKeyboardKey.escape);

      // Toolbars first, then back to the origin; held, no further.
      await hold(tester, LogicalKeyboardKey.escape);
      expect(b.readers, findsNWidgets(2));
      await hold(tester, LogicalKeyboardKey.escape);
      expect(b.readers, findsOneWidget);
      expect(tester.element(find.byType(BookReaderScreen)), same(origin));
      expect(b.details, 0);
      await b.close();
    }, variant: windows);

    testWidgets('page keys keep working across chapter changes', (
      tester,
    ) async {
      final b = Book(tester, scenario: FixtureScenario.multiVolume);
      await b.pump();
      final first = b.showing;
      for (var i = 0; i < 60 && b.showing == first; i++) {
        await key(tester, LogicalKeyboardKey.pageDown);
      }
      final second = b.showing;
      expect(second, isNot(first));
      // From the first page of the new chapter, back is the chapter before.
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(b.showing, first);
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(b.showing, second);
      await chord(tester, LogicalKeyboardKey.keyT, control: true);
      expect(contentsPanel, findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      await chord(tester, LogicalKeyboardKey.keyG, control: true);
      expectAnchored(tester);
      await key(tester, LogicalKeyboardKey.escape);
      await b.close();
    }, variant: windows);
  });

  group('desktop bottom bar', () {
    for (final (width, scale) in [
      (900.0, 1.0),
      (1280.0, 1.0),
      (900.0, 2.0),
      (840.0, 3.0),
    ]) {
      testWidgets(
        'groups its controls in the middle at $width, text x$scale',
        (tester) async {
          await pumpReader(
            tester,
            size: Size(width, 700),
            textScale: scale,
            chrome: true,
          );
          expect(tester.takeException(), isNull);
          final group = find.byKey(const ValueKey('reader-bottom-group'));
          final rect = tester.getRect(group);
          if (rect.width < width - 32) {
            expect(rect.center.dx, moreOrLessEquals(width / 2, epsilon: 1));
          }
          expect(
            tester.getSize(contentsButton).width,
            greaterThanOrEqualTo(ReaderBottomBar.contentsWidth),
          );
          expect(
            tester.getSize(progressButton).width,
            greaterThanOrEqualTo(ReaderBottomBar.progressWidth),
          );
          expect(
            tester.getSize(find.byTooltip(settingsTip)).width,
            greaterThanOrEqualTo(ReaderBottomBar.settingsWidth),
          );
          // No label is cut short.
          for (final label in [
            find.text('Contents'),
            progressLabel,
            find.text('Aa'),
          ]) {
            final text = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.descendant(of: group, matching: label),
                matching: find.byType(RichText),
                matchRoot: true,
              ),
            );
            expect(text.didExceedMaxLines, isFalse);
            expect(
              text.size.width,
              greaterThanOrEqualTo(
                text.getMaxIntrinsicWidth(double.infinity) - .5,
              ),
            );
          }
        },
        variant: windows,
      );
    }
  });

  testWidgets('touch platforms keep their keys, bar and taps', (tester) async {
    final reader = await pumpReader(tester, size: const Size(800, 1200));
    final start = reader.fraction;
    await key(tester, LogicalKeyboardKey.arrowRight);
    final next = reader.fraction;
    expect(next, greaterThan(start));
    await key(tester, LogicalKeyboardKey.space);
    await chord(tester, LogicalKeyboardKey.space, shift: true);
    for (final shortcut in [
      LogicalKeyboardKey.keyT,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.comma,
    ]) {
      await chord(tester, shortcut, control: true);
    }
    await key(tester, LogicalKeyboardKey.contextMenu);
    await rightClick(tester, const Offset(400, 600));
    expect(reader.fraction, next);
    expect(find.byType(BottomSheet), findsNothing);
    expect(menuItems, findsNothing);
    expect(find.byTooltip('Reading settings'), findsNothing);

    await key(tester, LogicalKeyboardKey.f2);
    expect(find.byTooltip('Reading settings'), findsOneWidget);
    expect(find.byTooltip(settingsTip), findsNothing);
    expect(find.byKey(const ValueKey('reader-bottom-group')), findsNothing);
    // Three equal thirds across the bar.
    final thirds = [
      for (final finder in [
        contentsButton,
        progressButton,
        find.byTooltip('Reading settings'),
      ])
        tester.getSize(finder).width,
    ];
    expect(thirds[1], moreOrLessEquals(thirds[0], epsilon: 1));
    expect(thirds[2], moreOrLessEquals(thirds[0], epsilon: 1));
  }, variant: android);
}
