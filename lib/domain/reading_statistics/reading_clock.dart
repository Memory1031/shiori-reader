import '../contracts/reading_statistics.dart';

abstract interface class ReadingClock {
  Duration get elapsed;
  DateTime get now;
}

final class SystemReadingClock implements ReadingClock {
  final _watch = Stopwatch()..start();
  @override
  Duration get elapsed => _watch.elapsed;
  @override
  DateTime get now => DateTime.now();
}

/// Settles elapsed time once, before changing any eligibility condition.
class ReadingInterval {
  ReadingInterval(this.clock) : _last = clock.elapsed, _wall = clock.now {
    _capture(_wall);
  }
  late int _day;
  late DateTime _midnight;
  void _capture(DateTime wall) {
    _day = readingDay(wall);
    _midnight =
        (wall.isUtc
                ? DateTime.utc(wall.year, wall.month, wall.day + 1)
                : DateTime(wall.year, wall.month, wall.day + 1))
            .toUtc();
    _wall = wall.toUtc();
  }

  final ReadingClock clock;
  Duration _last;
  DateTime _wall;
  Duration? _deadline;
  bool allowed = false;
  static const idle = Duration(seconds: 300);
  bool get active => allowed && _deadline != null && clock.elapsed < _deadline!;
  Duration get remaining => _deadline == null || clock.elapsed >= _deadline!
      ? Duration.zero
      : _deadline! - clock.elapsed;
  void activity() => _deadline = clock.elapsed + idle;
  void expire() => _deadline = null;

  Map<int, int> settle() {
    final end = clock.elapsed, wall = clock.now;
    final elapsed = end - _last;
    final wallDelta = wall.difference(_wall);
    final days = <int, int>{};
    // Missed active wakeups or a changed wall-clock mapping cannot prove reading.
    final uncertain =
        elapsed.isNegative ||
        allowed && elapsed > const Duration(seconds: 30) ||
        (wallDelta - elapsed).abs() > const Duration(seconds: 2);
    if (uncertain) {
      expire();
    } else if (allowed && _deadline != null) {
      final until = end < _deadline! ? end : _deadline!;
      final remaining = (until - _last).inMilliseconds;
      if (remaining > 0) {
        final room = _midnight.difference(_wall).inMilliseconds;
        final before = remaining < room ? remaining : room;
        if (before > 0) days[_day] = before;
        if (remaining > before) {
          final date = DateTime.utc(
            _day ~/ 10000,
            _day ~/ 100 % 100,
            _day % 100 + 1,
          );
          days[readingDay(date)] = remaining - before;
        }
      }
    }
    _last = end;
    _capture(wall);
    return days;
  }
}
