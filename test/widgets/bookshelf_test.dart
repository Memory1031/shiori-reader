import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/library_controller.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'grid taps read, long press offers details; swipe reveals actions without removing',
    (tester) async {
      final repo = FixtureLibraryRepository();
      final c = LibraryController(repo)..onStart();
      final book = const FixtureData().summary(FixtureScenario.shortChapter);
      await c.add(book);
      var reads = 0, details = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => BookshelfView(
                controller: c,
                onOpen: (_) => reads++,
                onDetails: (_) => details++,
                onSearch: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(book.key)));
      expect(reads, 1);
      await tester.longPress(find.byKey(ValueKey(book.key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novel details'));
      await tester.pumpAndSettle();
      expect(details, 1);
      await tester.tap(find.byTooltip('List'));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(ValueKey(book.key)), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(c.books.length, 1);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(details, 2);
      await tester.drag(find.byKey(ValueKey(book.key)), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(c.books, isEmpty);
      await tester.tap(find.text('Undo removal'));
      await tester.pumpAndSettle();
      expect(c.books.length, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        c.onDelete();
        await c.resourcesReleased;
        c.dispose();
        await repo.close();
      });
    },
  );
  test(
    'add is idempotent; remove undo and failed write preserve state',
    () async {
      final repo = FixtureLibraryRepository();
      final c = LibraryController(repo)..onStart();
      final book = const FixtureData().summary(FixtureScenario.shortChapter);
      await c.add(book);
      await c.add(book);
      await Future<void>.delayed(Duration.zero);
      expect(c.books.length, 1);
      await c.remove(book.key);
      await Future<void>.delayed(Duration.zero);
      expect(c.books, isEmpty);
      await c.undo();
      await Future<void>.delayed(Duration.zero);
      expect(c.books.single.snapshot, book);
      repo.controls.failNext(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.libraryWrite,
        ),
      );
      expect(await c.remove(book.key), isFalse);
      expect(c.writeFailure, isNotNull);
      expect(c.books.length, 1);
      c.onDelete();
      await c.resourcesReleased;
      c.dispose();
      await repo.close();
    },
  );
  testWidgets('500 book grid is lazy and large text layout toggles', (
    tester,
  ) async {
    final repo = FixtureLibraryRepository();
    final c = LibraryController(repo)..onStart();
    await tester.runAsync(() async {
      for (var i = 0; i < 500; i++) {
        await c.add(
          NovelSummary(
            key: NovelKey(sourceId: SourceId('fixture'), novelId: '$i'),
            title: 'Book $i',
          ),
        );
      }
    });
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: BookshelfView(controller: c, onOpen: (_) {}, onSearch: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Book ').evaluate().length,
      inInclusiveRange(1, 39),
    );
    await tester.tap(find.byTooltip('List'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      c.onDelete();
      await c.resourcesReleased;
      c.dispose();
      await repo.close();
    });
  });
}
