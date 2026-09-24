import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/reader/reader_chrome.dart';

class _FakeBattery implements Battery {
  _FakeBattery(this.level, this.state);
  final int level;
  final BatteryState state;
  @override
  Future<int> get batteryLevel async => level;
  @override
  Future<BatteryState> get batteryState async => state;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoBattery implements Battery {
  @override
  Future<int> get batteryLevel => Future.error(UnsupportedError('none'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _row(Battery battery) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(alwaysUse24HourFormat: true),
    child: Scaffold(
      body: SizedBox(
        width: 320,
        child: ReaderStatusRow(
          battery: battery,
          progress: const Text('Chapter 12%'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the clock, battery level and progress', (tester) async {
    await tester.pumpWidget(_row(_FakeBattery(82, BatteryState.discharging)));
    await tester.pump();
    expect(find.textContaining(RegExp(r'\d{1,2}:\d{2}')), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_BatteryGlyph',
      ),
      findsOneWidget,
    );
    expect(find.text('Chapter 12%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps only the clock without a readable battery', (
    tester,
  ) async {
    for (final battery in <Battery>[
      _NoBattery(),
      _FakeBattery(0, BatteryState.unknown),
    ]) {
      await tester.pumpWidget(_row(battery));
      await tester.pump();
      // Only the progress label carries a percentage.
      expect(find.textContaining('%'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_BatteryGlyph',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('advances the clock on the minute boundary', (tester) async {
    await tester.pumpWidget(_row(_FakeBattery(50, BatteryState.charging)));
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);
    // The next tick is scheduled; disposing the row cancels it.
    await tester.pump(const Duration(minutes: 1));
    expect(
      find.textContaining(RegExp(r'\d{1,2}:\d{2}'), findRichText: true),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
