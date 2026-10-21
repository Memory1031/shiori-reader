import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/reading_statistics_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/statistics/reading_statistics_controller.dart';
import '../../domain/reading_statistics/reading_clock_test.dart'
    show TestReadingClock;

final key = NovelKey(sourceId: SourceId('source'), novelId: 'book');
final other = NovelKey(sourceId: SourceId('source'), novelId: 'other');
T ok<T>(Result<T> r) => (r as Success<T>).value;

class LostAck extends LocalReadingStatisticsRepository {
  LostAck(super.db);
  final committed = Completer<void>(), release = Completer<void>();
  bool first = true;
  final seen = <ReadingCheckpoint>[];
  @override
  Future<Result<bool>> submit(ReadingCheckpoint checkpoint) async {
    seen.add(checkpoint);
    final result = await super.submit(checkpoint);
    if (first) {
      first = false;
      committed.complete();
      await release.future;
      return Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.libraryWrite,
        ),
      );
    }
    return result;
  }
}

class GateSubmit extends LocalReadingStatisticsRepository {
  GateSubmit(super.db);
  final entered = Completer<void>(), release = Completer<void>();
  bool first = true;
  @override
  Future<Result<bool>> submit(ReadingCheckpoint checkpoint) async {
    if (first) {
      first = false;
      entered.complete();
      await release.future;
    }
    return super.submit(checkpoint);
  }
}

class GateBegin extends LocalReadingStatisticsRepository {
  GateBegin(super.db);
  final entered = Completer<void>(), release = Completer<void>();
  int calls = 0;
  @override
  Future<Result<ReadingRecordSession?>> begin(NovelKey book) async {
    if (++calls == 2) {
      entered.complete();
      await release.future;
    }
    return super.begin(book);
  }
}

