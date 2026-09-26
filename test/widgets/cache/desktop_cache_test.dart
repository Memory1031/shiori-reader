import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/cache/cache_screen.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/home/desktop_shell.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/shared/widgets/desktop_content_frame.dart';
import 'package:shiori/shared/widgets/state_views.dart';
import 'harness.dart';

final windows = TargetPlatformVariant.only(TargetPlatform.windows);
Finder more(CacheHarness h, int i) =>
    find.descendant(of: h.book(i), matching: find.byType(IconButton));
Future<void> key(WidgetTester tester, LogicalKeyboardKey value) async {
  await tester.sendKeyEvent(value);
  await tester.pumpAndSettle();
}

Future<void> rightClick(WidgetTester tester, Offset at) async {
  final mouse = await tester.startGesture(
    at,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await mouse.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [900.0, 1280.0, 1600.0, 1920.0]) {
    testWidgets('Cache centered page and readable content at $width', (
      tester,
    ) async {
      final h = CacheHarness(tester);
      await h.pump(width: width);
      final viewport = tester.getRect(h.view);
      final toolbar = tester.getRect(find.byType(DesktopPageToolbar));
      final card = tester.getRect(find.byKey(const ValueKey('cache-storage')));
      expect(viewport.width, width - (width < 1200 ? 72 : 232));
      expect(toolbar.width, (viewport.width - 2 * ShioriLayout.gutter(width)));
      expect(toolbar.center.dx, viewport.center.dx);
      expect(card.width, toolbar.width.clamp(0, 760));
      expect(card.center.dx, viewport.center.dx);
      expect(tester.getRect(h.book(0)).left, card.left);
      expect(tester.getRect(h.book(0)).right, card.right);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      final scrollbar = find.descendant(
        of: h.page,
        matching: find.byType(Scrollbar),
      );
      expect(scrollbar, findsOneWidget);
      expect(tester.getRect(scrollbar).right, viewport.right);
      await h.close();
    }, variant: windows);
  }

  testWidgets('bounded Shell width and standalone route geometry', (
    tester,
  ) async {
    final h = CacheHarness(tester);
    await h.pump(width: 1920, bounded: 900);
    expect(tester.getRect(h.view).width, 828);
    expect(tester.getRect(find.byType(DesktopPageToolbar)).width, 780);
    await h.close();
    final root = CacheHarness(tester);
    await root.pump(width: 900, shell: false);
    expect(tester.getRect(root.view).width, 900);
    expect(find.byType(BackButton), findsNothing);
    final navigator = Navigator.of(tester.element(root.page));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => CacheScreen(cache: root.cache)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(navigator.canPop(), isFalse);
    await root.close();
  }, variant: windows);

  testWidgets(
    'margin wheel, edge thumb, breakpoint owner and expansion identity',
    (tester) async {
      final h = CacheHarness(tester);
      await h.pump(width: 1920);
      await h.expand(0);
      final page = tester.element(h.page), viewport = tester.element(h.view);
      final workspace = h.workspace, scroll = h.scroll;
      final controller = tester.widget<ListView>(h.view).controller;
      final expansion = tester.state(find.byType(ExpansionTile).first);
      for (final width in [
        839.0,
        840.0,
        839.0,
        900.0,
        1199.0,
        1200.0,
        1199.0,
        1920.0,
      ]) {
        await h.resize(width);
        expect(tester.element(h.page), same(page));
        expect(tester.element(h.view), same(viewport));
        expect(h.workspace, same(workspace));
        expect(h.scroll, same(scroll));
        expect(tester.widget<ListView>(h.view).controller, same(controller));
        expect(tester.state(find.byType(ExpansionTile).first), same(expansion));
        expect(h.chapter(0), findsOneWidget);
        expect(
          find.byType(DesktopPageToolbar),
          width >= 840 ? findsOneWidget : findsNothing,
        );
      }
      final bounds = tester.getRect(h.view);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: Offset(bounds.right - 25, bounds.center.dy),
          scrollDelta: const Offset(0, 500),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      final offset = scroll.position.pixels;
      for (final width in [839.0, 840.0, 1199.0, 1200.0, 1920.0]) {
        await h.resize(width);
        expect(scroll.position.pixels, closeTo(offset, 1));
      }
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final thumb = Offset(bounds.right - 4, bounds.top + 16);
      await mouse.addPointer(location: thumb);
      await mouse.moveTo(thumb + const Offset(0, 1));
      await tester.pumpAndSettle();
      await mouse.down(thumb);
      await mouse.moveBy(const Offset(0, 120));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(200));
      await mouse.removePointer();
      expect(h.cache.inspections, 1);
      await h.close();
    },
    variant: windows,
  );

  for (final lang in ['zh', 'en']) {
    testWidgets('large text short Cache layout $lang', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = lang == 'zh'
          ? Brightness.dark
          : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final h = CacheHarness(tester, cache: DesktopCache(books: 2));
      await h.pump(width: 900, height: 500, scale: 2, lang: lang);
      final toolbar = tester.getRect(find.byType(DesktopPageToolbar));
      final refresh = tester.getRect(
        find.byKey(const ValueKey('cache-refresh')),
      );
      expect(refresh.right, lessThanOrEqualTo(toolbar.right));
      expect(refresh.bottom, lessThan(500));
      await tester.ensureVisible(find.byKey(const ValueKey('cache-clear-all')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cache-clear-all')).hitTestable(),
        findsOneWidget,
      );
      await h.expand(0);
      await tester.ensureVisible(h.chapter(0));
      await tester.pumpAndSettle();
      expect(h.chapter(0).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.close();
    }, variant: windows);
  }

  testWidgets(
    'loading failure empty and refresh share page geometry; prefetch single-flight',
    (tester) async {
      final cache = DesktopCache()
        ..pending = Completer<Result<CacheOverview>>();
      final h = CacheHarness(tester, cache: cache);
      await h.pump(settle: false);
      await tester.pump();
      final toolbar = tester.getRect(find.byType(DesktopPageToolbar));
      final viewport = tester.element(h.view);
      expect(find.byType(LoadingView), findsOneWidget);
      cache.prefetch.emit(PrefetchPhase.complete);
      await tester.pump();
      expect(cache.inspections, 1);
      cache.pending!.complete(Failure(cacheFailure));
      await tester.pumpAndSettle();
      expect(find.byType(FailureView), findsOneWidget);
      expect(tester.element(h.view), same(viewport));
      expect(tester.getRect(find.byType(DesktopPageToolbar)), toolbar);
      cache.pending = null;
      cache.data = CacheOverview(
        textBytes: 0,
        imageBytes: 0,
        chapters: const [],
      );
      await tester.tap(find.byKey(const ValueKey('cache-refresh')));
      await tester.pumpAndSettle();
      expect(find.byType(EmptyView), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('cache-storage'))).center.dx,
        toolbar.center.dx,
      );
      cache.data = DesktopCache().data;
      cache.prefetch.emit(PrefetchPhase.running);
      await tester.pump();
      expect(cache.inspections, 2);
      cache.prefetch.emit(PrefetchPhase.complete);
      await tester.pumpAndSettle();
      expect(cache.inspections, 3);
      await h.expand(0);
      final expansion = tester.state(find.byType(ExpansionTile).first);
      h.scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      cache.pending = Completer<Result<CacheOverview>>();
      await tester.tap(find.byKey(const ValueKey('cache-refresh')));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('cache-refresh')))
            .onPressed,
        isNull,
      );
      expect(tester.widget<IconButton>(more(h, 0)).onPressed, isNull);
      cache.prefetch.emit(PrefetchPhase.complete);
      expect(cache.inspections, 4);
      cache.pending!.complete(Failure(cacheFailure));
      await tester.pumpAndSettle();
      expect(find.byType(FailureView), findsOneWidget);
      expect(tester.state(find.byType(ExpansionTile).first), same(expansion));
      await tester.ensureVisible(h.chapter(0));
      expect(h.chapter(0), findsOneWidget);
      expect(h.chapter(1), findsNothing);
      cache.pending = null;
      h.scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cache-refresh')));
      await tester.pumpAndSettle();
      expect(find.byType(FailureView), findsNothing);
      expect(h.chapter(0), findsOneWidget);
      expect(tester.state(find.byType(ExpansionTile).first), same(expansion));
      expect(cache.inspections, 5);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      cache.prefetch.emit(PrefetchPhase.complete);
      expect(cache.inspections, 5);
      await h.close();
    },
    variant: windows,
  );

  testWidgets(
    'desktop book menu input shares confirmation and chapter activation is single',
    (tester) async {
      final h = CacheHarness(tester);
      await h.pump(shell: false);
      await rightClick(tester, tester.getCenter(h.book(0)));
      expect(h.chapter(0), findsNothing);
      expect(find.text(h.l.cacheClearBook), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      await h.expand(0);
      final header = find.descendant(
        of: h.book(0),
        matching: find.text('Cached book 0 with a long title'),
      );
      final headerFocus = Focus.of(tester.element(header));
      headerFocus.requestFocus();
      await tester.pump();
      for (final menuKey in [
        LogicalKeyboardKey.contextMenu,
        LogicalKeyboardKey.f10,
      ]) {
        if (menuKey == LogicalKeyboardKey.f10) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await key(tester, menuKey);
        if (menuKey == LogicalKeyboardKey.f10) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        expect(find.text(h.l.cacheClearBook), findsOneWidget);
        await key(tester, LogicalKeyboardKey.escape);
        expect(headerFocus.hasFocus, isTrue);
      }
      await key(tester, LogicalKeyboardKey.tab);
      expect(headerFocus.hasPrimaryFocus, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await key(tester, LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(headerFocus.hasPrimaryFocus, isTrue);
      final chapterFocus = Focus.of(
        tester.element(
          find.descendant(
            of: h.chapter(0),
            matching: find.text('Offline chapter 0'),
          ),
        ),
      );
      chapterFocus.requestFocus();
      await tester.pump();
      await key(tester, LogicalKeyboardKey.enter);
      expect(h.reads.length, 1);
      await key(tester, LogicalKeyboardKey.space);
      expect(h.reads.length, 2);
      await tester.tap(h.chapter(0));
      expect(h.reads.length, 3);
      await tester.tap(more(h, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(h.l.cacheClearBook));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(h.cache.clears, isEmpty);
      await key(tester, LogicalKeyboardKey.escape);
      expect(h.cache.clears, isEmpty);
      await tester.tap(more(h, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(h.l.cacheClearBook));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, h.l.cacheClear));
      await tester.pumpAndSettle();
      expect(h.cache.clears, [h.cache.novel(0)]);
      expect(h.cache.inspections, 2);
      h.scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cache-clear-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, h.l.cacheClear));
      await tester.pumpAndSettle();
      expect(h.cache.clears, [h.cache.novel(0), null]);
      await h.close();
    },
    variant: windows,
  );

  testWidgets(
    'Cache Offline Reader Back preserves route list and expansion; section lifecycle',
    (tester) async {
      final h = CacheHarness(tester);
      await h.env.novels.loadChapter(
        h.cache.chapter(0),
        mode: ReadMode.cacheFirst,
        cancellation: CancellationSource().token,
      );
      await h.env.novels.loadCatalog(
        h.cache.novel(0),
        mode: ReadMode.cacheFirst,
        cancellation: CancellationSource().token,
      );
      await h.pump();
      await h.expand(0);
      h.scroll.position.jumpTo(160);
      await tester.pumpAndSettle();
      final page = tester.element(h.page), viewport = tester.element(h.view);
      final workspace = h.workspace;
      final offset = h.scroll.position.pixels;
      await tester.tap(h.chapter(0));
      await tester.pumpAndSettle();
      final reader = tester.element(find.byType(BookReaderScreen));
      expect(
        tester.widget<BookReaderScreen>(find.byType(BookReaderScreen)).offline,
        isTrue,
      );
      expect(Navigator.of(reader), isNot(same(workspace)));
      expect(find.byType(ShellNavigation), findsNothing);
      for (final width in [839.0, 840.0, 1199.0, 1200.0]) {
        await h.resize(width);
        expect(h.workspace, same(workspace));
        expect(
          tester.element(find.byType(CacheScreen, skipOffstage: false)),
          same(page),
        );
      }
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(BookReaderScreen), findsNothing);
      expect(tester.element(h.page), same(page));
      expect(tester.element(h.view), same(viewport));
      expect(h.chapter(0), findsOneWidget);
      expect(h.scroll.position.pixels, closeTo(offset, 1));
      h.navigation.select(HomeSection.offline);
      await tester.pumpAndSettle();
      expect(tester.element(h.page), same(page));
      expect(h.chapter(0), findsOneWidget);
      h.navigation.select(HomeSection.shelf);
      await tester.pumpAndSettle();
      expect(h.page, findsNothing);
      h.navigation.select(HomeSection.offline);
      await tester.pumpAndSettle();
      // A different section retires this route, as before; no global session.
      expect(tester.element(h.page), isNot(same(page)));
      expect(h.chapter(0), findsNothing);
      expect(h.workspace, same(workspace));
      await h.close();
    },
    variant: windows,
  );

  testWidgets(
    'pointer dismissal leaves later focus alone; Escape closes only root menu',
    (tester) async {
      final h = CacheHarness(tester);
      await h.pump();
      final workspace = h.workspace;
      unawaited(
        workspace.push(
          MaterialPageRoute<void>(builder: (_) => CacheScreen(cache: h.cache)),
        ),
      );
      await tester.pumpAndSettle();
      final page = tester.element(h.page);
      await h.expand(0);
      final label = find.descendant(
        of: h.book(0),
        matching: find.text('Cached book 0 with a long title'),
      );
      final cardFocus = Focus.of(tester.element(label));
      cardFocus.requestFocus();
      await tester.pump();
      await key(tester, LogicalKeyboardKey.contextMenu);
      await key(tester, LogicalKeyboardKey.escape);
      expect(tester.element(h.page), same(page));
      expect(workspace.canPop(), isTrue);
      expect(cardFocus.hasFocus, isTrue);
      await tester.tap(more(h, 0));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(h.view);
      await tester.tapAt(Offset(viewport.right - 30, viewport.top + 40));
      await tester.pumpAndSettle();
      expect(find.text(h.l.cacheClearBook), findsNothing);
      expect(h.cache.clears, isEmpty);
      final refreshFocus = Focus.of(tester.element(find.byIcon(Icons.refresh)));
      refreshFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(refreshFocus.hasFocus, isTrue);
      expect(cardFocus.hasFocus, isFalse);
      expect(h.chapter(0), findsOneWidget);
      await h.close();
    },
    variant: windows,
  );

  testWidgets(
    'clear failure retains expanded cache and scoped confirmation',
    (tester) async {
      final cache = DesktopCache()..clearResult = Failure(cacheFailure);
      final h = CacheHarness(tester, cache: cache);
      await h.pump();
      await h.expand(0);
      h.scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(more(h, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(h.l.cacheClearBook));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, h.l.cacheClear));
      await tester.pumpAndSettle();
      expect(cache.clears, [cache.novel(0)]);
      expect(cache.inspections, 1);
      expect(find.byType(FailureView), findsOneWidget);
      expect(h.chapter(0), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('cache-refresh')))
            .onPressed,
        isNotNull,
      );
      await h.close();
    },
    variant: windows,
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'wide $platform keeps mobile presentation and route primary binding',
      (tester) async {
        final h = CacheHarness(tester);
        await h.pump(width: 1600, shell: false);
        expect(find.byType(DesktopPageToolbar), findsNothing);
        expect(find.byType(AppBar), findsOneWidget);
        expect(tester.getRect(h.view).width, 760);
        expect(tester.widget<ListView>(h.view).controller, isNull);
        final scaffold = find.descendant(
          of: h.page,
          matching: find.byType(Scaffold),
        );
        final primary = PrimaryScrollController.of(tester.element(scaffold));
        expect(primary.positions.single, same(h.scroll.position));
        expect(find.byType(PopupMenuButton<String>), findsWidgets);
        await h.expand(0);
        await tester.tap(h.chapter(0));
        expect(h.reads, [h.cache.chapter(0)]);
        await h.close();
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
