import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/reading_statistics_lifecycle.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/reading_statistics_repository.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/statistics/reading_statistics_controller.dart';
import '../../domain/reading_statistics/reading_clock_test.dart'
    show TestReadingClock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'desktop native focus and wake gate timing without renewing idle',
    () async {
      const channel = MethodChannel('reading-test');
      final db = UserDatabase(NativeDatabase.memory());
      final clock = TestReadingClock();
      final recorder = ReadingStatisticsController(
        LocalReadingStatisticsRepository(db),
        clock: clock,
        schedule: false,
      );
      final bridge = ReadingStatisticsLifecycle(
        recorder,
        channel: channel,
        desktop: true,
      );
      var available = true;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'available': available, 'wake': false},
      );
      addTearDown(() async {
        bridge.close();
        await recorder.close();
        recorder.dispose();
        await db.close();
        messenger.setMockMethodCallHandler(channel, null);
      });
      await recorder.ready;
      await bridge.start();
      final owner = Object();
      recorder.source(
        owner,
        NovelKey(sourceId: SourceId('s'), novelId: 'b'),
        visible: true,
        activity: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(recorder.recording, true);
      clock.advance(const Duration(seconds: 15));
      available = false;
      await bridge.refresh();
      expect(recorder.recording, false);
      clock.advance(const Duration(minutes: 10));
      available = true;
      await bridge.refresh();
      expect(recorder.recording, false);
      recorder.activity(owner);
      expect(recorder.recording, true);
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('state', {'available': true, 'wake': true}),
        ),
        (_) {},
      );
      expect(recorder.recording, false);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      expect(await bridge.refresh(), false);
      expect(recorder.failure, isNotNull);
      expect(recorder.nativeAvailable, false);
    },
  );
}
