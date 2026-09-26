import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/bookshelf/desktop_shelf.dart';
import 'package:shiori/features/home/desktop_shell.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/local_books/local_books_screen.dart';
import 'package:shiori/features/local_books/local_reparse_flow.dart';
import 'package:shiori/features/novel_detail/detail_screen.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'harness.dart';
import 'package:shiori/dev/fixtures.dart';
import 'desktop_local_books_test.dart' show rightClick, windows;
import 'package:shiori/features/local_books/desktop_local_books.dart';

void main() {
  testWidgets(
    'Local Books Detail Reader returns same filtered Workspace page across breakpoints',
    (tester) async {
      final h = LocalHarness(tester);
      final book = h.store.books.removeAt(0);
      h.store.books.insert(12, book);
      await h.pump(shell: true);
      await tester.tap(find.widgetWithText(ChoiceChip, 'EPUB 23'));
      await tester.pumpAndSettle();
      final page = tester.element(h.page),
          viewport = tester.element(h.view),
          workspace = Navigator.of(tester.element(h.page));
      // Scroll to the real local-book fixture in the middle of the filtered list.
      h.scroll.position.jumpTo(600);
      await tester.pumpAndSettle();
      final before = h.scroll.position.pixels;
      final bookRow = find.ancestor(
        of: find.text('Book'),
        matching: find.byType(DesktopLocalBookRow),
      );
      await tester.tap(
        find.descendant(of: bookRow, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(h.l.novelDetailsTitle));
      await tester.pumpAndSettle();
      final detail = tester.element(find.byType(DetailScreen));
      expect(Navigator.of(detail), same(workspace));
      expect(find.byType(ShellNavigation), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('detail-read')));
      await tester.pumpAndSettle();
      final reader = tester.element(find.byType(BookReaderScreen));
      expect(
        Navigator.of(reader),
        same(Navigator.of(reader, rootNavigator: true)),
      );
      expect(Navigator.of(reader), isNot(same(workspace)));
      expect(find.byType(ShellNavigation), findsNothing);
      for (final width in [1199.0, 1200.0, 1920.0]) {
        await h.resize(width);
        expect(tester.element(find.byType(BookReaderScreen)), same(reader));
        expect(
          tester.element(find.byType(DetailScreen, skipOffstage: false)),
          same(detail),
        );
        expect(
          tester.element(find.byType(LocalBooksScreen, skipOffstage: false)),
          same(page),
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(DetailScreen)), same(detail));
      await tester.tap(find.byKey(const ValueKey('detail-back')));
      await tester.pumpAndSettle();
      expect(tester.element(h.page), same(page));
      expect(tester.element(h.view), same(viewport));
      expect(h.scroll.position.pixels, before);
      expect(Navigator.of(tester.element(h.page)), same(workspace));
      expect(h.navigation.section, HomeSection.localBooks);
      // Direct row click uses the existing root Reader path too.
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.element(h.page), same(page));
      expect(h.scroll.position.pixels, before);
      h.scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'EPUB 23'))
            .selected,
        isTrue,
      );
      await h.close();
    },
    variant: windows,
  );
  testWidgets(
    'Shelf local-only Reparse shares flow and invalidation; reopen reads new content',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore(count: 1));
      final key = h.store.books.first.key;
      await h.library.putBookshelf(
        BookshelfEntry(
          snapshot: NovelSummary(key: key, title: 'Book'),
          addedAt: DateTime.utc(2025),
        ),
        cancellation: CancellationSource().token,
      );
      final online = h.env.source.data.summary(FixtureScenario.shortChapter);
      await h.library.putBookshelf(
        BookshelfEntry(snapshot: online, addedAt: DateTime.utc(2024)),
        cancellation: CancellationSource().token,
      );
      await h.pump(shell: true);
      final covers = tester.widget<LocalBooksScreen>(h.page).covers!;
      h.navigation.select(HomeSection.shelf);
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(tester.element(find.byType(BookshelfView)));
      final shelf = tester.element(find.byType(BookshelfView));
      await tester.tap(find.byTooltip(l.shelfList));
      await tester.pumpAndSettle();
      await rightClick(tester, tester.getCenter(find.text(online.title).first));
      expect(find.text(l.localReparse), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(DesktopBookRow),
              matching: find.text('Book'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsOneWidget);
      expect(find.textContaining('Readable revision 0'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await covers.resolve(key);
      expect(covers.contains(key), isTrue);
      final before = h.store.reads;
      await rightClick(
        tester,
        tester.getCenter(
          find
              .descendant(
                of: find.byType(DesktopBookRow),
                matching: find.text('Book'),
              )
              .first,
        ),
      );
      expect(find.text(l.localReparse), findsOneWidget);
      await tester.tap(find.text(l.localReparse));
      await tester.pumpAndSettle();
      // Menu eligibility / confirmation never read an entire manifest.
      expect(h.store.reads, before);
      await tester.tap(find.widgetWithText(FilledButton, l.localReparse));
      await tester.pumpAndSettle();
      expect(h.store.calls, hasLength(1));
      expect(find.byType(LocalReparseResultView), findsOneWidget);
      expect(find.byType(BookReaderScreen), findsNothing);
      expect(covers.contains(key), isFalse);
      await covers.resolve(key);
      expect(covers.contains(key), isTrue);
      await tester.tap(find.text(l.importDone));
      await tester.pumpAndSettle();
      expect(h.navigation.section, HomeSection.shelf);
      expect(tester.element(find.byType(BookshelfView)), same(shelf));
      await tester.tap(
        find
            .descendant(
              of: find.byType(DesktopBookRow),
              matching: find.text('Book'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsOneWidget);
      expect(find.textContaining('Readable revision 1'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await h.close();
    },
    variant: windows,
  );
}
