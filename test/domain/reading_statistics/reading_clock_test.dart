import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/reading_statistics/reading_clock.dart';

class TestReadingClock implements ReadingClock {
  TestReadingClock([DateTime? start])
    : wall = start ?? DateTime(2026, 10, 21, 12);
  Duration ticks = Duration.zero;
  DateTime wall;
  @override
  Duration get elapsed => ticks;
  @override
  DateTime get now => wall;
  void advance(Duration d) {
    ticks += d;
    wall = wall.add(d);
  }
}

void main() {
  test('idle stops at 300 seconds and activity never backfills', () {
    final clock = TestReadingClock(), total = <int, int>{};
    final interval = ReadingInterval(clock)
      ..allowed = true
      ..activity();
    void step() {
      clock.advance(const Duration(seconds: 15));
      for (final e in interval.settle().entries) {
        total[e.key] = (total[e.key] ?? 0) + e.value;
      }
    }

    for (var i = 0; i < 24; i++) {
      step();
    }
    expect(total.values.single, 300000);
    expect(interval.active, false);
    interval.activity();
    step();
    expect(total.values.single, 315000);
  });
  test(
    'settle before pause excludes background and preserves remaining deadline',
    () {
      final clock = TestReadingClock();
      final interval = ReadingInterval(clock)
        ..allowed = true
        ..activity();
      var total = 0;
      for (var i = 0; i < 7; i++) {
        clock.advance(const Duration(seconds: 10));
        total += interval.settle().values.fold(0, (a, b) => a + b);
      }
      interval.allowed = false;
      clock.advance(const Duration(minutes: 10));
      expect(interval.settle(), isEmpty);
      interval.allowed = true;
      expect(interval.active, false);
      expect(total, 70000);
      interval.activity();
      clock.advance(const Duration(seconds: 5));
      expect(interval.settle().values.single, 5000);
    },
  );
  test('midnight uses two local days and repeated events add no time', () {
    final clock = TestReadingClock(DateTime(2026, 10, 21, 23, 59, 55));
    final interval = ReadingInterval(clock)
      ..allowed = true
      ..activity();
    clock.advance(const Duration(seconds: 10));
    expect(interval.settle(), {20261021: 5000, 20261022: 5000});
    expect(interval.settle(), isEmpty);
  });
  test('clock jumps and missed wakeups cannot create reading', () {
    final clock = TestReadingClock();
    final interval = ReadingInterval(clock)
      ..allowed = true
      ..activity();
    clock.advance(const Duration(seconds: 10));
    clock.wall = clock.wall.subtract(const Duration(hours: 1));
    expect(interval.settle(), isEmpty);
    expect(interval.active, false);
    interval.activity();
    clock.advance(const Duration(hours: 2));
    expect(interval.settle(), isEmpty);
    expect(interval.active, false);
  });
  test(
    'timezone remapping freezes old day buckets and wall jumps stop recording',
    () {
      final clock = TestReadingClock(DateTime(2026, 10, 21, 23, 59, 55));
      final interval = ReadingInterval(clock)
        ..allowed = true
        ..activity();
      clock.advance(const Duration(seconds: 5));
      final first = interval.settle();
      expect(first, {20261021: 5000});
      clock.wall = clock.wall.toUtc();
      clock.advance(const Duration(seconds: 5));
      expect(interval.settle().values.single, 5000);
      expect(first, {20261021: 5000});
      clock.wall = clock.wall.add(const Duration(days: 1));
      clock.ticks += const Duration(seconds: 5);
      expect(interval.settle(), isEmpty);
      expect(interval.active, false);
      interval.activity();
      // A platform stopwatch may stop during sleep; wall time still changes.
      clock.wall = clock.wall.add(const Duration(hours: 2));
      expect(interval.settle(), isEmpty);
      expect(interval.active, false);
    },
  );
  if (Platform.environment['TZ'] == 'America/New_York') {
    test(
      'DST 23/25-hour days keep real elapsed time and split actual midnight',
      () {
        for (final date in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
          final next = DateTime(date.year, date.month, date.day + 1);
          expect(next.difference(date).inHours, date.month == 3 ? 23 : 25);
          final clock = TestReadingClock(
            DateTime(date.year, date.month, date.day, 1, 59, 55),
          );
          final interval = ReadingInterval(clock)
            ..allowed = true
            ..activity();
          clock.advance(const Duration(seconds: 10));
          expect(interval.settle(), {
            date.year * 10000 + date.month * 100 + date.day: 10000,
          });
          clock.wall = next.subtract(const Duration(seconds: 5));
          interval.settle();
          interval.activity();
          clock.advance(const Duration(seconds: 10));
          expect(interval.settle(), {
            date.year * 10000 + date.month * 100 + date.day: 5000,
            next.year * 10000 + next.month * 100 + next.day: 5000,
          });
        }
      },
    );
  }
}
