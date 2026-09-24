import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/page_turn.dart';
import 'package:shiori/features/reader/viewport/paper_turn.dart';

void main() {
  testWidgets('drag cancellation keeps anchor; commit waits for animation', (
    tester,
  ) async {
    final controller = PagedReaderController();
    final content = const FixtureData().content(
      FixtureScenario.extremeParagraph,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 600,
              child: PagedReaderViewport(
                content: content,
                controller: controller,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initial = controller.capture();
    final view = find.byType(PagedReaderViewport);
    final gesture = await tester.startGesture(tester.getCenter(view));
    await gesture.moveBy(const Offset(-22, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    final partial = tester.widget<PaperTurnFold>(find.byType(PaperTurnFold));
    expect(partial.progress, greaterThan(0));
    expect(partial.progress, lessThan(.28));
    expect(controller.capture(), initial);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(controller.capture(), initial);
    expect(
      tester.widget<PaperTurnFold>(find.byType(PaperTurnFold)).progress,
      0,
    );

    final next = controller.next();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.capture(), initial);
    expect(
      tester.widget<PaperTurnFold>(find.byType(PaperTurnFold)).progress,
      greaterThan(0),
    );
    await tester.pumpAndSettle();
    await next;
    expect(controller.capture(), isNot(initial));
    final previous = controller.previous();
    await tester.pumpAndSettle();
    await previous;
    expect(controller.capture(), initial);
    expect(tester.takeException(), isNull);
  });

  test(
    'fold clipping endpoints and direction expose only the intended side',
    () {
      const size = Size(360, 600);
      for (final direction in [-1, 1]) {
        expect(
          PaperTurnClipper(
            0,
            direction,
          ).getClip(size).contains(const Offset(180, 300)),
          isTrue,
        );
        expect(
          PaperTurnClipper(
            1,
            direction,
          ).getClip(size).contains(const Offset(180, 300)),
          isFalse,
        );
      }
      expect(
        const PaperTurnClipper(
          .5,
          1,
        ).getClip(size).contains(const Offset(40, 300)),
        isTrue,
      );
      expect(
        const PaperTurnClipper(
          .5,
          -1,
        ).getClip(size).contains(const Offset(40, 300)),
        isFalse,
      );
    },
  );

  test('a curl held low lifts the bottom corner further than the top', () {
    const size = Size(360, 600);
    // With a low grip the crease leans so more of the page is uncovered near
    // the bottom edge than near the top.
    final low = const PaperTurnClipper(.5, 1, grip: .8).getClip(size);
    double coveredWidth(Path clip, double y) {
      var x = 0.0;
      while (x < size.width && clip.contains(Offset(x, y))) {
        x += 1;
      }
      return x;
    }

    expect(coveredWidth(low, 20), greaterThan(coveredWidth(low, 580)));
    final high = const PaperTurnClipper(.5, 1, grip: .2).getClip(size);
    expect(coveredWidth(high, 20), lessThan(coveredWidth(high, 580)));
    expect(pageTurnGrip(0, 600), .15);
    expect(pageTurnGrip(300, 600), .5);
    expect(pageTurnGrip(600, 600), .85);
  });
}
