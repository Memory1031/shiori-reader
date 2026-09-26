import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/appearance_panel.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/bookshelf/desktop_shelf.dart';
import 'package:shiori/features/home/desktop_shell.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/novel_detail/desktop_detail.dart';
import 'package:shiori/features/novel_detail/detail_screen.dart';
import 'package:shiori/features/search/search_screen.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/widgets/shiori_logo.dart';

import 'bookshelf_test.dart' show ShelfLocalBooks;
import 'reader/continue_test.dart' show seed;
import 'reader/settings_test.dart' show Store;

final _desktop = TargetPlatformVariant.only(TargetPlatform.windows);

/// Serves details for one imported book; everything else is the fixture's.
class LocalDetails implements NovelRepository {
  LocalDetails(this.inner, this.book);
  final NovelRepository inner;
  final NovelSummary book;

  @override
  Future<Result<List<DiscoverSection>>> discover(
    SourceId sourceId, {
    required CancellationToken cancellation,
  }) => inner.discover(sourceId, cancellation: cancellation);

  @override
  Future<Result<SearchPage>> search(
    SourceId sourceId,
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) =>
      inner.search(sourceId, query, cursor: cursor, cancellation: cancellation);

  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async => key == book.key
      ? Success(
          LoadResult(
            value: NovelDetail(summary: book),
            origin: LoadOrigin.local,
            fetchedAt: DateTime.utc(2026),
          ),
        )
      : inner.loadDetail(key, mode: mode, cancellation: cancellation);

  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => inner.loadCatalog(key, mode: mode, cancellation: cancellation);

  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => inner.loadChapter(key, mode: mode, cancellation: cancellation);

  @override
  Stream<Result<LoadResult<NovelDetail>>> detailUpdates(NovelKey key) =>
      inner.detailUpdates(key);

  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      inner.catalogUpdates(key);

  @override
  Stream<Result<LoadResult<ChapterContent>>> chapterUpdates(ChapterKey key) =>
      inner.chapterUpdates(key);
}

/// A desktop home in the real app shell, with an injected navigation so
/// tests can read the selected section.
class ShellHarness {
  ShellHarness(this.tester);
  final WidgetTester tester;
  final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
  final navigation = HomeNavigation();
  var imports = 0, updateCalls = 0;

  NovelSummary get book => env.source.data.summary(FixtureScenario.multiVolume);

  Future<void> pump({
    Size size = const Size(1280, 720),
    int extraBooks = 0,
    bool onShelf = false,
    bool progress = false,
    bool updatesSection = true,
    NovelSummary? local,
    NovelRepository? repository,
    bool noSources = false,
    double? shellWidth,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final token = CancellationSource().token;
    if (onShelf) {
      await env.library.putBookshelf(
        BookshelfEntry(snapshot: book, addedAt: DateTime.utc(2026, 2, 1)),
        cancellation: token,
      );
    }
    for (var i = 0; i < extraBooks; i++) {
      await env.library.putBookshelf(
        BookshelfEntry(
          snapshot: NovelSummary(
            key: NovelKey(sourceId: SourceId('fixture'), novelId: 'extra-$i'),
            title: 'Extra book $i',
            authors: const ['Author'],
          ),
          addedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
        ),
        cancellation: token,
      );
    }
    if (local != null) {
      await env.library.putBookshelf(
        BookshelfEntry(snapshot: local, addedAt: DateTime.utc(2026, 3, 1)),
        cancellation: token,
      );
    }
    if (progress) {
      await seed(env, fixtureChapterKey(FixtureScenario.multiVolume));
    }
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        homeBuilder: (context, app) {
          final home = ReadingHome(
            repository:
                repository ??
                (local == null ? env.novels : LocalDetails(env.novels, local)),
            library: env.library,
            localManagement: local == null
                ? null
                : ShelfLocalBooks(env.library),
            sources: noSources ? [] : [env.source.descriptor],
            settings: Store()..value = ReaderSettings(controlsHintSeen: true),
            navigation: navigation,
            onAppearance: () => showAppAppearance(context, app),
            onImport: () => imports++,
            onUpdates: () => updateCalls++,
            updates: updatesSection
                ? (_) => const Scaffold(body: Text('updates page'))
                : null,
          );
          return shellWidth == null
              ? home
              : Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: shellWidth, child: home),
                );
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    navigation.dispose();
    await tester.runAsync(env.close);
  }