void main() {
  late UserDatabase db;
  late LocalReadingStatisticsRepository repo;
  late TestReadingClock clock;
  late ReadingStatisticsController recorder;
  setUp(() {
    db = UserDatabase(NativeDatabase.memory());
    repo = LocalReadingStatisticsRepository(db);
    clock = TestReadingClock();
    recorder = ReadingStatisticsController(repo, clock: clock, schedule: false);
  });
  tearDown(() async {
    await recorder.close();
    recorder.dispose();
    await db.close();
  });
  Future<void> open(Object owner, NovelKey book) async {
    await recorder.ready;
    recorder.source(owner, book, visible: true, activity: true);
    if (recorder.recording || recorder.failure != null) return;
    final ready = Completer<void>();
    void changed() {
      if (!ready.isCompleted &&
          (recorder.recording || recorder.failure != null)) {
        ready.complete();
      }
    }

    recorder.addListener(changed);
    try {
      changed();
      await ready.future.timeout(const Duration(seconds: 2));
    } finally {
      recorder.removeListener(changed);
    }
  }

  Future<int> total() async => ok(
    await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
  ).total;
  test(
    'known 40-second focus pause preserves the original idle deadline',
    () async {
      await open(Object(), key);
      clock.advance(const Duration(seconds: 10));
      recorder.environment(focused: false);
      clock.advance(const Duration(seconds: 40));
      recorder.environment(focused: true);
      expect(recorder.recording, true);
      clock.advance(const Duration(seconds: 15));
      await recorder.tick();
      expect(await total(), 25000);
      expect(recorder.interval.remaining, const Duration(seconds: 235));
    },
  );
  test(
    'multiple visible surfaces count once and background preserves deadline',
    () async {
      final main = Object(), footnote = Object();
      await open(main, key);
      clock.advance(const Duration(seconds: 10));
      recorder.source(main, key, visible: false);
      await open(footnote, key);
      clock.advance(const Duration(seconds: 10));
      await recorder.tick();
      expect(await total(), 20000);
      recorder.environment(foreground: false);
      clock.advance(const Duration(minutes: 10));
      recorder.environment(foreground: true);
      clock.advance(const Duration(seconds: 10));
      await recorder.tick();
      expect(await total(), 20000);
      recorder.activity(footnote);
      clock.advance(const Duration(seconds: 10));
      await recorder.tick();
      expect(await total(), 30000);
    },
  );
  test(
    'all pause reasons must be removed; only deliberate activity renews idle',
    () async {
      final owner = Object();
      await open(owner, key);
      clock.advance(const Duration(seconds: 10));
      recorder.source(owner, key, visible: false);
      recorder.environment(focused: false);
      clock.advance(const Duration(seconds: 20));
      recorder.source(owner, key, visible: true, activity: true);
      clock.advance(const Duration(seconds: 5));
      await recorder.tick();
      expect(await total(), 10000);
      recorder.environment(focused: true);
      clock.advance(const Duration(seconds: 5));
      await recorder.tick();
      expect(await total(), 15000);
      recorder.source(owner, key, visible: false);
      clock.advance(const Duration(seconds: 20));
      recorder.source(owner, key, visible: true, activity: true);
      clock.advance(const Duration(seconds: 5));
      await recorder.tick();
      expect(await total(), 20000);
    },
  );
  test(
    'clear retains switch and cannot backfill popup time; disabling persists',
    () async {
      final owner = Object();
      await open(owner, key);
      clock.advance(const Duration(seconds: 15));
      await recorder.tick();
      expect(await recorder.clear(), true);
      expect(recorder.enabled, true);
      expect(await total(), 0);
      clock.advance(const Duration(seconds: 10));
      await recorder.tick();
      expect(await total(), 0);
      recorder.activity(owner);
      await Future<void>.delayed(Duration.zero);
      clock.advance(const Duration(seconds: 5));
      await recorder.tick();
      expect(await total(), 5000);
      await recorder.setEnabled(false);
      clock.advance(const Duration(seconds: 15));
      await recorder.tick();
      expect(await total(), 5000);
      expect(ok(await repo.settings()).enabled, false);
    },
  );
  test(
    'checkpoint payload is frozen after commit and before lost acknowledgement',
    () async {
      await recorder.close();
      recorder.dispose();
      final lost = LostAck(db);
      repo = lost;
      recorder = ReadingStatisticsController(
        repo,
        clock: clock,
        schedule: false,
      );
      final owner = Object();
      await open(owner, key);
      clock.advance(const Duration(seconds: 15));
      final writing = recorder.tick();
      await lost.committed.future;
      clock.advance(const Duration(seconds: 5));
      recorder.activity(owner);
      lost.release.complete();
      await writing;
      expect(recorder.failure, isNotNull);
      await recorder.retry();
      expect(await total(), 20000);
      expect(lost.seen[0], same(lost.seen[1]));
      expect(lost.seen[2].sequence, 2);
      expect(lost.seen[2].days.values.single, 5000);
    },
  );
  test(
    'changing books settles independently without overlapping writers',
    () async {
      final a = Object(), b = Object();
      await open(a, key);
      clock.advance(const Duration(seconds: 15));
      recorder.source(a, key, visible: false);
      await open(b, other);
      clock.advance(const Duration(seconds: 10));
      await recorder.tick();
      final snapshot = ok(
        await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
      );
      expect(snapshot.total, 25000);
      expect(snapshot.books.map((b) => b.milliseconds), [15000, 10000]);
    },
  );
  for (final action in ['clear', 'disable', 'delete']) {
    test('in-flight checkpoint cannot restore data after $action', () async {
      await recorder.close();
      recorder.dispose();
      final gated = GateSubmit(db);
      repo = gated;
      recorder = ReadingStatisticsController(
        repo,
        clock: clock,
        schedule: false,
      );
      final owner = Object();
      await open(owner, key);
      clock.advance(const Duration(seconds: 15));
      final writing = recorder.tick();
      await gated.entered.future;
      Future<bool>? disabling;
      if (action == 'clear') {
        expect(await recorder.clear(), true);
      } else if (action == 'disable') {
        disabling = recorder.setEnabled(false);
      } else {
        await db.removeReadingStatistics(key.sourceId.value, key.novelId);
      }
      gated.release.complete();
      await writing;
      if (disabling != null) expect(await disabling, true);
      await Future<void>.delayed(Duration.zero);
      expect(await total(), action == 'disable' ? 15000 : 0);
      clock.advance(const Duration(seconds: 10));
      await recorder.tick();
      expect(await total(), action == 'disable' ? 15000 : 0);
    });
  }
  test(
    'failed startup cleanup pauses statistics without rejecting reading sources',
    () async {
      await recorder.close();
      recorder.dispose();
      var fail = true;
      recorder = ReadingStatisticsController(
        repo,
        clock: clock,
        schedule: false,
        prepare: () async => fail
            ? Failure(
                AppFailure(
                  kind: FailureKind.database,
                  operation: Operation.libraryRead,
                ),
              )
            : const Success(null),
      );
      final owner = Object();
      await open(owner, key);
      expect(recorder.failure, isNotNull);
      expect(recorder.enabled, false);
      clock.advance(const Duration(seconds: 15));
      await recorder.tick();
      expect(await total(), 0);
      fail = false;
      await recorder.retry();
      await Future<void>.delayed(Duration.zero);
      recorder.activity(owner);
      clock.advance(const Duration(seconds: 5));
      await recorder.tick();
      expect(await total(), 5000);
    },
  );
  test(
    'rapid A to B to A keeps one owner and retires a late B session',
    () async {
      await recorder.close();
      recorder.dispose();
      final gated = GateBegin(db);
      repo = gated;
      recorder = ReadingStatisticsController(
        repo,
        clock: clock,
        schedule: false,
      );
      final a = Object(), b = Object();
      await open(a, key);
      clock.advance(const Duration(seconds: 5));
      recorder.source(a, key, visible: false);
      recorder.source(b, other, visible: true, activity: true);
      await gated.entered.future;
      recorder.source(b, other, visible: false);
      recorder.source(a, key, visible: true, activity: true);
      expect(recorder.recording, false);
      clock.advance(const Duration(seconds: 5));
      gated.release.complete();
      final resumed = Completer<void>();
      void changed() {
        if (recorder.recording && !resumed.isCompleted) resumed.complete();
      }

      recorder.addListener(changed);
      try {
        changed();
        await resumed.future.timeout(const Duration(seconds: 2));
      } finally {
        recorder.removeListener(changed);
      }
      clock.advance(const Duration(seconds: 5));
      await recorder.tick();
      expect(await total(), 10000);
      final snapshot = ok(
        await repo.read(firstDay: 20261021, lastDay: 20261021, today: 20261021),
      );
      expect(snapshot.books.single.key, key);
    },
  );
  test(
    'an unacknowledged write cannot hold normal shutdown indefinitely',
    () async {
      await recorder.close();
      recorder.dispose();
      final gated = GateSubmit(db);
      repo = gated;
      recorder = ReadingStatisticsController(
        repo,
        clock: clock,
        schedule: false,
      );
      await open(Object(), key);
      clock.advance(const Duration(seconds: 15));
      final writing = recorder.tick();
      await gated.entered.future;
      await recorder.close().timeout(const Duration(seconds: 3));
      expect(recorder.recording, false);
      gated.release.complete();
      await writing;
      expect(await total(), 15000);
    },
  );
}
