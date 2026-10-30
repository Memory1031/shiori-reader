import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/appearance_panel.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/bookshelf/book_selection_widgets.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';

void main() {
  testWidgets(
    'mobile tabs preserve shelf state and keep import and selection in More',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 700)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.reset);
      final env = FixtureEnvironment();
      final navigation = HomeNavigation();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await env.close();
        navigation.dispose();
      });
      for (final scenario in FixtureScenario.values) {
        await env.library.putBookshelf(
          BookshelfEntry(
            snapshot: env.source.data.summary(scenario),
            addedAt: DateTime.utc(2026),
          ),
          cancellation: CancellationSource().token,
        );
      }
      var imports = 0;
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          homeBuilder: (_, _) => ReadingHome(
            repository: env.novels,
            library: env.library,
            sources: [env.source.descriptor],
            navigation: navigation,
            onImport: () => imports++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = find.byType(NavigationBar);
      final ios =
          Theme.of(tester.element(find.byType(ReadingHome))).platform ==
          TargetPlatform.iOS;
      final bottomGap = ios ? 16.0 : 34.0;
      expect(tester.getSize(bar).height, 64 + bottomGap);
      expect(
        MediaQuery.paddingOf(tester.element(find.byType(ReadingHome))).bottom,
        34,
      );
      for (final destination in find.byType(NavigationDestination).evaluate()) {
        final rect = tester.getRect(find.byWidget(destination.widget));
        expect(rect.height, greaterThanOrEqualTo(kMinInteractiveDimension));
        expect(rect.bottom, lessThanOrEqualTo(700 - bottomGap));
      }
      for (final inset in [0.0, 24.0, 48.0]) {
        tester.view.padding = FakeViewPadding(top: 47, bottom: inset);
        await tester.pumpAndSettle();
        final gap = ios ? inset.clamp(0.0, 16.0) : inset;
        expect(tester.getSize(bar).height, 64 + gap);
        for (final destination
            in find.byType(NavigationDestination).evaluate()) {
          final rect = tester.getRect(find.byWidget(destination.widget));
          expect(rect.height, greaterThanOrEqualTo(kMinInteractiveDimension));
          expect(rect.bottom, lessThanOrEqualTo(700 - gap));
        }
      }
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('List'));
      await tester.pumpAndSettle();
      final shelf = tester.element(find.byType(BookshelfView));
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const PageStorageKey('shelf-list')),
          matching: find.byType(Scrollable),
        ),
      );
      scroll.position.jumpTo(200);
      await tester.pumpAndSettle();
      final offset = scroll.position.pixels;
      await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(BookshelfView), findsNothing);
      expect(find.byType(BookshelfView, skipOffstage: false), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(BookshelfView)), same(shelf));
      expect(
        tester.widget<BookshelfView>(find.byType(BookshelfView)).layout!.value,
        isFalse,
      );
      expect(scroll.position.pixels, offset);

      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip('More'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Import book'), findsOneWidget);
      expect(find.text('Local files'), findsNothing);
      expect(find.text('App appearance'), findsNothing);
      await tester.tap(find.text('Import book'));
      await tester.pumpAndSettle();
      expect(imports, 1);
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip('More'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Multi-select'));
      await tester.pumpAndSettle();
      expect(find.byType(BookSelectionBottomBar), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BookSelectionBottomBar), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
      await tester.pumpAndSettle();
      navigation.returnToShelf();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(tester.element(find.byType(BookshelfView)), same(shelf));
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      final book = env.source.data.summary(FixtureScenario.shortChapter);
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(book.key)),
        200,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('shelf-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(find.byKey(ValueKey(book.key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(book.key)));
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  testWidgets('settings reuses appearance and updates callbacks', (
    tester,
  ) async {
    final env = FixtureEnvironment();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    });
    var updates = 0;
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        homeBuilder: (context, app) => ReadingHome(
          repository: env.novels,
          library: env.library,
          sources: const [],
          onAppearance: () => showAppAppearance(context, app),
          onUpdates: () => updates++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Local files'), findsNothing);
    expect(find.text('Offline content'), findsNothing);
    await tester.tap(find.text('App appearance'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tester.tap(find.text('About & updates'));
    await tester.pumpAndSettle();
    expect(updates, 1);
    expect(tester.takeException(), isNull);
  });
}
