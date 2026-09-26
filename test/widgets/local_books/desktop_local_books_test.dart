import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/local_books/desktop_local_books.dart';
import 'package:shiori/features/local_books/local_reparse_flow.dart';
import 'package:shiori/shared/widgets/book_list_tile.dart';
import 'package:shiori/shared/widgets/desktop_content_frame.dart';
import 'harness.dart';
import 'package:shiori/shared/widgets/state_views.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/local_books/local_books_screen.dart';

final windows = TargetPlatformVariant.only(TargetPlatform.windows);
Future<void> rightClick(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(
    at,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> menu(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(DesktopLocalBookRow).first,
      matching: find.byType(IconButton),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester, LocalHarness h) async {
  await menu(tester);
  await tester.tap(find.text(h.l.localReparse));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, h.l.localReparse));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  for (final width in [900.0, 1280.0, 1600.0, 1920.0]) {
    testWidgets('centered local content and full viewport $width', (
      tester,
    ) async {
      final h = LocalHarness(tester);
      await h.pump(width: width, shell: true);
      final viewport = tester.getRect(h.view);
      final chrome = tester.getRect(find.byType(DesktopPageToolbar));
      expect(chrome.left, viewport.left + ShioriLayout.gutter(width));
      expect(chrome.right, viewport.right - ShioriLayout.gutter(width));
      final frame = tester.getRect(
        find.byKey(const ValueKey('local-library-summary')),
      );
      final expected = (viewport.width - 2 * (width < 1200 ? 24 : 32)).clamp(
        0,
        1200,
      );
      expect(frame.width, expected);
      expect(frame.center.dx, viewport.center.dx);
      final tile = tester.getRect(find.byType(BookListTile).first);
      final row = tester.getRect(find.byType(DesktopLocalBookRow).first);
      final more = tester.getRect(
        find.descendant(
          of: find.byType(DesktopLocalBookRow).first,
          matching: find.byType(IconButton),
        ),
      );
      expect(row.left, frame.left);
      expect(row.right, frame.right);
      expect(tile.left, frame.left + ShioriSpace.item);
      expect(
        tile.width,
        (expected - 3 * ShioriSpace.item - more.width).clamp(
          0,
          ShioriLayout.page,
        ),
      );
      expect(more.right, frame.right - ShioriSpace.item);
      expect(more.top, tile.top);
      final card = find.byKey(const ValueKey('local-library-summary'));
      expect(tester.getRect(card).left, frame.left);
      expect(tester.getRect(card).right, frame.right);
      expect(
        find.descendant(of: card, matching: find.text(h.l.localBooksCount(45))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('EPUB 23 · TXT 22')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text(h.l.localBooksSubtitle)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('local-books-reparse-all')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(DesktopPageToolbar),
          matching: find.text(h.l.localReparseAll),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(DesktopPageToolbar),
          matching: find.text(h.l.localBooksCount(45)),
        ),
        findsNothing,
      );
      final scrollbars = find.descendant(
        of: h.page,
        matching: find.byType(Scrollbar),
      );
      expect(scrollbars, findsOneWidget);
      expect(tester.getRect(scrollbars).right, viewport.right);
      expect(find.byType(DesktopLocalBookRow), findsWidgets);
      expect(find.textContaining('Imported'), findsWidgets);
      expect(tester.takeException(), isNull);
      await h.close();
    }, variant: windows);
  }
  for (final lang in ['en', 'zh']) {
    testWidgets('short large-text local toolbar $lang', (tester) async {
      if (lang == 'zh') {
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      }
      final h = LocalHarness(tester);
      await h.pump(width: 900, height: 500, scale: 2, lang: lang, shell: true);
      final import = tester.getRect(
        find.byKey(const ValueKey('local-books-import')),
      );
      expect(import.bottom, lessThan(500));
      expect(import.width, greaterThan(40));
      final frame = tester.getRect(find.byType(DesktopPageToolbar));
      expect(import.right, lessThanOrEqualTo(frame.right));
      expect(tester.takeException(), isNull);
      await h.close();
    }, variant: windows);
  }
  testWidgets('bounded shell uses own width for gutter', (tester) async {
    final h = LocalHarness(tester);
    await h.pump(width: 1920, bounded: 900, shell: true);
    final viewport = tester.getRect(h.view),
        frame = tester.getRect(find.byType(DesktopPageToolbar));
    expect(viewport.width, 828);
    expect(frame.left - viewport.left, 24);
    expect(frame.width, 780);
    await h.close();
  }, variant: windows);
  testWidgets(
    'margin wheel, draggable automatic edge scrollbar, identity/filter across breakpoints',
    (tester) async {
      final h = LocalHarness(tester);
      await h.pump(shell: true);
      await tester.tap(find.widgetWithText(ChoiceChip, 'EPUB 23'));
      await tester.pumpAndSettle();
      final page = tester.element(h.page),
          view = tester.element(h.view),
          scroll = h.scroll,
          controller = tester.widget<CustomScrollView>(h.view).controller;
      final viewport = tester.getRect(h.view);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(viewport.right - 50, viewport.center.dy),
          scrollDelta: const Offset(0, 650),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, 650);
      for (final width in [839.0, 840.0, 1199.0, 1200.0, 1920.0]) {
        await h.resize(width);
        expect(tester.element(h.page), same(page));
        expect(tester.element(h.view), same(view));
        expect(h.scroll, same(scroll));
        expect(
          tester.widget<CustomScrollView>(h.view).controller,
          same(controller),
        );
        expect(h.scroll.position.pixels, greaterThan(400));
        expect(storeVisible(tester), isNot(contains('Local book 1 with')));
      }
      expect(
        h.store.watches,
        2,
      ); // LibraryController plus the page, not resize.
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: Offset(viewport.right - 4, viewport.top + 16),
      );
      await mouse.moveTo(Offset(viewport.right - 4, viewport.top + 17));
      await tester.pumpAndSettle();
      await mouse.down(Offset(viewport.right - 4, viewport.top + 17));
      await mouse.moveBy(const Offset(0, 140));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      await mouse.removePointer();
      await h.close();
    },
    variant: windows,
  );
  testWidgets(
    'row read, right click, menu keys, focus restoration and details',
    (tester) async {
      final h = LocalHarness(tester);
      await h.pump();
      final row = find.byType(DesktopLocalBookRow).first;
      await tester.tap(find.text('Book'));
      expect(h.reads, 1);
      await rightClick(tester, tester.getCenter(row));
      expect(h.reads, 1);
      expect(find.text(h.l.localReparse), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final node = FocusManager.instance.primaryFocus!;
      expect(node.debugLabel, 'local-book-row');
      for (final key in [
        LogicalKeyboardKey.contextMenu,
        LogicalKeyboardKey.f10,
      ]) {
        if (key == LogicalKeyboardKey.f10) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyEvent(key);
        if (key == LogicalKeyboardKey.f10) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pumpAndSettle();
        expect(find.text(h.l.localReparse), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(node.hasFocus, isTrue);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(h.reads, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(h.reads, 3);
      await menu(tester);
      await tester.tap(find.text(h.l.novelDetailsTitle));
      await tester.pumpAndSettle();
      expect(h.details, 1);
      expect(h.reads, 3);
      await menu(tester);
      await tester.tapAt(const Offset(50, 500));
      await tester.pumpAndSettle();
      // No explicit row requestFocus on pointer dismissal (Navigator may restore its own scope).
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      await h.close();
    },
    variant: windows,
  );
  testWidgets(
    'confirm single flight; Stop holds route and busy until service unwind',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore()..gate = Completer());
      await h.pump();
      final start = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('local-books-reparse-all')),
          )
          .onPressed!;
      start();
      start();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(h.store.calls, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, h.l.localReparseAll));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(h.store.calls, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.tapAt(const Offset(2, 400));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(h.l.localReparseStop));
      await tester.pump();
      expect(h.store.calls.single.token.isCancelled, isTrue);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      start();
      await tester.pump();
      expect(h.store.calls, hasLength(1));
      h.store.gate!.complete(
        Failure(AppFailure.cancelled(Operation.libraryWrite)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LocalReparseResultView), findsOneWidget);
      expect(find.text(h.l.localReparseAllSummary(0, 0, 45)), findsOneWidget);
      await tester.tap(find.text(h.l.importDone));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await h.close();
    },
    variant: windows,
  );
  testWidgets(
    'immediate encoding chooser stays above operation and cancel unwinds',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore()..prompt = true);
      await h.pump();
      await confirm(tester, h);
      expect(find.text('Sample'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, h.l.importCancel).last);
      await tester.pumpAndSettle();
      expect(h.store.calls.single.token.isCancelled, isTrue);
      expect(find.byType(LocalReparseResultView), findsOneWidget);
      expect(find.textContaining('database'), findsNothing);
      await tester.tap(find.text(h.l.importDone));
      await tester.pumpAndSettle();
      await h.close();
    },
    variant: windows,
  );
  testWidgets(
    'page disposal cancels delayed operation and produces no late UI',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore()..gate = Completer());
      await h.pump();
      await confirm(tester, h);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(h.store.calls.single.token.isCancelled, isTrue);
      h.store.gate!.complete(Success(LocalReparseResult(approximate: false)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await h.close();
    },
    variant: windows,
  );
  testWidgets(
    'delete confirms, removes row and reports cleanup; import uses root owner',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore()..cleanup = true);
      await h.pump(shell: true);
      final page = tester.element(h.page);
      await menu(tester);
      await tester.tap(find.text(h.l.localDeleteConfirm));
      await tester.pumpAndSettle();
      expect(h.store.deletes, 0);
      await tester.tap(
        find.widgetWithText(FilledButton, h.l.localDeleteConfirm),
      );
      await tester.pumpAndSettle();
      expect(h.store.deletes, 1);
      expect(find.text('Book'), findsNothing);
      expect(find.text(h.l.localCleanupPending), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('local-books-import')));
      await tester.pumpAndSettle();
      expect(h.imports, 1);
      expect(h.importer.panelOpen, isTrue);
      expect(
        tester.element(find.byType(LocalBooksScreen, skipOffstage: false)),
        same(page),
      );
      expect(
        find.byKey(const ValueKey('import-dismiss-barrier')),
        findsOneWidget,
      );
      h.importer.dismiss();
      await tester.pumpAndSettle();
      expect(tester.element(h.page), same(page));
      await h.close();
    },
    variant: windows,
  );
  testWidgets('unsupported service omits both reparse entries', (tester) async {
    final h = LocalHarness(tester);
    await h.pump(supportsReparse: false);
    expect(find.byKey(const ValueKey('local-books-reparse-all')), findsNothing);
    await menu(tester);
    expect(find.text(h.l.localReparse), findsNothing);
    expect(find.text(h.l.localDeleteConfirm), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await h.close();
  }, variant: windows);
  testWidgets(
    'cancel confirmation makes no request; forced operation close cancels before another session',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore()..gate = Completer());
      await h.pump();
      final start = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('local-books-reparse-all')),
          )
          .onPressed!;
      start();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.store.calls, isEmpty);
      await confirm(tester, h);
      final dialog = tester.element(find.byType(AlertDialog));
      Navigator.of(dialog).removeRoute(ModalRoute.of(dialog)!);
      await tester.pumpAndSettle();
      expect(h.store.calls.single.token.isCancelled, isTrue);
      start();
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(h.store.calls, hasLength(1));
      h.store.gate!.complete(
        Failure(AppFailure.cancelled(Operation.libraryWrite)),
      );
      await tester.pumpAndSettle();
      start();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await h.close();
    },
    variant: windows,
  );
  testWidgets(
    'inline operation retains Stop when resized into desktop and section exit cancels',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore()..gate = Completer());
      await h.pump(width: 839, shell: true);
      await tester.tap(find.byKey(const ValueKey('local-books-reparse-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, h.l.localReparseAll));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      tester.view.physicalSize = const Size(900, 720);
      await tester.pump();
      expect(find.byType(DesktopPageToolbar), findsOneWidget);
      expect(find.text(h.l.localReparseStop), findsOneWidget);
      await tester.tap(find.text(h.l.localReparseStop));
      await tester.pump();
      expect(h.store.calls.single.token.isCancelled, isTrue);
      h.navigation.select(HomeSection.shelf);
      await tester.pump();
      h.store.gate!.complete(
        Failure(AppFailure.cancelled(Operation.libraryWrite)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(h.store.calls, hasLength(1));
      await h.close();
    },
    variant: windows,
  );
  testWidgets('failure and empty retain the full viewport and toolbar', (
    tester,
  ) async {
    final h = LocalHarness(tester);
    await h.pump();
    final viewport = tester.element(h.view);
    h.store.updates.add(
      Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.libraryRead,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FailureView), findsOneWidget);
    expect(tester.element(h.view), same(viewport));
    expect(find.byType(DesktopPageToolbar), findsOneWidget);
    h.store.updates.add(const Success([]));
    await tester.pumpAndSettle();
    expect(find.text(h.l.localBooksEmpty), findsOneWidget);
    expect(find.byType(DesktopLocalBookRow), findsNothing);
    expect(tester.element(h.view), same(viewport));
    expect(find.byKey(const ValueKey('local-books-import')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.close();
  }, variant: windows);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'wide $platform retains mobile controls and primary position',
      (tester) async {
        final h = LocalHarness(tester);
        await h.pump();
        expect(find.byType(DesktopPageToolbar), findsNothing);
        expect(find.byType(AppBar), findsOneWidget);
        expect(
          find.byKey(ValueKey(('local-book-reparse', h.store.books.first.key))),
          findsOneWidget,
        );
        final scaffold = tester.element(find.byType(Scaffold).first);
        expect(
          PrimaryScrollController.of(scaffold).positions,
          contains(h.scroll.position),
        );
        await h.close();
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}

String storeVisible(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((e) => e.data ?? '')
    .join('|');