  AppLocalizations get l => AppLocalizations.of(
    tester.element(find.byType(DesktopShell, skipOffstage: false)),
  );

  ShellLayout get layout => tester
      .widget<ShellNavigation>(
        find.byType(ShellNavigation, skipOffstage: false),
      )
      .layout;

  NavigatorState get root =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  NavigatorState get workspace => tester.state<NavigatorState>(
    find
        .descendant(
          of: find.byType(DesktopShell, skipOffstage: false),
          matching: find.byType(Navigator, skipOffstage: false),
        )
        .first,
  );

  /// The navigation entry labelled [label], in any layout.
  Finder item(String label) => find.descendant(
    of: find.byType(ShellNavigation),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.button == true &&
          widget.properties.label == label,
    ),
  );

  FocusNode focusOf(Finder finder) => Focus.of(
    tester.element(
      find.descendant(of: finder, matching: find.byType(Icon)).first,
    ),
  );

  Future<void> select(String label) async {
    await tester.tap(item(label));
    await tester.pumpAndSettle();
  }

  Future<void> resize(double width, [double height = 720]) async {
    tester.view.physicalSize = Size(width, height);
    await tester.pumpAndSettle();
  }

  Future<void> search() async {
    await select(l.searchTitle);
    await tester.enterText(
      find.byKey(const ValueKey('search-input')),
      book.title,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-submit')));
    await tester.pumpAndSettle();
  }

  Future<void> openResult() async {
    await tester.tap(find.byKey(ValueKey(book.key)));
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsOneWidget);
  }

  /// The layout the shelf toggle shows: grid (true) or list.
  bool get shelfGrid => tester
      .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
      .selected
      .single;

  Future<void> key(LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }
}

