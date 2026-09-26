import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/shared/widgets/desktop_content_frame.dart';

void main() {
  test('centered content geometry keeps gutters and feature width budgets', () {
    for (final sample in [
      (828.0, 24.0, 1200.0, 780.0, 24.0),
      (1368.0, 32.0, 1200.0, 1200.0, 84.0),
      (1688.0, 32.0, 1200.0, 1200.0, 244.0),
      (1688.0, 32.0, 1600.0, 1600.0, 44.0),
      (20.0, 24.0, 1200.0, 0.0, 10.0),
    ]) {
      final geometry = desktopContentGeometry(
        availableWidth: sample.$1,
        gutter: sample.$2,
        maxWidth: sample.$3,
      );
      expect(geometry.contentWidth, sample.$4);
      expect(geometry.inset, sample.$5);
      expect(sample.$1 - geometry.inset - geometry.contentWidth, sample.$5);
    }
  });

  for (final direction in TextDirection.values) {
    testWidgets(
      'frame is physically centered with start aligned content $direction',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final width in [828.0, 1688.0]) {
          await tester.pumpWidget(
            Directionality(
              textDirection: direction,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: DesktopLayoutScope(
                    width: 900,
                    child: DesktopContentFrame(
                      maxWidth: 1200,
                      child: SizedBox(
                        key: const ValueKey('frame'),
                        height: 200,
                        child: Align(
                          alignment: AlignmentDirectional.topStart,
                          child: SizedBox(
                            key: const ValueKey('content'),
                            width: 80,
                            height: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final frame = tester.getRect(find.byKey(const ValueKey('frame')));
          final content = tester.getRect(find.byKey(const ValueKey('content')));
          expect(frame.left, width - frame.right);
          expect(frame.width, width == 828 ? 780 : 1200);
          expect(
            direction == TextDirection.ltr ? content.left : content.right,
            direction == TextDirection.ltr ? frame.left : frame.right,
          );
          expect(find.byType(Scrollable), findsNothing);
        }
      },
    );
  }

  for (final title in ['我的书架', 'My bookshelf']) {
    testWidgets(
      'toolbar slots wrap without replacing focused actions: $title',
      (tester) async {
        tester.view.physicalSize = const Size(1300, 450);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var activations = 0;
        Future<void> mount(double width, double scale) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: DesktopPageToolbar(
                      title: title,
                      leading: IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.arrow_back),
                      ),
                      secondary: const Text('12 books'),
                      actions: [
                        OutlinedButton(
                          key: const ValueKey('action'),
                          focusNode: focus,
                          onPressed: () => activations++,
                          child: const Text('Import books'),
                        ),
                        TextButton(
                          onPressed: () {},
                          child: const Text('View options'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final semantics = tester.ensureSemantics();
        await mount(1200, 1);
        final action = find.byKey(const ValueKey('action'));
        final element = tester.element(action);
        final state = tester.state(action);
        final wideTitle = tester.getRect(find.text(title));
        expect(tester.getRect(action).top, lessThan(wideTitle.bottom));
        expect(tester.getRect(action).left, greaterThan(wideTitle.right));
        expect(
          tester.getSemantics(find.text(title)).flagsCollection.isHeader,
          isTrue,
        );
        focus.requestFocus();
        await tester.pump();
        await mount(350, 2);
        expect(tester.element(action), same(element));
        expect(tester.state(action), same(state));
        expect(focus.hasFocus, isTrue);
        expect(
          tester.getRect(action).top,
          greaterThan(tester.getRect(find.text(title)).bottom),
        );
        expect(
          tester.getRect(find.byType(DesktopPageToolbar)).height,
          lessThan(450),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(action);
        expect(activations, 1);
        await mount(1200, 1);
        expect(tester.element(action), same(element));
        expect(focus.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      },
    );
  }

  testWidgets('title-only and secondary toolbars preserve full header semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final secondary in [null, const Text('12 books')]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: DesktopPageToolbar(
                  title:
                      'A very long localized page heading that wraps and truncates visually',
                  secondary: secondary,
                ),
              ),
            ),
          ),
        ),
      );
      final text = find.text(
        'A very long localized page heading that wraps and truncates visually',
      );
      expect(tester.getSemantics(text).flagsCollection.isHeader, isTrue);
      expect(tester.getRect(text).left, 0);
      expect(
        tester.getSize(find.byType(DesktopPageToolbar)).height,
        greaterThanOrEqualTo(64),
      );
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });
}
