import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/dev/ui/viewport_experiment.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/dev/viewport/reader_viewport.dart';

void main() {
  testWidgets(
    'reading defaults to horizontal, mode switching preserves the semantic anchor',
    (tester) async {
      final env = FixtureEnvironment();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => ViewportExperiment(
              content: env.source.data.content(
                FixtureScenario.extremeParagraph,
              ),
              images: env.images,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PagedReaderViewport), findsOneWidget);
      await tester.tap(find.text('75%'));
      await tester.pumpAndSettle();
      final paged = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      expect(paged.controller.capture()!.blockFraction, closeTo(.75, .00001));
      await tester.tap(find.text('Scroll'));
      await tester.pumpAndSettle();
      final scroll = tester.widget<ReaderViewport>(find.byType(ReaderViewport));
      expect(scroll.controller.capture()!.blockFraction, closeTo(.75, .001));
      await tester.tap(find.text('Paged'));
      await tester.pumpAndSettle();
      final again = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      expect(again.controller.capture()!.blockFraction, closeTo(.75, .001));
      await tester.pumpWidget(const SizedBox());
      await env.close();
    },
  );
}
