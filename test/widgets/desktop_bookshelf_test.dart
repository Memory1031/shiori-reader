import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/bookshelf/desktop_shelf.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/home/continue_reading_row.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/widgets/book_cover.dart';
import 'package:shiori/shared/widgets/book_list_tile.dart';
import 'package:shiori/shared/widgets/state_views.dart';

import 'reader/continue_test.dart' show seed;
import 'desktop_shell_test.dart' show ShellHarness;

/// A desktop home on a shelf of [books] long-titled books.
class _Shelf {
  _Shelf(this.tester);
  final WidgetTester tester;
  final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
  late double width;

  Future<void> pump({
    Size size = const Size(1280, 720),
    double dpr = 1,
    double textScale = 1,
    String language = 'zh',
    int books = 60,
    bool progress = true,
    bool settle = true,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    width = size.width / dpr;
    final token = CancellationSource().token;
    for (var i = 0; i < books; i++) {
      await env.library.putBookshelf(
        BookshelfEntry(
          snapshot: NovelSummary(
            key: i.isEven
                ? LocalBookIdentity.book(i.toRadixString(16).padLeft(64, '0'))
                : NovelKey(sourceId: SourceId('fixture'), novelId: '$i'),
            title: '$i ${'很长的中文书名 Long English book title ' * 3}',
            authors: ['${'Long author name 作者 ' * 4}$i'],
          ),
          addedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
        ),
        cancellation: token,
      );
    }
    if (progress) {
      await seed(env, fixtureChapterKey(FixtureScenario.multiVolume));
    }
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: appTheme(language == 'zh' ? Brightness.light : Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ReadingHome(
          repository: env.novels,
          library: env.library,
          sources: [env.source.descriptor],
          settings: env.settings,
          onImport: () {},
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(env.close);
  }

  Finder get shelf => find.byType(BookshelfView);
  AppLocalizations get l => AppLocalizations.of(tester.element(shelf));
  Rect get workspace => tester.getRect(
    find.ancestor(of: shelf, matching: find.byType(Scaffold)).first,
  );
  double get gutter => desktopShelfGutter(width);
  double get left => workspace.left + (workspace.width - frame(grid)) / 2;
  double frame(bool grid) =>
      (workspace.width - 2 * gutter).clamp(0, grid ? 1600 : 1200);
  bool get grid => tester
      .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
      .selected
      .single;

  /// Grid covers, without the one in the continue row.
  List<Rect> get covers {
    final row = find
        .descendant(
          of: find.byType(ContinueReadingRow),
          matching: find.byType(BookCover),
        )
        .evaluate()
        .toSet();
    return find
        .descendant(of: shelf, matching: find.byType(BookCover))
        .evaluate()
        .where((e) => !row.contains(e))
        .map((e) => tester.getRect(find.byWidget(e.widget)))
        .toList();
  }

  ScrollPosition get position => tester
      .state<ScrollableState>(
        find.descendant(of: shelf, matching: find.byType(Scrollable)).first,
      )
      .position;
}

void _near(double actual, double expected, String reason) =>
    expect(actual, closeTo(expected, .5), reason: reason);

/// Columns and card width at normal text for a window width, from the
/// confirmed acceptance table; other sizes follow [desktopShelfGrid].
const _table = {900: (5, 140.0), 1280: (6, 147.3), 1600: (8, 145.5)};

void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  for (final display in [
    (size: const Size(900, 720), dpr: 1.0),
    (size: const Size(1280, 720), dpr: 1.0),
    (size: const Size(1600, 900), dpr: 1.0),
    (size: const Size(1920, 1080), dpr: 1.0),
    (size: const Size(2560, 1440), dpr: 1.5),
  ]) {
    for (final language in ['zh', 'en']) {
      testWidgets(
        'desktop shelf frame ${display.size} DPR ${display.dpr} $language',
        (tester) async {
          final s = _Shelf(tester);
          await s.pump(
            size: display.size,
            dpr: display.dpr,
            language: language,
          );
          final l = s.l;
          final width = s.width;
          expect(
            s.workspace.left,
            closeTo(
              width >= ShioriLayout.sidebarBreakpoint
                  ? ShioriLayout.sidebar
                  : ShioriLayout.rail,
              .01,
            ),
          );
          expect(s.grid, isTrue);
          expect(find.text(l.shelfBookCount(60)), findsOneWidget);
          expect(find.text(l.homeContinueAction), findsOneWidget);

          // Title, continue row and first cover share the frame's left edge.
          final title = find.descendant(
            of: find.byType(DesktopShelfToolbar),
            matching: find.text(l.homeShelf),
          );
          _near(tester.getRect(title).left, s.left, 'title');
          final row = tester.getRect(find.byType(ContinueReadingRow));
          _near(row.left, s.left, 'continue row');
          _near(row.width, s.frame(true), 'continue row width');
          _near(
            tester.getRect(find.byType(DesktopShelfToolbar)).width,
            s.frame(true),
            'toolbar width',
          );
          final toolbar = tester.getRect(find.byType(DesktopShelfToolbar));
          final toggle = tester.getRect(find.byType(SegmentedButton<bool>));
          final import = tester.getRect(
            find.descendant(
              of: find.byType(DesktopShelfToolbar),
              matching: find.byType(OutlinedButton),
            ),
          );
          _near(toggle.center.dy, import.center.dy, 'toolbar action centers');
          _near(
            toolbar.left - s.workspace.left,
            s.workspace.right - toolbar.right,
            'centered content',
          );
          final scrollView = find.descendant(
            of: s.shelf,
            matching: find.byType(CustomScrollView),
          );
          final viewport = tester.getRect(scrollView);
          _near(
            viewport.left,
            s.workspace.left,
            'full Workspace viewport start',
          );
          _near(
            viewport.right,
            s.workspace.right,
            'full Workspace viewport end',
          );
          final scrollbar = find.descendant(
            of: scrollView,
            matching: find.byType(Scrollbar),
          );
          expect(scrollbar, findsOneWidget);
          expect(tester.getRect(scrollbar), viewport);

          final covers = s.covers;
          _near(covers.first.left, s.left, 'first cover');
          final expected = desktopShelfGrid(
            s.frame(true),
            const TextScaler.linear(1),
          );
          if (_table[width.round()] case (final columns, final card)) {
            expect(expected.columns, columns);
            expect(expected.card, closeTo(card, .1));
          }
          if (width == 1920) {
            expect(s.frame(true), 1600);
            expect(expected.columns, 10);
            expect(expected.card, closeTo(142, .1));
          }
          final firstRow = covers
              .where((r) => (r.top - covers.first.top).abs() < 1)
              .toList();
          expect(firstRow.length, expected.columns);
          for (final rect in firstRow) {
            _near(rect.width, expected.card, 'card width');
            expect(rect.height / rect.width, closeTo(1.5, .01));
          }
          _near(
            firstRow.last.right - firstRow.first.left,
            expected.extent,
            'grid extent',
          );
          expect(tester.takeException(), isNull);

          // The wheel scrolls over the spare width beside the grid too.
          await tester.sendEventToBinding(
            PointerScrollEvent(
              kind: PointerDeviceKind.mouse,
              position: Offset(
                (s.left + expected.extent + s.workspace.right) / 2,
                s.workspace.center.dy,
              ),
              scrollDelta: const Offset(0, 500),
            ),
          );
          await tester.pumpAndSettle();
          expect(s.position.pixels, greaterThan(0));
          s.position.jumpTo(0);
          await tester.pumpAndSettle();

          // The list uses a narrower centered content frame, not a new viewport.
          await tester.tap(find.byTooltip(l.shelfList));
          await tester.pumpAndSettle();
          expect(s.grid, isFalse);
          expect(find.byType(SliverGrid), findsNothing);
          _near(
            tester.getRect(find.byType(DesktopShelfToolbar)).width,
            s.frame(false),
            'list toolbar width',
          );
          final listRow = tester.getRect(find.byType(ContinueReadingRow));
          _near(listRow.left, s.left, 'list continue row');
          _near(listRow.width, s.frame(false), 'list continue row width');
          final firstBook = find.byType(DesktopBookRow).first;
          final tint = tester.getRect(firstBook);
          _near(tint.left, s.left - BookListItem.inset, 'list tint bleed');
          _near(
            tint.width,
            s.frame(false) + 2 * BookListItem.inset,
            'list tint width',
          );
          final listViewport = tester.getRect(scrollView);
          _near(
            listViewport.right,
            s.workspace.right,
            'list scrollbar remains on Workspace edge',
          );
          expect(
            find.descendant(of: scrollView, matching: find.byType(Scrollbar)),
            findsOneWidget,
          );
          _near(
            tester
                .getRect(
                  find.descendant(
                    of: firstBook,
                    matching: find.byType(BookCover),
                  ),
                )
                .left,
            s.left,
            'list cover',
          );
          expect(
            tester.getSize(firstBook).height,
            greaterThanOrEqualTo(DesktopBookRow.minHeight),
          );
          expect(tester.takeException(), isNull);

          // Resizing keeps the chosen mode through the compact layout.
          for (final next in [390.0, width]) {
            tester.view.physicalSize = Size(
              next * display.dpr,
              display.size.height,
            );
            await tester.pumpAndSettle();
            expect(s.grid, isFalse);
            expect(tester.getSize(s.shelf).width, lessThanOrEqualTo(next));
            expect(tester.takeException(), isNull);
          }
          await tester.tap(find.byTooltip(l.shelfGrid));
          await tester.pumpAndSettle();
          expect(s.grid, isTrue);
          expect(find.byType(SliverGrid), findsOneWidget);
          expect(tester.takeException(), isNull);
          await s.close();
        },
        variant: windows,
      );
    }
  }

  testWidgets(
    'bounded Shelf uses Shell width and retains viewport across breakpoints',
    (tester) async {
      final h = ShellHarness(tester);
      await h.pump(
        size: const Size(1920, 720),
        shellWidth: 900,
        extraBooks: 60,
      );
      final shelf = find.byType(BookshelfView);
      final scrollView = find.descendant(
        of: shelf,
        matching: find.byType(CustomScrollView),
      );
      final workspace = h.workspace;
      final viewport = tester.element(scrollView);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: shelf, matching: find.byType(Scrollable)).first,
      );
      expect(MediaQuery.sizeOf(tester.element(shelf)).width, 1920);
      expect(tester.getRect(find.byType(DesktopShelfToolbar)).left, 72 + 24);
      expect(
        tester.getSize(find.byType(DesktopShelfToolbar)).width,
        900 - 72 - 48,
      );
      scrollable.position.jumpTo(500);
      await tester.pumpAndSettle();
      for (final width in [
        839.0,
        840.0,
        839.0,
        840.0,
        1199.0,
        1200.0,
        1199.0,
        1920.0,
      ]) {
        await h.pump(size: const Size(1920, 720), shellWidth: width);
        expect(h.workspace, same(workspace));
        expect(tester.element(scrollView), same(viewport));
        expect(
          tester.state<ScrollableState>(
            find.descendant(of: shelf, matching: find.byType(Scrollable)).first,
          ),
          same(scrollable),
        );
        expect(scrollable.position.pixels, 500);
        expect(h.shelfGrid, isTrue);
        final nav = width < 840
            ? 0.0
            : width < 1200
            ? 72.0
            : 232.0;
        final gutter = width < 1200 ? 24.0 : 32.0;
        final frame = (width - nav - 2 * gutter).clamp(0, 1600);
        final toolbar = tester.getRect(find.byType(DesktopShelfToolbar));
        expect(toolbar.left, closeTo(nav + (width - nav - frame) / 2, .01));
        expect(toolbar.width, frame);
        expect(tester.takeException(), isNull);
      }
      await h.close();
    },
    variant: windows,
  );

