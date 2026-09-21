import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'reader/continue_test.dart' show seed;
import 'bookshelf_test.dart' show RemovalCache;

void main() {
  testWidgets('continue reading can open details without stacking readers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
    await seed(env, fixtureChapterKey(FixtureScenario.multiVolume));
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => ReadingHome(
            repository: env.novels,
            library: env.library,
            sources: [env.source.descriptor],
            settings: env.settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    for (var cycle = 0; cycle < 2; cycle++) {
      expect(find.byType(ReaderContentView), findsOneWidget);
      if (find.text('Got it').evaluate().isNotEmpty) {
        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
      }
      if (find.byTooltip('More').evaluate().isEmpty) {
        await tester.tapAt(tester.getCenter(find.byType(ReaderContentView)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novel details'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderContentView, skipOffstage: false), findsNothing);
      expect(find.text('Add to bookshelf'), findsOneWidget);
      if (cycle == 0) {
        await tester.ensureVisible(find.byKey(const ValueKey('detail-read')));
        await tester.tap(find.byKey(const ValueKey('detail-read')));
        await tester.pumpAndSettle();
      }
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Your bookshelf is empty.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(env.close);
  });

  testWidgets(
    'detail removal reflects on shelf without undo; history clears independently',
    (tester) async {
      final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
      final cache = RemovalCache();
      final summary = env.source.data.summary(FixtureScenario.multiVolume);
      await env.library.putBookshelf(
        BookshelfEntry(snapshot: summary, addedAt: DateTime.now()),
        cancellation: CancellationSource().token,
      );
      await seed(env, fixtureChapterKey(FixtureScenario.multiVolume));
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => ReadingHome(
              cache: cache,
              repository: env.novels,
              library: env.library,
              sources: [env.source.descriptor],
              settings: env.settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text(summary.title).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novel details'));
      await tester.pumpAndSettle();
      expect(find.text('In bookshelf'), findsOneWidget);
      expect(find.text('Remove from bookshelf'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('detail-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from bookshelf'));
      await tester.pumpAndSettle();
      expect(find.text('Add to bookshelf'), findsOneWidget);
      expect(cache.cleared, [summary.key]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Your bookshelf is empty.'), findsOneWidget);
      expect(find.text('Undo removal'), findsNothing);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recent reading'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear this reading history'));
      await tester.pumpAndSettle();
      expect(find.text('No reading history yet.'), findsOneWidget);
      await tester.runAsync(() async {
        expect(
          (await env.library.watchBookshelf().first
                  as Success<List<BookshelfEntry>>)
              .value
              .length,
          0,
        );
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(env.close);
    },
  );
}
