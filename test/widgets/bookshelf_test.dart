import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/library_controller.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

void main() {
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
      find.byIcon(Icons.remove_circle_outline).evaluate().length,
      lessThan(40),
    );
    await tester.tap(find.byTooltip('Switch bookshelf layout'));
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