  testWidgets(
    'Shelf scrollbar and outer whitespace remain interactive on Workspace edge',
    (tester) async {
      final s = _Shelf(tester);
      await s.pump(size: const Size(1920, 900));
      await tester.tap(find.byTooltip(s.l.shelfList));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(
        find.descendant(of: s.shelf, matching: find.byType(CustomScrollView)),
      );
      // Well outside the centered 1200 content frame, inside full-width viewport.
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(viewport.right - 60, viewport.center.dy),
          scrollDelta: const Offset(0, 600),
        ),
      );
      await tester.pumpAndSettle();
      expect(s.position.pixels, 600);
      s.position.jumpTo(0);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: Offset(viewport.right - 4, viewport.top + 15),
      );
      await mouse.moveTo(Offset(viewport.right - 4, viewport.top + 16));
      await tester.pumpAndSettle();
      await mouse.down(Offset(viewport.right - 4, viewport.top + 16));
      await mouse.moveBy(const Offset(0, 150));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(s.position.pixels, greaterThan(0));
      await mouse.removePointer();
      await s.close();
    },
    variant: windows,
  );

  testWidgets('large text keeps covers dense and lets list rows grow', (
    tester,
  ) async {
    final s = _Shelf(tester);
    await s.pump(textScale: 1.6);
    final covers = s.covers;
    final firstRow = covers
        .where((r) => (r.top - covers.first.top).abs() < 1)
        .toList();
    expect(firstRow.length, 5);
    _near(firstRow.first.width, 180.8, 'large text card');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip(s.l.shelfList));
    await tester.pumpAndSettle();
    for (final element in find.byType(DesktopBookRow).evaluate()) {
      expect(
        tester.getSize(find.byWidget(element.widget)).height,
        greaterThan(DesktopBookRow.minHeight),
      );
    }
    expect(tester.takeException(), isNull);
    await s.close();
  }, variant: windows);

  testWidgets('no recent reading leaves out the continue row', (tester) async {
    final s = _Shelf(tester);
    await s.pump(progress: false);
    expect(find.byType(ContinueReadingRow), findsNothing);
    expect(find.text(s.l.shelfBookCount(60)), findsOneWidget);
    _near(s.covers.first.left, s.left, 'first cover');
    expect(tester.takeException(), isNull);
    await s.close();
  }, variant: windows);

  testWidgets('an empty shelf shows no count', (tester) async {
    final s = _Shelf(tester);
    await s.pump(books: 0, progress: false);
    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.text(s.l.shelfBookCount(0)), findsNothing);
    expect(find.byType(ContinueReadingRow), findsNothing);
    expect(s.grid, isTrue);
    expect(tester.takeException(), isNull);
    await s.close();
  }, variant: windows);
}
