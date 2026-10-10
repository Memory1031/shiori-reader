import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/local_books/local_books_screen.dart';
import 'package:shiori/features/local_books/local_reparse_flow.dart';
import 'package:shiori/features/bookshelf/book_selection_widgets.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

import 'local_books/harness.dart';

void main() {
  testWidgets(
    'legacy reparse all holds the shared maintenance lane through Stop and results',
    (tester) async {
      final store = LocalStore(count: 2)
        ..gate = Completer<Result<LocalReparseResult>>();
      final h = LocalHarness(tester, store: store);
      await h.pump(width: 390, height: 844, shell: true);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local files'));
      await tester.pumpAndSettle();
      final actions = tester
          .widget<BookSelectionScope>(
            find.descendant(
              of: h.page,
              matching: find.byType(BookSelectionScope),
            ),
          )
          .actions;
      final enter = tester
          .widget<IconButton>(find.byKey(const ValueKey('book-multi-select')))
          .onPressed!;
      await tester.tap(find.byKey(const ValueKey('local-books-reparse-all')));
      await tester.pumpAndSettle();
      expect(store.calls, isEmpty);
      expect(h.importer.maintenanceBlocked, isTrue);
      await tester.tap(find.widgetWithText(FilledButton, h.l.localReparseAll));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.calls, hasLength(1));
      expect(actions.library.writing, isTrue);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('book-multi-select')))
            .onPressed,
        isNull,
      );
      enter();
      expect(actions.selection.active, isFalse);

      // Even a retained selection and direct action calls cannot bypass the lease.
      actions.selection.enter();
      actions.selection.toggleAll();
      await actions.reparseSelected(tester.element(h.page));
      await actions.removeSelected(tester.element(h.page));
      await tester.pump();
      expect(store.calls, hasLength(1));
      expect(store.deletes, 0);
      expect(find.byType(AlertDialog), findsNothing);
      actions.leave();
      await tester.pump();

      await tester.tap(find.text(h.l.localReparseStop));
      await tester.pump();
      expect(store.calls.single.token.isCancelled, isTrue);
      expect(actions.library.writing, isTrue);
      expect(h.importer.maintenanceBlocked, isTrue);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      store.gate!.complete(Success(LocalReparseResult(approximate: false)));
      await tester.pumpAndSettle();
      expect(store.calls, hasLength(1));
      expect(find.byType(LocalReparseResultView), findsOneWidget);
      expect(find.text(h.l.localReparseAllSummary(1, 0, 1)), findsOneWidget);
      expect(actions.library.writing, isTrue);
      enter();
      expect(actions.selection.active, isFalse);
      await tester.tap(find.widgetWithText(TextButton, h.l.importDone));
      await tester.pumpAndSettle();
      expect(actions.library.writing, isFalse);
      expect(h.importer.maintenanceBlocked, isFalse);

      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-selection-reparse')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, h.l.bookReparseSelected(1)),
      );
      await tester.pumpAndSettle();
      expect(store.calls.map((call) => call.key), [
        store.books.first.key,
        store.books.first.key,
      ]);
      expect(find.text(h.l.bookBatchSummary(1, 0, 0, 0, 0)), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, h.l.importDone));
      await tester.pumpAndSettle();
      expect(actions.library.writing, isFalse);
      await h.close();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'legacy single reparse releases the shared lease when confirmation is cancelled',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore(count: 1));
      await h.pump(width: 390, height: 844, shell: true);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local files'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey(('local-book-reparse', h.store.books.first.key))),
      );
      await tester.pumpAndSettle();
      expect(h.importer.maintenanceBlocked, isTrue);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('book-multi-select')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(TextButton, h.l.importCancel));
      await tester.pumpAndSettle();
      expect(h.store.calls, isEmpty);
      expect(h.importer.maintenanceBlocked, isFalse);
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('book-selection-exit')), findsOneWidget);
      await h.close();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'leaving legacy reparse cancels remaining books and holds the lease until unwind',
    (tester) async {
      final store = LocalStore(count: 2)
        ..gate = Completer<Result<LocalReparseResult>>();
      final h = LocalHarness(tester, store: store);
      await h.pump(width: 390, height: 844, shell: true);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local files'));
      await tester.pumpAndSettle();
      final library = tester
          .widget<LocalBooksScreen>(h.page)
          .libraryController!;
      await tester.tap(find.byKey(const ValueKey('local-books-reparse-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, h.l.localReparseAll));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.calls, hasLength(1));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(h.page, findsNothing);
      expect(store.calls.single.token.isCancelled, isTrue);
      expect(library.writing, isTrue);
      expect(h.importer.maintenanceBlocked, isTrue);
      store.gate!.complete(Success(LocalReparseResult(approximate: false)));
      await tester.pumpAndSettle();
      expect(store.calls, hasLength(1));
      expect(library.writing, isFalse);
      expect(h.importer.maintenanceBlocked, isFalse);
      expect(find.byType(LocalReparseResultView), findsNothing);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local files'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('book-selection-exit')), findsOneWidget);
      await h.close();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'Workspace batch keeps OS import overlay deferred through confirmation and results',
    (tester) async {
      final store = LocalStore(count: 2)
        ..gate = Completer<Result<LocalReparseResult>>();
      final h = LocalHarness(tester, store: store);
      await h.pump(width: 1280, shell: true);
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-selection-reparse')));
      await tester.pumpAndSettle();
      expect(store.calls, isEmpty);
      expect(h.importer.maintenanceBlocked, isTrue);
      h.source.receive(id: 'during-maintenance');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('import-dismiss-barrier')),
        findsNothing,
      );
      expect(h.source.inbox, hasLength(1));
      await tester.tap(
        find.widgetWithText(FilledButton, 'Reparse selected (1)'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.calls.map((call) => call.key), [store.books.first.key]);
      expect(
        find.byKey(const ValueKey('import-dismiss-barrier')),
        findsNothing,
      );
      store.gate!.complete(Success(LocalReparseResult(approximate: false)));
      await tester.pumpAndSettle();
      expect(find.text(h.l.bookBatchSummary(1, 0, 0, 0, 0)), findsOneWidget);
      expect(h.importer.maintenanceBlocked, isTrue);
      expect(h.source.acked, isEmpty);
      expect(
        find.byKey(const ValueKey('import-dismiss-barrier')),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(TextButton, h.l.importDone));
      await tester.pumpAndSettle();
      expect(h.importer.maintenanceBlocked, isFalse);
      expect(
        find.byKey(const ValueKey('import-dismiss-barrier')),
        findsOneWidget,
      );
      expect(h.source.acked, isEmpty);
      expect(h.source.inbox, hasLength(1));
      expect(h.importer.busy, isFalse);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('book-multi-select')),
            )
            .onPressed,
        isNotNull,
      );
      await h.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'Windows Workspace reselection clears local selection and keeps its scroll position',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore(count: 35));
      await h.pump(width: 1280, shell: true);
      await tester.drag(h.view, const Offset(0, -400));
      await tester.pumpAndSettle();
      final offset = h.scroll.position.pixels;
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-selection-all')));
      await tester.pumpAndSettle();
      expect(find.text(h.l.bookSelectedCount(35)), findsOneWidget);
      h.navigation.select(HomeSection.localBooks);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('book-selection-exit')), findsNothing);
      expect(h.scroll.position.pixels, closeTo(offset, 1));
      await h.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets(
    'mobile home more entry starts empty and shares count with shelf',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore(count: 4));
      for (final info in h.store.books) {
        await h.library.putBookshelf(
          BookshelfEntry(
            snapshot: NovelSummary(key: info.key, title: info.title),
            addedAt: info.importedAt,
          ),
          cancellation: CancellationSource().token,
        );
      }
      await h.pump(width: 390, height: 844, shell: true);
      h.navigation.select(HomeSection.shelf);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Multi-select'));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('book-selection-exit')));
      await tester.pumpAndSettle();
      final shelf = tester.widget<BookshelfView>(find.byType(BookshelfView));
      expect(shelf.batchActions!.selection.active, isFalse);
      await h.close();
    },
  );

  testWidgets(
    'local all includes offscreen; filter reconciles; failed watch preserves keys; import is not auto-selected',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore(count: 30));
      await h.pump(width: 390, height: 844);
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-selection-all')));
      await tester.pumpAndSettle();
      expect(find.text('30 selected'), findsOneWidget);
      await tester.tap(find.text('TXT 15'));
      await tester.pumpAndSettle();
      expect(find.text('15 selected'), findsOneWidget);
      h.store.updates.add(
        Failure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.libraryRead,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('15 selected'), findsOneWidget);
      final newBook = LocalBookInfo(
        key: LocalBookIdentity.book('f' * 64),
        title: 'New import',
        format: LocalBookFormat.txt,
        importedAt: DateTime.utc(2026),
      );
      h.store.books.add(newBook);
      h.store.updates.add(Success(List.of(h.store.books)));
      await tester.pumpAndSettle();
      expect(find.text('15 selected'), findsOneWidget);
      await tester.tap(find.text('All 31'));
      await tester.pumpAndSettle();
      expect(find.text('15 selected'), findsOneWidget);
      await h.close();
    },
  );

  for (final lang in ['en', 'zh']) {
    testWidgets(
      'local selection 2x $lang safe bottom and last row remain reachable',
      (tester) async {
        final h = LocalHarness(tester, store: LocalStore(count: 12));
        await h.pump(width: 390, height: 844, scale: 2, lang: lang);
        await tester.tap(find.byKey(const ValueKey('book-multi-select')));
        await tester.pumpAndSettle();
        final last = h.store.books.last;
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(last.key)),
          500,
          scrollable: find
              .descendant(of: h.view, matching: find.byType(Scrollable))
              .first,
        );
        await tester.ensureVisible(find.byKey(ValueKey(last.key)));
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byKey(ValueKey(last.key)));
        expect(
          rect.bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byType(BookSelectionBottomBar)).top + 1,
          ),
        );
        await tester.tap(find.text(last.title));
        await tester.pumpAndSettle();
        expect(find.text(h.l.bookSelectedCount(1)), findsOneWidget);
        expect(h.reads, 0);
        expect(tester.takeException(), isNull);
        await h.close();
      },
    );
  }

  testWidgets(
    'Cupertino selection disables route swipe; explicit cancel restores ordinary back',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = LocalStore(count: 2), library = FixtureLibraryRepository();
      late CupertinoPageRoute<void> page;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  page = CupertinoPageRoute(
                    builder: (_) => LocalBooksScreen(
                      store: store,
                      management: store,
                      library: library,
                      onRead: (_) {},
                      onImport: () {},
                    ),
                  );
                  Navigator.of(context).push(page);
                },
                child: const Text('Open local'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open local'));
      await tester.pumpAndSettle();
      expect(page.popGestureEnabled, isTrue);
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      expect(page.popGestureEnabled, isFalse);
      await tester.dragFrom(const Offset(1, 400), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(find.byType(LocalBooksScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('book-selection-exit')));
      await tester.pumpAndSettle();
      expect(page.popGestureEnabled, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Open local'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await store.close();
        await library.close();
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'local selection entry selects nothing; row toggles without read',
    (tester) async {
      final h = LocalHarness(tester, store: LocalStore(count: 4));
      await h.pump(width: 390, height: 844);
      final readsBefore = h.store.reads;
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(h.reads, 0);
      expect(h.store.reads, readsBefore);
      await h.close();
    },
  );
}
