import '../models/models.dart';
import 'result.dart';

int readingDay(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;
DateTime readingDate(int day) =>
    DateTime(day ~/ 10000, day ~/ 100 % 100, day % 100);

final class ReadingRecordSettings {
  const ReadingRecordSettings({
    this.enabled = true,
    this.noticeSeen = false,
    this.epoch = 0,
    this.startedDay,
  });
  final bool enabled, noticeSeen;
  final int epoch;
  final int? startedDay;
}

final class ReadingRecordSession {
  const ReadingRecordSession(
    this.id,
    this.book,
    this.epoch,
    this.removalGeneration,
  );
  final String id;
  final NovelKey book;
  final int epoch, removalGeneration;
}

final class ReadingCheckpoint {
  ReadingCheckpoint(this.session, this.sequence, Map<int, int> days)
    : days = Map.unmodifiable(days) {
    if (sequence < 1 ||
        days.isEmpty ||
        days.length > 2 ||
        days.values.any(
          (v) => v <= 0 || v > const Duration(days: 1).inMilliseconds,
        )) {
      throw ArgumentError('Invalid reading checkpoint');
    }
  }
  final ReadingRecordSession session;
  final int sequence;
  final Map<int, int> days;
}

final class ReadingBookTime {
  const ReadingBookTime(this.key, this.milliseconds, this.summary);
  final NovelKey key;
  final int milliseconds;
  final NovelSummary? summary;
}

final class ReadingStatisticsSnapshot {
  ReadingStatisticsSnapshot({
    required this.settings,
    required this.lifetime,
    required this.today,
    required Map<int, int> days,
    required Iterable<ReadingBookTime> books,
    required this.anonymous,
  }) : days = Map.unmodifiable(days),
       books = List.unmodifiable(books);
  final ReadingRecordSettings settings;
  final int lifetime, today, anonymous;
  final Map<int, int> days;
  final List<ReadingBookTime> books;
  int get total => days.values.fold(0, (a, b) => a + b);
}

abstract interface class ReadingStatisticsRepository {
  Stream<void> get changes;
  Future<Result<ReadingRecordSettings>> settings();
  Future<Result<ReadingRecordSettings>> setEnabled(bool enabled);
  Future<Result<void>> dismissNotice();
  Future<Result<ReadingRecordSettings>> clear();
  Future<Result<ReadingRecordSession?>> begin(NovelKey book);
  Future<Result<bool>> submit(ReadingCheckpoint checkpoint);
  Future<Result<void>> finish(ReadingRecordSession session);
  Future<Result<ReadingStatisticsSnapshot>> read({
    required int firstDay,
    required int lastDay,
    required int today,
  });
}
