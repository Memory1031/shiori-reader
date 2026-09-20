import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paper_turn.dart';

void main() {
  testWidgets(
    'slow next chapter keeps current page until new layout is ready',
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
      // Keep the exact current page mounted throughout a slow chapter request.
      final before = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView),
      );
      env.source.controls.delays[Operation.chapter] = const Duration(
        seconds: 2,
      );
      before.onNextChapter!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<ReaderContentView>(find.byType(ReaderContentView))
            .content
            .key,
        before.content.key,
      );
      await tester.pump(const Duration(seconds: 2));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byWidgetPredicate(
          (w) => w is ReaderContentView && w.key == before.key,
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<PaperTurnFold>(find.byType(PaperTurnFold))
            .any((fold) => fold.progress > 0 && fold.progress < 1),
        isTrue,
      );
      await tester.pumpAndSettle();
      final next = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView),
      );
      expect(
        next.content.key,
        fixtureChapterKey(FixtureScenario.multiVolume, 1),
      );
      env.source.controls.delays.remove(Operation.chapter);
      next.onPreviousChapter!();
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
  );

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
      await tester.tap(find.textContaining('Chapter '));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Previous chapter'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Next chapter'));
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
      if (find.byTooltip('In-volume contents').evaluate().isEmpty) {
        await tester.tapAt(tester.getCenter(find.byType(ReaderContentView)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('In-volume contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volumes'));
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
