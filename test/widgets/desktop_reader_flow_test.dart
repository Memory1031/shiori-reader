import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/home/desktop_shell.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/novel_detail/desktop_detail.dart';
import 'package:shiori/features/novel_detail/detail_sections.dart';
import 'package:shiori/features/novel_detail/detail_screen.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/search/search_screen.dart';

import 'desktop_shell_test.dart' show ShellHarness;

final _desktop = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  Future<void> read(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('detail-read')));
    await tester.pumpAndSettle();
    expect(find.byType(BookReaderScreen), findsOneWidget);
  }

  testWidgets('the reader covers the shell and resizing keeps both', (
    tester,
  ) async {
    final h = ShellHarness(tester);
    await h.pump();
    await h.search();
    await h.openResult();
    final detail = tester.element(find.byType(DetailScreen));
    final search = tester.element(
      find.byType(SearchScreen, skipOffstage: false),
    );
    await read(tester);
    final reader = tester.element(find.byType(BookReaderScreen));
    expect(Navigator.of(reader), same(h.root));
    // The shell is covered, not replaced.
    expect(find.byType(ShellNavigation), findsNothing);
    expect(find.byType(ShellNavigation, skipOffstage: false), findsOneWidget);

    for (final width in [900.0, 820.0, 1280.0, 900.0]) {
      await h.resize(width);
      expect(tester.element(find.byType(BookReaderScreen)), same(reader));
      expect(
        tester.element(find.byType(DetailScreen, skipOffstage: false)),
        same(detail),
      );
      expect(tester.takeException(), isNull, reason: '$width');
    }

    // Escape in the reader never reaches the workspace.
    await h.key(LogicalKeyboardKey.escape);
    await h.key(LogicalKeyboardKey.escape);
    expect(
      tester.element(find.byType(DetailScreen, skipOffstage: false)),
      same(detail),
    );
    expect(h.workspace.canPop(), isTrue);
    expect(h.navigation.section, HomeSection.search);

    if (find.byType(BookReaderScreen).evaluate().isNotEmpty) {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    expect(find.byType(BookReaderScreen), findsNothing);
    expect(h.layout, ShellLayout.rail);
    expect(tester.element(find.byType(DetailScreen)), same(detail));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(SearchScreen)), same(search));
    await h.close();
  }, variant: _desktop);

  testWidgets('details from the reader open over it and back returns', (
    tester,
  ) async {
    final h = ShellHarness(tester);
    await h.pump();
    await h.search();
    await h.openResult();
    await read(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(h.l.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.l.novelDetailsTitle).last);
    await tester.pumpAndSettle();
    final over = find.byType(DetailScreen);
    expect(over, findsOneWidget);
    // Full window, above the reader rather than in the workspace.
    expect(Navigator.of(tester.element(over)), same(h.root));
    expect(find.byType(ShellNavigation), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BookReaderScreen), findsOneWidget);
    // The reader is back as it was left: toolbars shown, so back first
    // closes them and then leaves.
    expect(find.byTooltip(h.l.moreActions), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BookReaderScreen), findsOneWidget);
    expect(find.byTooltip(h.l.moreActions), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BookReaderScreen), findsNothing);
    expect(find.byType(DetailScreen), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(DetailScreen))),
      same(h.workspace),
    );
    await h.close();
  }, variant: _desktop);

  testWidgets('returning to the shelf clears the reader and details', (
    tester,
  ) async {
    final h = ShellHarness(tester);
    await h.pump(onShelf: true);

    // From another section.
    await h.search();
    await h.openResult();
    await read(tester);
    tester
        .widget<BookReaderScreen>(find.byType(BookReaderScreen))
        .onReturnToShelf!();
    await tester.pumpAndSettle();
    expect(find.byType(BookReaderScreen), findsNothing);
    expect(find.byType(DetailScreen, skipOffstage: false), findsNothing);
    expect(find.byType(BookshelfView), findsOneWidget);
    expect(h.navigation.section, HomeSection.shelf);
    expect(h.workspace.canPop(), isFalse);

    // With the shelf already selected and its details open.
    await tester.tap(find.byTooltip(h.l.shelfList));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(h.l.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.l.novelDetailsTitle));
    await tester.pumpAndSettle();
    expect(h.workspace.canPop(), isTrue);
    await read(tester);
    tester
        .widget<BookReaderScreen>(find.byType(BookReaderScreen))
        .onReturnToShelf!();
    await tester.pumpAndSettle();
    expect(find.byType(BookReaderScreen), findsNothing);
    expect(find.byType(DetailScreen, skipOffstage: false), findsNothing);
    expect(find.byType(BookshelfView), findsOneWidget);
    expect(h.workspace.canPop(), isFalse);
    // The layout chosen before reading is kept.
    expect(h.shelfGrid, isFalse);
    await h.close();
  }, variant: _desktop);

  testWidgets('resume from the shelf reads over the shell', (tester) async {
    final h = ShellHarness(tester);
    await h.pump(onShelf: true, progress: true);
    await tester.tap(find.text(h.l.homeContinueAction));
    await tester.pumpAndSettle();
    expect(find.byType(BookReaderScreen), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(BookReaderScreen))),
      same(h.root),
    );
    await h.resize(820);
    await h.resize(1280);
    expect(tester.takeException(), isNull);
    tester
        .widget<BookReaderScreen>(find.byType(BookReaderScreen))
        .onReturnToShelf!();
    await tester.pumpAndSettle();
    expect(find.byType(BookshelfView), findsOneWidget);
    expect(h.layout, ShellLayout.sidebar);
    await h.close();
  }, variant: _desktop);

  testWidgets('details over the reader use the window frame and keep their '
      'state', (tester) async {
    final h = ShellHarness(tester);
    await h.pump();
    await h.search();
    await h.openResult();
    await read(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(h.l.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.l.novelDetailsTitle).last);
    await tester.pumpAndSettle();
    // The workspace copy stays mounted under the reader; the two share no
    // keys.
    expect(find.byType(DesktopDetail, skipOffstage: false), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    final over = find.byType(DesktopDetail);
    expect(Navigator.of(tester.element(over)), same(h.root));
    final state = tester.state(over);

    Rect back() => tester.getRect(find.byKey(const ValueKey('detail-back')));
    Rect cover() => tester.getRect(
      find.descendant(of: over, matching: find.byType(DetailCover)),
    );
    expect(back().left, closeTo(ShioriLayout.gutter(1280), .01));
    expect(cover().width, closeTo(ShioriLayout.detailSideWide, .01));

    for (final width in [900.0, 1600.0, 1280.0]) {
      await h.resize(width);
      expect(tester.state(find.byType(DesktopDetail)), same(state));
      expect(back().left, closeTo(ShioriLayout.gutter(width), .01));
      expect(tester.takeException(), isNull, reason: '$width');
    }
    expect(cover().width, closeTo(ShioriLayout.detailSideWide, .01));

    // Reading from here returns to the reader beneath.
    final reader = tester.element(
      find.byType(BookReaderScreen, skipOffstage: false),
    );
    await tester.tap(find.byKey(const ValueKey('detail-read')));
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(BookReaderScreen)), same(reader));
    expect(find.byType(DesktopDetail), findsNothing);
    expect(find.byType(DesktopDetail, skipOffstage: false), findsOneWidget);
    await h.close();
  }, variant: _desktop);
}
