import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

void main() {
  testWidgets(
    'confirmed progress is immediate and unchanged percent skips text notifications',
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
      final labelFinder = find.descendant(
        of: find.byType(ReaderBottomBar),
        matching: find.byKey(const ValueKey('reader-progress-text')),
      );
      final label = tester.widget<ValueListenableBuilder>(labelFinder);
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
      expect(notifications, 59);
      viewport.onPosition!(at(.95), false);
      await tester.pump();
      expect(find.text('Chapter 95%'), findsWidgets);
      final progressButton = find.ancestor(
        of: labelFinder,
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
