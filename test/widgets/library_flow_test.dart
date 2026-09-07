import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'reader/continue_test.dart' show seed;

void main() {
  testWidgets(
    'detail removal reflects on shelf; undo and history clearing have separate boundaries',
    (tester) async {
      final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
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
              repository: env.novels,
              library: env.library,
              sources: [env.source.descriptor],
              settings: env.settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(summary.title).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remove from bookshelf'));
      await tester.tap(find.text('Remove from bookshelf'));
      await tester.pumpAndSettle();
      expect(find.text('Add to bookshelf'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Your bookshelf is empty.'), findsOneWidget);
      await tester.tap(find.text('Undo removal'));
      await tester.pumpAndSettle();
      expect(find.text('Your bookshelf is empty.'), findsNothing);
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
          1,
        );
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(env.close);
    },
  );
}
