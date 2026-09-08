import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

void main() {
  testWidgets(
    'progress label stays within 4Hz while panel uses latest position',
    (tester) async {
      final content = const FixtureData().content(
        FixtureScenario.extremeParagraph,
      );
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(home: (_) => ReaderContentView(content: content)),
        ),
      );
      await tester.pumpAndSettle();
      final label = tester.widget<ValueListenableBuilder<ReaderPosition?>>(
        find.byWidgetPredicate(
          (w) => w is ValueListenableBuilder<ReaderPosition?>,
        ),
      );
      var notifications = 0;
      void changed() => notifications++;
      label.valueListenable.addListener(changed);
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      ReaderPosition at(double fraction) => ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks.first.blockKey,
        blockIndex: 0,
        blockFraction: fraction,
        chapterFraction: fraction,
      );
      for (var i = 0; i < 600; i++) {
        viewport.onPosition!(at(i / 1000), false);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 250));
      expect(notifications, inInclusiveRange(1, 40));
      // Opening controls must not use the delayed label's value.
      viewport.onPosition!(at(.95), false);
      final progressButton = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is ValueListenableBuilder<ReaderPosition?>,
        ),
        matching: find.byType(TextButton),
      );
      await tester.tap(progressButton);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        closeTo(.95, .0001),
      );
      label.valueListenable.removeListener(changed);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    },
  );
}
