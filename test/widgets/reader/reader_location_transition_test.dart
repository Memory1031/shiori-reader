import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/reader/reader_location_transition.dart';

void main() {
  testWidgets(
    'location reveal preserves child state and retires without an awaited ticker',
    (tester) async {
      Future<void> mount(int revision, {bool enabled = true}) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ReaderLocationTransition(
                  revision: revision,
                  enabled: enabled,
                  paper: Colors.white,
                  child: const TextField(),
                ),
              ),
            ),
          );
      double opacity() => tester
          .widget<Opacity>(
            find.descendant(
              of: find.byType(ReaderLocationTransition),
              matching: find.byType(Opacity),
            ),
          )
          .opacity;
      await mount(0);
      final child = tester.state(find.byType(TextField));
      expect(opacity(), 1);
      await mount(1);
      await tester.pump(const Duration(milliseconds: 64));
      expect(opacity(), inExclusiveRange(.88, 1));
      expect(tester.state(find.byType(TextField)), same(child));
      await mount(1, enabled: false);
      expect(opacity(), 1);
      await mount(2, enabled: false);
      await mount(2);
      expect(opacity(), 1);
      await mount(3);
      await tester.pump(const Duration(milliseconds: 32));
      expect(opacity(), lessThan(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(opacity(), 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(opacity(), 1);
      await mount(4);
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