void main() {
  test('shell layout follows the width it is given', () {
    expect(shellLayoutFor(1280), ShellLayout.sidebar);
    expect(shellLayoutFor(1200), ShellLayout.sidebar);
    expect(shellLayoutFor(1199), ShellLayout.rail);
    expect(shellLayoutFor(900), ShellLayout.rail);
    expect(shellLayoutFor(840), ShellLayout.rail);
    expect(shellLayoutFor(820), ShellLayout.bar);
  });

  testWidgets(
    'touch platforms keep the mobile home at desktop sizes',
    (tester) async {
      final h = ShellHarness(tester);
      await h.pump();
      expect(find.byType(DesktopShell), findsNothing);
      expect(find.byType(ShellNavigation), findsNothing);
      expect(find.byType(ShioriLogo), findsOneWidget);
      await h.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'iPad keeps the mobile home',
    (tester) async {
      final h = ShellHarness(tester);
      await h.pump(size: const Size(1366, 1024));
      expect(find.byType(DesktopShell), findsNothing);
      await h.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('the shelf title appears once, in the toolbar', (tester) async {
    final h = ShellHarness(tester);
    await h.pump(onShelf: true);
    expect(h.layout, ShellLayout.sidebar);
    expect(find.text(h.l.homeShelf), findsOneWidget);
    // The sidebar entry is the only other mention.
    expect(find.text(h.l.shelfTitle), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ShellNavigation),
        matching: find.text(h.l.shelfTitle),
      ),
      findsOneWidget,
    );
    await h.close();
  }, variant: _desktop);

  testWidgets('crossing breakpoints keeps the workspace and its stack', (
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
    final workspace = h.workspace;
    for (final (width, layout) in [
      (900.0, ShellLayout.rail),
      (1280.0, ShellLayout.sidebar),
      (900.0, ShellLayout.rail),
      (820.0, ShellLayout.bar),
      (1280.0, ShellLayout.sidebar),
    ]) {
      await h.resize(width);
      expect(h.layout, layout, reason: '$width');
      expect(tester.element(find.byType(DetailScreen)), same(detail));
      expect(
        tester.element(find.byType(SearchScreen, skipOffstage: false)),
        same(search),
      );
      expect(h.workspace, same(workspace));
      expect(h.navigation.section, HomeSection.search);
      expect(
        find.byType(ShioriLogo),
        layout == ShellLayout.sidebar ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsNothing);
    expect(tester.element(find.byType(SearchScreen)), same(search));
    expect(find.text(h.book.title), findsWidgets);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('search-input')))
          .controller
          ?.text,
      h.book.title,
    );
    expect(find.byKey(ValueKey(h.book.key)), findsOneWidget);
    await h.close();
  }, variant: _desktop);

  testWidgets('details open in the workspace beside the navigation', (
    tester,
  ) async {
    final h = ShellHarness(tester);
    await h.pump();
    await h.search();
    await tester.tap(find.byKey(ValueKey(h.book.key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // An ordinary push still animates: both pages are on stage.
    expect(find.byType(DetailScreen), findsOneWidget);
    expect(find.byType(SearchScreen), findsOneWidget);
    await tester.pumpAndSettle();
    expect(
      Navigator.of(tester.element(find.byType(DetailScreen))),
      same(h.workspace),
    );
    expect(find.byType(ShellNavigation), findsOneWidget);
    expect(tester.getRect(find.byType(DetailScreen)).left, closeTo(232, .01));
    await h.close();
  }, variant: _desktop);

  testWidgets('switching section drops details at once; reselecting goes '
      'to the root', (tester) async {
    final h = ShellHarness(tester);
    await h.pump();
    await h.search();
    await h.openResult();
    await tester.tap(h.item(h.l.shelfTitle));
    await tester.pump();
    // One frame, no exit transition.
    expect(find.byType(DetailScreen, skipOffstage: false), findsNothing);
    expect(find.byType(SearchScreen, skipOffstage: false), findsNothing);
    expect(find.byType(BookshelfView), findsOneWidget);
    expect(h.workspace.canPop(), isFalse);
    expect(h.navigation.section, HomeSection.shelf);
    await tester.pumpAndSettle();

    await h.search();
    await h.openResult();
    await tester.tap(h.item(h.l.searchTitle));
    await tester.pump();
    expect(find.byType(DetailScreen, skipOffstage: false), findsNothing);
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(h.workspace.canPop(), isFalse);
    expect(h.navigation.section, HomeSection.search);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await h.close();
  }, variant: _desktop);

  testWidgets('Escape leaves workspace pages from the sidebar, the page and '
      'text fields', (tester) async {
    final h = ShellHarness(tester);
    await h.pump();
    await h.search();

    // Focus in the sidebar.
    await h.openResult();
    h.focusOf(h.item(h.l.shelfTitle)).requestFocus();
    await tester.pump();
    await h.key(LogicalKeyboardKey.escape);
    expect(find.byType(DetailScreen), findsNothing);
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(h.navigation.section, HomeSection.search);

    // Focus on a button of the page.
    await h.openResult();
    final read = find.byKey(const ValueKey('detail-read'));
    Focus.of(
      tester.element(find.descendant(of: read, matching: find.byType(Text))),
    ).requestFocus();
    await tester.pump();
    await h.key(LogicalKeyboardKey.escape);
    expect(find.byType(DetailScreen), findsNothing);
    expect(primaryFocus?.context?.mounted, isTrue);
    expect(
      find.ancestor(
        of: find.byWidgetPredicate((w) => w == primaryFocus?.context?.widget),
        matching: find.byType(DetailScreen, skipOffstage: false),
      ),
      findsNothing,
    );

    // Focus in a text field: Escape leaves, Alt+← stays with the field.
    final route = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: TextField(autofocus: true)),
    );
    h.workspace.push(route);
    await tester.pumpAndSettle();
    expect(
      primaryFocus?.context?.findAncestorStateOfType<EditableTextState>(),
      isNotNull,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(route.isActive, isTrue);
    await h.key(LogicalKeyboardKey.escape);
    expect(route.isActive, isFalse);
    expect(find.byType(SearchScreen), findsOneWidget);

    // At a section's root there is nothing to leave.
    await h.key(LogicalKeyboardKey.escape);
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(h.navigation.section, HomeSection.search);
    await h.close();
  }, variant: _desktop);

  testWidgets('Alt+← and the mouse back button reuse workspace back', (
    tester,
  ) async {
    final h = ShellHarness(tester);
    await h.pump();
    await h.search();
    await h.openResult();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsNothing);

    await h.openResult();
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await mouse.down(tester.getCenter(find.byType(DetailScreen)));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsNothing);
    expect(find.byType(SearchScreen), findsOneWidget);

    // System back pops the workspace too.
    await h.openResult();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsNothing);
    expect(find.byType(SearchScreen), findsOneWidget);

    // With a dialog open the mouse back button leaves the page alone.
    await h.openResult();
    await tester.tap(h.item(h.l.appAppearance));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await mouse.down(const Offset(5, 5));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen, skipOffstage: false), findsOneWidget);
    await mouse.removePointer();
    await h.close();
  }, variant: _desktop);

  testWidgets('Escape closes only the dialog, menu or sheet on top', (
    tester,
  ) async {
    final h = ShellHarness(tester);
    await h.pump(onShelf: true);
    await h.search();
    await h.openResult();
    final detail = tester.element(find.byType(DetailScreen));

    // The appearance dialog, opened from the keyboard, returns focus to
    // its entry and leaves the section and page as they were.
    final appearance = h.focusOf(h.item(h.l.appAppearance));
    appearance.requestFocus();
    await tester.pump();
    await h.key(LogicalKeyboardKey.enter);
    expect(find.byType(Dialog), findsOneWidget);
    expect(Navigator.of(tester.element(find.byType(Dialog))), same(h.root));
    await h.key(LogicalKeyboardKey.escape);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.element(find.byType(DetailScreen)), same(detail));
    expect(h.navigation.section, HomeSection.search);
    expect(primaryFocus, same(appearance));

    // Its close button does the same.
    await tester.tap(h.item(h.l.appAppearance));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.element(find.byType(DetailScreen)), same(detail));

    // A menu of the page.
    await tester.tap(find.byKey(const ValueKey('detail-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-refresh')), findsOneWidget);
    await h.key(LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('detail-refresh')), findsNothing);
    expect(tester.element(find.byType(DetailScreen)), same(detail));

    // A book menu from the shelf opens over the window; its details open
    // in the workspace.
    await h.select(h.l.shelfTitle);
    await tester.tap(find.byTooltip(h.l.shelfList));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(h.l.moreActions));
    await tester.pumpAndSettle();
    final details = find.text(h.l.novelDetailsTitle);
    expect(details, findsOneWidget);
    expect(Navigator.of(tester.element(details)), same(h.root));
    await h.key(LogicalKeyboardKey.escape);
    expect(details, findsNothing);
    expect(find.byType(BookshelfView), findsOneWidget);
    expect(h.navigation.section, HomeSection.shelf);

    await tester.tap(find.byTooltip(h.l.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(DetailScreen))),
      same(h.workspace),
    );
    expect(find.byType(ShellNavigation), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(BookshelfView), findsOneWidget);
    await h.close();
  }, variant: _desktop);

  testWidgets('the shelf keeps its layout and scroll across sections', (
    tester,
  ) async {
    final h = ShellHarness(tester);
    await h.pump(extraBooks: 40);
    await tester.tap(find.byTooltip(h.l.shelfList));
    await tester.pumpAndSettle();
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(BookshelfView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    position().jumpTo(400);
    await tester.pumpAndSettle();

    await h.select(h.l.searchTitle);
    expect(find.byType(BookshelfView), findsNothing);
    await h.select(h.l.shelfTitle);
    expect(h.shelfGrid, isFalse);
    expect(find.byType(SliverGrid), findsNothing);
    expect(position().pixels, 400);

    // Reselecting the shelf returns to its root but keeps the choice.
    await h.select(h.l.shelfTitle);
    expect(h.shelfGrid, isFalse);
    await h.close();
  }, variant: _desktop);

  testWidgets('import, updates and appearance entries', (tester) async {
    final h = ShellHarness(tester);
    await h.pump();
    // The toolbar action; an empty shelf offers the same import again.
    await tester.tap(
      find.descendant(
        of: find.byType(DesktopShelfToolbar),
        matching: find.text(h.l.importTitle),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.imports, 1);

    await h.select(h.l.updateTitle);
    expect(h.navigation.section, HomeSection.updates);
    expect(find.text('updates page'), findsOneWidget);
    expect(h.updateCalls, 0);

    // Appearance runs over the section without selecting anything.
    await h.select(h.l.appAppearance);
    expect(find.byType(Dialog), findsOneWidget);
    expect(h.navigation.section, HomeSection.updates);
    await h.key(LogicalKeyboardKey.escape);
    expect(find.text('updates page'), findsOneWidget);

    // Selecting from outside, as the app's update prompt does.
    h.navigation.returnToShelf();
    await tester.pumpAndSettle();
    expect(find.byType(BookshelfView), findsOneWidget);
    h.navigation.select(HomeSection.updates);
    await tester.pumpAndSettle();
    expect(find.text('updates page'), findsOneWidget);
    await h.close();
  }, variant: _desktop);

  testWidgets('without an updates page the entry runs its callback', (
    tester,
  ) async {
    final h = ShellHarness(tester);
    await h.pump(updatesSection: false);
    await h.select(h.l.updateTitle);
    expect(h.updateCalls, 1);
    expect(h.navigation.section, HomeSection.shelf);
    // A section without a page falls back to the shelf.
    h.navigation.select(HomeSection.updates);
    await tester.pumpAndSettle();
    expect(find.byType(BookshelfView), findsOneWidget);
    await h.close();
  }, variant: _desktop);

  testWidgets('the home disposes only the navigation it created', (
    tester,
  ) async {
    final env = FixtureEnvironment();
    final injected = HomeNavigation();
    Widget home(HomeNavigation? navigation) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ReadingHome(
        repository: env.novels,
        library: env.library,
        sources: [env.source.descriptor],
        navigation: navigation,
      ),
    );
    await tester.pumpWidget(home(injected));
    await tester.pumpAndSettle();
    await tester.pumpWidget(home(null));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    // Still usable: the caller owns it.
    injected
      ..addListener(() {})
      ..select(HomeSection.search)
      ..dispose();
    await tester.runAsync(env.close);
  }, variant: _desktop);

  testWidgets('removing an imported book from its details returns to the '
      'section root', (tester) async {
    final h = ShellHarness(tester);
    final local = NovelSummary(
      key: LocalBookIdentity.book('b' * 64),
      title: 'Imported book',
    );
    await h.pump(local: local);
    await tester.tap(find.byTooltip(h.l.shelfList));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(h.l.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.l.novelDetailsTitle));
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsOneWidget);
    expect(h.workspace.canPop(), isTrue);
    await tester.tap(find.byKey(const ValueKey('detail-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('detail-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete book and progress'));
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen, skipOffstage: false), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BookshelfView), findsOneWidget);
    expect(find.text('Imported book'), findsNothing);
    expect(h.workspace.canPop(), isFalse);
    expect(h.navigation.section, HomeSection.shelf);
    // The list layout chosen before is kept.
    expect(h.shelfGrid, isFalse);
    expect(tester.takeException(), isNull);
    await h.close();
  }, variant: _desktop);

  testWidgets('workspace details start on the shelf toolbar edge', (
    tester,
  ) async {
    final h = ShellHarness(tester);
    await h.pump(onShelf: true);
    await tester.tap(find.byTooltip(h.l.shelfList));
    await tester.pumpAndSettle();
    for (final width in [900.0, 1280.0, 1600.0]) {
      await h.resize(width);
      final edge = (width >= 1200 ? 232 : 72) + ShioriLayout.gutter(width);
      expect(
        tester.getRect(find.text(h.l.homeShelf)).left,
        closeTo(edge, .01),
        reason: '$width',
      );
      await tester.tap(find.byTooltip(h.l.moreActions));
      await tester.pumpAndSettle();
      await tester.tap(find.text(h.l.novelDetailsTitle));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('detail-back'))).left,
        closeTo(edge, .01),
        reason: '$width',
      );
      await tester.tap(find.byKey(const ValueKey('detail-back')));
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen, skipOffstage: false), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await h.close();
  }, variant: _desktop);

  testWidgets('Escape with the details menu open closes the menu, then the '
      'page', (tester) async {
    final h = ShellHarness(tester);
    await h.pump();
    await h.search();
    await h.openResult();
    final search = tester.element(
      find.byType(SearchScreen, skipOffstage: false),
    );
    await tester.tap(find.byKey(const ValueKey('detail-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-refresh')), findsOneWidget);
    await h.key(LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('detail-refresh')), findsNothing);
    expect(find.byType(DesktopDetail), findsOneWidget);
    await h.key(LogicalKeyboardKey.escape);
    expect(find.byType(DetailScreen, skipOffstage: false), findsNothing);
    expect(tester.element(find.byType(SearchScreen)), same(search));
    expect(h.navigation.section, HomeSection.search);
    await h.close();
  }, variant: _desktop);
}
