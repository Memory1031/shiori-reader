import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

void main() {
  final content = ChapterContent(
    key: fixtureChapterKey(FixtureScenario.twentyImages),
    title: 'Buffered turns',
    blocks: [
      for (var i = 0; i < 6; i++)
        ImageBlock(media: fixtureMediaRef(i), width: 300, height: 600),
    ],
  );
  Future<void> mount(
    WidgetTester tester,
    PagedReaderController controller, {
    ValueChanged<int>? onBoundary,
    GlobalKey<NavigatorState>? navigator,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 600,
              child: PagedReaderViewport(
                content: content,
                controller: controller,
                onBoundary: onBoundary,
                imageBuilder: (_, image) =>
                    Center(child: Text(image.media.mediaId)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, {bool forward = true}) => tester.tapAt(
    tester.getTopLeft(find.byType(PagedReaderViewport)) +
        Offset(forward ? 280 : 20, 300),
  );

  testWidgets('rapid taps retain exactly one extra turn in either direction', (
    tester,
  ) async {
    final c = PagedReaderController();
    await mount(tester, c);
    await tap(tester);
    await tester.pump(const Duration(milliseconds: 80));
    for (var i = 0; i < 12; i++) {
      await tap(tester);
    }
    expect(c.capture()!.blockIndex, 0);
    await tester.pumpAndSettle();
    expect(c.capture()!.blockIndex, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(c.capture()!.blockIndex, 2);
    await tap(tester, forward: false);
    await tester.pump(const Duration(milliseconds: 80));
    for (var i = 0; i < 12; i++) {
      await tap(tester, forward: false);
    }
    await tester.pumpAndSettle();
    expect(c.capture()!.blockIndex, 0);
  });

  testWidgets(
    'reverse intent cancels buffered input without reversing active animation',
    (tester) async {
      final c = PagedReaderController();
      await mount(tester, c);
      await tap(tester);
      await tester.pump();
      await tap(tester);
      await tap(tester, forward: false);
      await tester.pumpAndSettle();
      expect(c.capture()!.blockIndex, 1);
    },
  );

  testWidgets('restore and modal navigation discard buffered turns', (
    tester,
  ) async {
    final c = PagedReaderController();
    final navigator = GlobalKey<NavigatorState>();
    await mount(tester, c, navigator: navigator);
    final initial = c.capture()!;
    await tap(tester);
    await tester.pump();
    await tap(tester);
    c.restore(initial);
    await tester.pumpAndSettle();
    expect(c.capture(), initial);
    await tap(tester);
    await tester.pump();
    await tap(tester);
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();
    expect(c.capture()!.blockIndex, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(c.capture()!.blockIndex, 1);
  });

  testWidgets(
    'drag settlement and unbuffered commands still advance only once',
    (tester) async {
      final c = PagedReaderController();
      await mount(tester, c);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PagedReaderViewport)),
      );
      await gesture.moveBy(const Offset(-22, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-150, 0));
      await tester.pump();
      await gesture.up();
      await c.next(queueIfTurning: true);
      await tester.pumpAndSettle();
      expect(c.capture()!.blockIndex, 1);
      final turn = c.next();
      await tester.pump();
      await c.next(queueIfTurning: true);
      await tester.pumpAndSettle();
      await turn;
      expect(c.capture()!.blockIndex, 2);
    },
  );

  testWidgets('buffer reaches chapter boundary only once', (tester) async {
    final c = PagedReaderController();
    final boundaries = <int>[];
    await mount(tester, c, onBoundary: boundaries.add);
    for (var i = 0; i < 4; i++) {
      final turn = c.next();
      await tester.pumpAndSettle();
      await turn;
    }
    expect(c.capture()!.blockIndex, 4);
    await tap(tester);
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tap(tester);
    }
    await tester.pumpAndSettle();
    expect(c.capture()!.blockIndex, 5);
    expect(boundaries, [1]);
  });
}
