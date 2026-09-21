import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/home/continue_reading_card.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

import 'book_progress_test.dart' show seed;

void main() {
  for (final language in ['zh', 'en']) {
    for (final snapshot in [
      null,
      BookProgressSnapshot(fraction: .36, chapterCount: 120),
      BookProgressSnapshot(
        fraction: 1,
        chapterCount: 120,
        terminal: BookTerminalState.caughtUp,
      ),
    ]) {
      testWidgets(
        'continue card on narrow large-text home: $language ${snapshot?.terminal}',
        (tester) async {
          tester.view
            ..physicalSize = const Size(320, 640)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final env = FixtureEnvironment();
          await seed(
            env.library,
            env.source.data.summary(FixtureScenario.longTitle),
            snapshot,
          );
          Widget app(Widget child) => MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: appTheme(
              language == 'zh' ? Brightness.light : Brightness.dark,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: child,
          );
          await tester.pumpWidget(
            app(
              ReadingHome(
                repository: env.novels,
                library: env.library,
                sources: [env.source.descriptor],
              ),
            ),
          );
          await tester.pumpAndSettle();
          final card = find.byType(ContinueReadingCard);
          expect(card, findsOneWidget);
          expect(
            tester.getSize(find.byType(BookshelfView)).height,
            greaterThan(0),
          );
          expect(tester.takeException(), isNull);
          expect(env.source.controls.calls, isEmpty);
          final bars = find.descendant(
            of: card,
            matching: find.byType(LinearProgressIndicator),
          );
          if (snapshot == null) {
            expect(bars, findsNothing);
          } else {
            expect(
              tester.widget<LinearProgressIndicator>(bars).value,
              snapshot.fraction,
            );
          }
          final strings = AppLocalizations.of(tester.element(card));
          if (snapshot?.terminal == BookTerminalState.caughtUp) {
            expect(find.text(strings.bookCaughtUp), findsOneWidget);
          }

          final progress = tester.widget<ContinueReadingCard>(card).progress;
          var opens = 0;
          await tester.pumpWidget(
            app(
              Scaffold(
                body: ContinueReadingCard(
                  progress: progress,
                  onContinue: () => opens++,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final button = find.widgetWithText(
            TextButton,
            strings.homeContinueAction,
          );
          expect(button, findsOneWidget);
          await tester.tap(button);
          await tester.pumpAndSettle();
          await tester.tap(find.text(progress.snapshot.title));
          await tester.pumpAndSettle();
          expect(opens, 2);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(env.close);
        },
      );
    }
  }
}
