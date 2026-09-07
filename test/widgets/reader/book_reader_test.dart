import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';

void main() {
  testWidgets(
    'cross chapter saves before switching; failure leaves previous progress; catalog chooses key',
    (tester) async {
      final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: fixtureChapterKey(FixtureScenario.multiVolume),
              repository: env.novels,
              library: env.library,
              settings: env.settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Previous chapter',
              ),
            )
            .onPressed,
        isNull,
      );
      if (find.text('Got it').evaluate().isNotEmpty) {
        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
      }
      env.source.controls.failNext(
        AppFailure(
          kind: FailureKind.network,
          operation: Operation.chapter,
          retryPolicy: RetryPolicy.manual,
        ),
      );
      await tester.tap(find.byTooltip('Next chapter'));
      await tester.pumpAndSettle();
      final saved =
          (await env.library.getProgress(
                    fixtureNovelKey(FixtureScenario.multiVolume),
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value;
      expect(saved!.chapterKey, fixtureChapterKey(FixtureScenario.multiVolume));
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaderContentView>(find.byType(ReaderContentView))
            .content
            .key,
        fixtureChapterKey(FixtureScenario.multiVolume, 1),
      );
      if (find.byTooltip('Contents').evaluate().isEmpty) {
        await tester.tap(find.byTooltip('Show reading controls'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      final target = fixtureChapterKey(FixtureScenario.multiVolume, 2);
      await tester.scrollUntilVisible(find.byKey(ValueKey(target)), 200);
      await tester.tap(find.byKey(ValueKey(target)));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaderContentView>(find.byType(ReaderContentView))
            .content
            .key,
        target,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
  );
}
