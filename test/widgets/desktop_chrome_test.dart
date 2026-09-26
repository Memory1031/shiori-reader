import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/bookshelf/desktop_shelf.dart';
import 'package:shiori/features/home/desktop_shell.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/novel_detail/detail_sections.dart';
import 'package:shiori/features/search/search_screen.dart';
import 'package:shiori/features/updates/update_controller.dart';
import 'package:shiori/features/updates/update_screen.dart';
import 'package:shiori/shared/widgets/desktop_content_frame.dart';
import 'local_books/harness.dart';
import 'cache/harness.dart' show DesktopCache;
import 'desktop_shell_test.dart' show ShellHarness;
import '../support/fake_update_repository.dart';

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  for (final bounded in [false, true]) {
    testWidgets(
      'real Workspace shares chrome across all pages, bounded=$bounded',
      (tester) async {
        final updates = UpdateController(FakeUpdateRepository());
        await updates.initialize();
        addTearDown(() async {
          await updates.shutdown();
          updates.dispose();
        });
        final h = LocalHarness(
          tester,
          cache: DesktopCache(),
          updates: (_) =>
              UpdateScreen(controller: updates, openPage: (_) async => true),
        );
        final book = h.env.source.data.summary(FixtureScenario.shortChapter);
        await h.library.putBookshelf(
          BookshelfEntry(snapshot: book, addedAt: DateTime.utc(2026)),
          cancellation: CancellationSource().token,
        );
        await h.pump(width: 1920, shell: true, bounded: bounded ? 900 : null);
        final workspace = tester.state<NavigatorState>(
          find
              .descendant(
                of: find.byType(DesktopShell),
                matching: find.byType(Navigator),
              )
              .first,
        );
        final rects = <Rect>[];
        final titles = <double>[];
        Rect chrome() => tester.getRect(find.byType(DesktopPageToolbar));
        void record() {
          final bar = tester.widget<DesktopPageToolbar>(
            find.byType(DesktopPageToolbar),
          );
          rects.add(chrome());
          titles.add(
            tester
                .getRect(
                  find.descendant(
                    of: find.byType(DesktopPageToolbar),
                    matching: find.text(bar.title),
                  ),
                )
                .left,
          );
        }

        final strings = h.l;
        Future<void> section(HomeSection value, String label) async {
          await tester.tap(
            find.descendant(
              of: find.byType(ShellNavigation),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Semantics &&
                    w.properties.button == true &&
                    w.properties.label == label,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(h.navigation.section, value);
        }

        await section(HomeSection.shelf, strings.shelfTitle);
        record();
        final gridPadding = tester
            .widget<SliverPadding>(
              find
                  .ancestor(
                    of: find.byType(SliverGrid),
                    matching: find.byType(SliverPadding),
                  )
                  .last,
            )
            .padding
            .resolve(TextDirection.ltr);
        final gridView = tester.getRect(
          find.descendant(
            of: find.byType(BookshelfView),
            matching: find.byType(CustomScrollView),
          ),
        );
        final gridWidth = gridView.width - gridPadding.horizontal;
        await section(HomeSection.search, strings.searchTitle);
        record();
        await tester.enterText(
          find.byKey(const ValueKey('search-input')),
          book.title,
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('search-submit')));
        await tester.pumpAndSettle();
        final result = tester.getRect(find.byKey(ValueKey(book.key)));
        final searchView = tester.getRect(find.byType(CustomScrollView));
        expect(
          tester.getRect(find.byKey(const ValueKey('search-input'))).center.dx,
          result.center.dx,
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('search-input'))).width,
          result.width,
        );
        expect(searchView.width, gridView.width);
        await section(HomeSection.localBooks, strings.localBooksTitle);
        record();
        final local = tester.getRect(
          find.byKey(const ValueKey('local-library-summary')),
        );
        await section(HomeSection.offline, strings.cacheTitle);
        record();
        final cache = tester.getRect(
          find.byKey(const ValueKey('cache-storage')),
        );
        await section(HomeSection.updates, strings.updateTitle);
        record();
        final updateContent = tester.getRect(
          find.byKey(const ValueKey('update-channel')),
        );
        expect(updateContent.width, 640);
        expect(updateContent.width, lessThan(chrome().width));
        expect(updateContent.center.dx, chrome().center.dx);
        await section(HomeSection.search, strings.searchTitle);
        await tester.enterText(
          find.byKey(const ValueKey('search-input')),
          book.title,
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('search-submit')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(book.key)));
        await tester.pumpAndSettle();
        rects.add(chrome());
        expect(workspace.canPop(), isTrue);
        final cover = tester.getRect(find.byType(DetailCover));
        final info = tester.getRect(find.byType(DetailBookInfo));
        for (final rect in rects) {
          expect(rect.left, rects.first.left);
          expect(rect.right, rects.first.right);
          expect(rect.width, rects.first.width);
        }
        expect(titles.toSet().length, 1);
        final nav = bounded ? 72.0 : 232.0;
        final gutter = bounded ? 24.0 : 32.0;
        expect(rects.first.left, nav + gutter);
        expect(rects.first.right, (bounded ? 900 : 1920) - gutter);
        if (!bounded) {
          expect(gridWidth, 1600);
          expect(local.width, 1200);
          expect(result.width, 1200);
          expect(cache.width, 760);
          expect(info.right - cover.left, 1040);
          expect(cache.center.dx, local.center.dx);
          expect(cache.left, greaterThan(local.left));
          expect(rects.first.width, 1624);
        }
        expect(tester.takeException(), isNull);
        await h.close();
      },
      variant: _windows,
    );
  }

  testWidgets(
    'Shelf grid list grid keeps chrome actions and independent stored offsets',
    (tester) async {
      final h = ShellHarness(tester);
      await h.pump(size: const Size(1920, 720), onShelf: true, extraBooks: 80);
      final bar = tester.getRect(find.byType(DesktopPageToolbar));
      final title = tester.getRect(find.text(h.l.homeShelf));
      final toggle = tester.getRect(find.byType(ShelfLayoutToggle));
      final import = tester.getRect(
        find.descendant(
          of: find.byType(DesktopShelfToolbar),
          matching: find.byType(OutlinedButton),
        ),
      );
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
      void fixed() {
        expect(tester.getRect(find.byType(DesktopPageToolbar)), bar);
        expect(tester.getRect(find.text(h.l.homeShelf)), title);
        expect(tester.getRect(find.byType(ShelfLayoutToggle)), toggle);
        expect(
          tester.getRect(
            find.descendant(
              of: find.byType(DesktopShelfToolbar),
              matching: find.byType(OutlinedButton),
            ),
          ),
          import,
        );
      }

      position().jumpTo(500);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(h.l.shelfList));
      await tester.pumpAndSettle();
      fixed();
      expect(tester.getSize(find.byType(DesktopBookRow).first).width, 1200);
      position().jumpTo(300);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(h.l.shelfGrid));
      await tester.pumpAndSettle();
      fixed();
      expect(position().pixels, 500);
      await tester.tap(find.byTooltip(h.l.shelfList));
      await tester.pumpAndSettle();
      fixed();
      expect(position().pixels, 300);
      await h.close();
    },
    variant: _windows,
  );

  testWidgets(
    'SearchUnavailable shares Search chrome without a controller',
    (tester) async {
      final h = ShellHarness(tester);
      await h.pump(size: const Size(1920, 720));
      await h.select(h.l.searchTitle);
      final rect = tester.getRect(find.byType(DesktopPageToolbar));
      Finder titleFinder() => find.descendant(
        of: find.byType(DesktopPageToolbar),
        matching: find.text(h.l.searchTitle),
      );
      final title = tester.getRect(titleFinder());
      await h.pump(size: const Size(1920, 720), noSources: true);
      expect(find.byType(SearchUnavailable), findsOneWidget);
      expect(find.byType(SearchScreen), findsNothing);
      expect(tester.getRect(find.byType(DesktopPageToolbar)), rect);
      expect(tester.getRect(titleFinder()), title);
      await h.close();
    },
    variant: _windows,
  );
}
