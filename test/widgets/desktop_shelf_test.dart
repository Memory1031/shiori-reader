import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/bookshelf/desktop_shelf.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/home/continue_reading_row.dart';
import 'package:shiori/features/novel_detail/detail_screen.dart';
import 'package:shiori/features/reader/book_progress_label.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

import 'desktop_shell_test.dart' show ShellHarness;

final _desktop = TargetPlatformVariant.only(TargetPlatform.windows);

Widget _app(
  Widget child, {
  double textScale = 1,
  double width = 900,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: appTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void _view(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1600, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

AppLocalizations _l(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold)));

ReadingProgress _progress(BookProgressSnapshot? book, {String? title}) {
  final chapter = fixtureChapterKey(FixtureScenario.multiVolume);
  return ReadingProgress(
    snapshot: NovelSummary(
      key: chapter.novelKey,
      title: title ?? 'A book in progress',
    ),
    chapterKey: chapter,
    chapterOrdinalSnapshot: 0,
    catalogRevision: 'r',
    position: ReaderPosition(
      contentRevision: 'r',
      blockKey: 'b',
      blockIndex: 0,
      blockFraction: 0,
      chapterFraction: 0,
    ),
    completed: false,
    bookProgress: book,
    lastReadAt: DateTime.utc(2026),
  );
}

FocusNode _node(String label) => FocusManager.instance.rootScope.descendants
    .firstWhere((node) => node.debugLabel == label);

Future<TestGesture> _hover(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(at);
  await tester.pumpAndSettle();
  return mouse;
}

Future<void> _rightClick(WidgetTester tester, Offset at) async {
  final mouse = await tester.startGesture(
    at,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await mouse.up();
  await tester.pumpAndSettle();
}

void main() {
  group('grid geometry', () {
    const normal = TextScaler.noScaling;
    void expectGrid(
      double width,
      int columns,
      double card, {
      TextScaler scaler = normal,
    }) {
      final grid = desktopShelfGrid(width, scaler);
      expect(grid.columns, columns, reason: '$width');
      expect(grid.card, closeTo(card, .01), reason: '$width');
      expect(
        grid.extent,
        closeTo(columns * card + (columns - 1) * gap, .1),
        reason: '$width',
      );
    }

    test('matches the window table at normal text', () {
      // Frames for 900 (rail), 1280 and 1600 (sidebar) windows, and the
      // 1600 cap that a 1920 window reaches.
      expectGrid(900 - 72 - 48, 5, 140);
      expectGrid(1280 - 232 - 64, 6, 147.33);
      expectGrid(1600 - 232 - 64, 8, 145.5);
      expectGrid(1600, 10, 142);
    });

    test('adds a column exactly where the minimum card fits', () {
      expectGrid(740, 5, 132);
      // One pixel short: four cards, capped and left-aligned.
      expectGrid(739, 4, 168);
      expect(desktopShelfGrid(739, normal).extent, lessThan(739));
      expectGrid(892, 6, 132);
      expectGrid(891, 5, 162.2);
    });

    test('narrow frames fall back to one column', () {
      expectGrid(100, 1, 100);
      expectGrid(0, 1, 0);
      expectGrid(151, 1, 151);
      expectGrid(284, 2, 132);
    });

    test('large text widens cards up to the density clamp', () {
      expectGrid(984, 5, 180.8, scaler: const TextScaler.linear(1.3));
      // Past the clamp the density does not change.
      expectGrid(984, 5, 180.8, scaler: const TextScaler.linear(2));
      // Smaller text does not shrink cards below the target.
      expectGrid(984, 6, 147.33, scaler: const TextScaler.linear(.8));
    });

    test('never overflows the frame or leaves the card bounds', () {
      for (final scale in [1.0, 1.15, 1.3, 2.0]) {
        final s = scale.clamp(1.0, maxDensityScale);
        for (var width = 0.0; width < 2000; width += 7) {
          final grid = desktopShelfGrid(width, TextScaler.linear(scale));
          expect(grid.columns, greaterThanOrEqualTo(1));
          expect(grid.extent, lessThanOrEqualTo(width + 1e-6));
          expect(grid.card, lessThanOrEqualTo(maxCard * s + 1e-6));
          if (grid.columns > 1) {
            expect(grid.card, greaterThanOrEqualTo(minCard * s - 1e-6));
          }
        }
      }
    });
  });

  group('continue row', () {
    for (final book in [
      null,
      BookProgressSnapshot(fraction: .36, chapterCount: 120),
      BookProgressSnapshot(
        fraction: 1,
        chapterCount: 120,
        terminal: BookTerminalState.caughtUp,
      ),
    ]) {
      for (final (width, scale) in [
        (900.0, 1.0),
        (1200.0, 2.0),
        (280.0, 2.0),
      ]) {
        testWidgets('${book?.terminal} ${book?.fraction} at $width x$scale', (
          tester,
        ) async {
          _view(tester);
          var resumed = 0;
          await tester.pumpWidget(
            _app(
              ContinueReadingRow(
                progress: _progress(book, title: 'A long title ' * 12),
                onContinue: () => resumed++,
              ),
              textScale: scale,
              width: width,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final l = _l(tester);
          final row = find.byType(ContinueReadingRow);
          expect(tester.getSize(row).width, width);
          expect(
            tester.getSize(row).height,
            greaterThanOrEqualTo(ContinueReadingRow.minHeight),
          );
          // Unknown progress is not shown as 0%; terminal states keep text.
          expect(
            find.text(
              bookProgressLabel(l, book, descriptive: true) ??
                  l.readerReadingProgress,
            ),
            findsOneWidget,
          );
          final bar = find.byType(LinearProgressIndicator);
          if (book == null) {
            expect(bar, findsNothing);
          } else {
            expect(
              tester.widget<LinearProgressIndicator>(bar).value,
              book.fraction,
            );
            expect(
              tester.getSize(bar).width,
              lessThanOrEqualTo(ContinueReadingRow.progressWidth),
            );
          }
          // The whole row and the button each resume exactly once.
          await tester.tap(find.text(l.detailContinue));
          await tester.pumpAndSettle();
          expect(resumed, 1);
          await tester.tap(find.byWidgetPredicate((w) => w is FilledButton));
          await tester.pumpAndSettle();
          expect(resumed, 2);
        });
      }
    }

    // Rows whose text column would fit beside a 112 button but not beside
    // the button as laid out: English text at 1.3 and above widens it,
    // while the shorter Chinese label keeps 112 even at 2.
    for (final (width, scale, stackedEn, stackedZh) in [
      (330.0, 1.0, true, true),
      (400.0, 1.0, true, true),
      (500.0, 1.0, false, false),
      (330.0, 1.3, true, true),
      (400.0, 1.3, true, true),
      (500.0, 1.3, true, false),
      (330.0, 2.0, true, true),
      (400.0, 2.0, true, true),
      (500.0, 2.0, true, false),
    ]) {
      for (final (language, stacked) in [
        ('en', stackedEn),
        ('zh', stackedZh),
      ]) {
        testWidgets('${stacked ? 'stacks' : 'keeps'} the button at $width '
            'x$scale $language', (tester) async {
          _view(tester);
          final title = 'A long title ' * 12;
          await tester.pumpWidget(
            _app(
              ContinueReadingRow(
                progress: _progress(
                  BookProgressSnapshot(fraction: .36, chapterCount: 120),
                  title: title,
                ),
                onContinue: () {},
              ),
              textScale: scale,
              width: width,
              locale: Locale(language),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final row = tester.getRect(find.byType(ContinueReadingRow));
          final content = Rect.fromLTRB(
            row.left + 16 + ContinueReadingRow.coverWidth + 16,
            row.top,
            row.right - 16,
            row.bottom,
          );
          final button = tester.getRect(
            find.byWidgetPredicate((w) => w is FilledButton),
          );
          final text = tester.getRect(
            find
                .ancestor(of: find.text(title), matching: find.byType(Column))
                .first,
          );
          // The decision follows the button's actual width.
          expect(
            content.width - button.width - 16 < ContinueReadingRow.stackBelow,
            stacked,
            reason: 'button ${button.width}',
          );
          if (stacked) {
            expect(button.top, greaterThanOrEqualTo(text.bottom + 8 - .01));
            expect(button.left, closeTo(content.left, .01));
          } else {
            expect(
              text.width,
              greaterThanOrEqualTo(ContinueReadingRow.stackBelow),
            );
            expect(text.right, lessThanOrEqualTo(button.left - 16 + .01));
            expect(button.right, closeTo(content.right, .01));
          }
          expect(text.left, closeTo(content.left, .01));
          expect(button.right, lessThanOrEqualTo(content.right + .01));
          expect(
            row.height,
            greaterThanOrEqualTo(ContinueReadingRow.minHeight),
          );
        });
      }
    }

    testWidgets('is one keyboard stop', (tester) async {
      _view(tester);
      var resumed = 0;
      await tester.pumpWidget(
        _app(
          ContinueReadingRow(
            progress: _progress(null),
            onContinue: () => resumed++,
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final first = primaryFocus;
      expect(
        find.ancestor(
          of: find.byElementPredicate((e) => e == first!.context),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(primaryFocus, same(first));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(resumed, 1);
    });
  });

  group('list row', () {
    Future<({List<Rect> menus, int Function() taps})> pumpRow(
      WidgetTester tester, {
      double width = 1200,
      double scale = 1,
      String title = 'A book',
      bool dismissed = true,
    }) async {
      _view(tester);
      final menus = <Rect>[];
      var taps = 0;
      await tester.pumpWidget(
        _app(
          DesktopBookRow(
            cover: const ColoredBox(color: Colors.teal),
            title: title,
            subtitle: 'An author',
            sourceLabel: 'epub',
            progressLabel: '36% read',
            progress: .36,
            onTap: () => taps++,
            onMenu: (anchor) async {
              menus.add(anchor);
              return dismissed;
            },
          ),
          width: width,
          textScale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return (menus: menus, taps: () => taps);
    }

    Rect rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);

    testWidgets('lays source and progress out in columns when wide', (
      tester,
    ) async {
      await pumpRow(tester);
      final row = rectOf(tester, find.byType(DesktopBookRow));
      expect(row.height, DesktopBookRow.minHeight);
      final title = rectOf(tester, find.text('A book'));
      final tag = rectOf(tester, find.byType(ShelfFormatTag));
      final label = rectOf(tester, find.text('36% read'));
      final bar = rectOf(tester, find.byType(LinearProgressIndicator));
      expect(tag.left, greaterThan(title.left));
      expect(label.left, greaterThan(tag.right));
      expect(bar.width, DesktopBookRow.progressColumn);
      expect(bar.left, label.left);
      expect((tag.center.dy - title.center.dy).abs(), lessThan(20));
    });

    testWidgets('narrows the progress column before stacking', (tester) async {
      await pumpRow(tester, width: 600);
      final bar = rectOf(tester, find.byType(LinearProgressIndicator));
      expect(bar.width, DesktopBookRow.narrowProgressColumn);
      expect(
        rectOf(tester, find.text('36% read')).left,
        greaterThan(rectOf(tester, find.text('A book')).right),
      );
    });

    for (final (width, scale) in [(500.0, 1.0), (1200.0, 1.6), (360.0, 2.0)]) {
      testWidgets('stacks below the text at $width x$scale', (tester) async {
        await pumpRow(tester, width: width, scale: scale, title: 'Long ' * 40);
        final title = rectOf(tester, find.textContaining('Long'));
        final label = rectOf(tester, find.text('36% read'));
        final bar = rectOf(tester, find.byType(LinearProgressIndicator));
        expect(label.top, greaterThan(title.bottom - 1));
        expect(bar.width, lessThanOrEqualTo(DesktopBookRow.maxProgressBar));
        expect(
          tester.getSize(find.byType(DesktopBookRow)).height,
          greaterThanOrEqualTo(DesktopBookRow.minHeight),
        );
        // The title keeps room and at most two lines.
        expect(title.width, greaterThan(width / 3));
        final lines = tester.renderObject<RenderParagraph>(
          find.textContaining('Long'),
        );
        expect(lines.didExceedMaxLines, isTrue);
      });
    }

    testWidgets('right click, the Menu key and Shift+F10 open the menu only', (
      tester,
    ) async {
      final row = await pumpRow(tester);
      final at = tester.getCenter(find.text('A book'));
      await _rightClick(tester, at);
      expect(row.menus.single.topLeft, at);
      expect(row.taps(), 0);
      // A pointer menu dismissed without a key leaves focus alone, so the
      // row doesn't keep a focus ring.
      expect(primaryFocus?.debugLabel, isNot('shelf-row'));

      _node('shelf-row').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      // A keyboard menu dismissed without a choice returns focus.
      expect(primaryFocus?.debugLabel, 'shelf-row');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(row.menus, hasLength(3));
      // Keyboard menus anchor at the more button.
      final more = rectOf(tester, find.byIcon(Icons.more_horiz));
      expect(row.menus.last, more);
      expect(row.taps(), 0);

      await tester.tap(find.text('A book'));
      await tester.pumpAndSettle();
      expect(row.taps(), 1);
    });
  });

  group('book menu', () {
    Finder card(ShellHarness h) => find.byKey(ValueKey(h.book.key));

    Finder moreButton(ShellHarness h) =>
        find.descendant(of: card(h), matching: find.byType(AnimatedOpacity));

    double moreOpacity(WidgetTester tester, ShellHarness h) =>
        tester.widget<AnimatedOpacity>(moreButton(h)).opacity;

    testWidgets('grid cards show more on hover and focus, and right click '
        'opens the menu without opening the book', (tester) async {
      final h = ShellHarness(tester);
      await h.pump(onShelf: true, progress: true);
      expect(h.shelfGrid, isTrue);
      expect(moreOpacity(tester, h), 0);

      final mouse = await _hover(tester, tester.getCenter(card(h)));
      expect(moreOpacity(tester, h), 1);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(moreOpacity(tester, h), 0);

      await _rightClick(tester, tester.getCenter(card(h)));
      expect(find.text(h.l.novelDetailsTitle), findsOneWidget);
      expect(find.text(h.l.detailRemoveShelf), findsOneWidget);
      // A started book resumes; the menu offers nothing else.
      expect(find.byType(PopupMenuDivider), findsOneWidget);
      expect(find.byType(DetailScreen), findsNothing);
      expect(find.byType(BookReaderScreen), findsNothing);

      // Escape closes only the menu and gives focus back to the card.
      await h.key(LogicalKeyboardKey.escape);
      expect(find.text(h.l.novelDetailsTitle), findsNothing);
      expect(h.workspace.canPop(), isFalse);
      expect(h.navigation.section, HomeSection.shelf);
      await tester.pumpAndSettle();
      expect(primaryFocus, same(_node('shelf-card')));
      expect(moreOpacity(tester, h), 1);

      // From the focused card, the Menu key reaches the same menu, and
      // details open in the workspace.
      await h.key(LogicalKeyboardKey.contextMenu);
      await tester.tap(find.text(h.l.novelDetailsTitle));
      await tester.pumpAndSettle();
      expect(
        Navigator.of(tester.element(find.byType(DetailScreen))),
        same(h.workspace),
      );
      await h.close();
    }, variant: _desktop);

    testWidgets('clicking outside the menu leaves the card unfocused', (
      tester,
    ) async {
      final h = ShellHarness(tester);
      await h.pump(onShelf: true, progress: true);
      final mouse = await _hover(tester, tester.getCenter(card(h)));
      await tester.tap(find.byTooltip(h.l.moreActions));
      await tester.pumpAndSettle();
      expect(find.text(h.l.novelDetailsTitle), findsOneWidget);

      final outside =
          tester.getRect(find.byType(BookshelfView)).bottomRight -
          const Offset(8, 8);
      await mouse.moveTo(outside);
      await mouse.down(outside);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text(h.l.novelDetailsTitle), findsNothing);
      expect(find.byType(DetailScreen), findsNothing);
      expect(_node('shelf-card').hasFocus, isFalse);
      expect(moreOpacity(tester, h), 0);
      final cover = tester.widget<AnimatedContainer>(
        find.descendant(of: card(h), matching: find.byType(AnimatedContainer)),
      );
      final ring = (cover.foregroundDecoration! as BoxDecoration).border!;
      expect((ring as Border).top.color.a, 0);
      await h.close();
    }, variant: _desktop);

    testWidgets('the more button opens the menu and resume reads over the '
        'shell', (tester) async {
      final h = ShellHarness(tester);
      await h.pump(onShelf: true, progress: true);
      final mouse = await _hover(tester, tester.getCenter(card(h)));
      await tester.tap(find.byTooltip(h.l.moreActions));
      await tester.pumpAndSettle();
      await mouse.moveTo(Offset.zero);
      expect(find.byType(DetailScreen), findsNothing);
      await tester.tap(find.text(h.l.detailContinue).last);
      await tester.pumpAndSettle();
      expect(
        Navigator.of(tester.element(find.byType(BookReaderScreen))),
        same(h.root),
      );
      await h.close();
    }, variant: _desktop);

    testWidgets('list rows open the menu from Shift+F10; an unread book '
        'offers to start', (tester) async {
      final h = ShellHarness(tester);
      await h.pump(onShelf: true);
      await tester.tap(find.byTooltip(h.l.shelfList));
      await tester.pumpAndSettle();
      expect(find.byType(ContinueReadingRow), findsNothing);
      _node('shelf-row').requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text(h.l.detailStart), findsOneWidget);
      expect(find.text(h.l.detailContinue), findsNothing);
      await h.key(LogicalKeyboardKey.escape);
      expect(find.text(h.l.detailStart), findsNothing);
      expect(primaryFocus, same(_node('shelf-row')));
      expect(h.workspace.canPop(), isFalse);
      await h.close();
    }, variant: _desktop);

    testWidgets('removing an imported book asks first', (tester) async {
      final h = ShellHarness(tester);
      final local = NovelSummary(
        key: LocalBookIdentity.book('c' * 64),
        title: 'Imported book',
      );
      await h.pump(local: local);
      Future<void> remove() async {
        await _rightClick(tester, tester.getCenter(find.text('Imported book')));
        await tester.tap(find.text(h.l.detailRemoveShelf));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      }

      await remove();
      await h.key(LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Imported book'), findsOneWidget);
      expect(h.workspace.canPop(), isFalse);

      await remove();
      await tester.tap(find.text('Delete book and progress'));
      await tester.pumpAndSettle();
      expect(find.text('Imported book'), findsNothing);
      expect(tester.takeException(), isNull);
      await h.close();
    }, variant: _desktop);
  });
}
