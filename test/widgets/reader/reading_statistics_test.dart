import 'dart:async';
import 'package:drift/native.dart';
import 'package:shiori/app/app_exit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/reading_statistics_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/statistics/reading_statistics_controller.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/shared/widgets/reading_statistics_scope.dart';
import '../../domain/reading_statistics/reading_clock_test.dart'
    show TestReadingClock;
import 'link_return_test.dart' as f;
import 'local_search_test.dart' show ReaderSearchRepository;
import 'package:shiori/features/reader/reader_search_panel.dart';

void main() {
  testWidgets(
    'real paged Reader toolbar, search, panel return and auxiliary ownership',
    (tester) async {
      const appChannel = MethodChannel('dev.shiori.reader/app');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        appChannel,
        (_) async => true,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          appChannel,
          null,
        ),
      );
      final db = UserDatabase(NativeDatabase.memory());
      final repo = LocalReadingStatisticsRepository(db),
          clock = TestReadingClock();
      late ReadingStatisticsController recorder;
      await tester.runAsync(() async {
        recorder = ReadingStatisticsController(
          repo,
          clock: clock,
          schedule: false,
        );
        await recorder.ready;
      });
      addTearDown(() async {
        await recorder.close();
        recorder.dispose();
        await db.close();
      });
      await tester.runAsync(() async {
        await recorder.ready;
        await db.customStatement(
          'INSERT INTO local_books(digest,format,title,imported_at,manifest_hash) VALUES(?,?,?,?,?)',
          [
            f.returnBook().detail.summary.key.novelId,
            'epub',
            'Fixture',
            0,
            'a' * 64,
          ],
        );
      });
      final reader = await f.mount(
        tester,
        statistics: recorder,
        repositoryFactory: ReaderSearchRepository.new,
        size: const Size(1100, 800),
      );
      Future<void> settle() async {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
      }

      Future<int> total() async {
        var result = 0;
        await tester.runAsync(() async {
          await recorder.tick();
          result =
              (await repo.read(
                        firstDay: 20261021,
                        lastDay: 20261021,
                        today: 20261021,
                      )
                      as Success<ReadingStatisticsSnapshot>)
                  .value
                  .total;
        });
        await tester.pumpAndSettle();
        return result;
      }

      await settle();
      expect(recorder.recording, true);
      clock.advance(const Duration(seconds: 10));
      await f.toggle(tester);
      expect(find.byType(ReaderTopBar), findsOneWidget);
      clock.advance(const Duration(seconds: 10));
      expect(await total(), 20000);
      await tester.tap(find.byKey(const ValueKey('reader-search-open')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSearchPanel), findsOneWidget);
      expect(recorder.recording, false);
      clock.advance(const Duration(seconds: 20));
      expect(await total(), 20000);
      await tester.binding.handlePopRoute();
      await settle();
      expect(recorder.recording, true);
      clock.advance(const Duration(seconds: 10));
      expect(await total(), 30000);
      final origin = reader.position(tester);
      await reader.link(tester, 'Same file');
      await settle();
      expect(reader.position(tester), isNot(origin));
      clock.advance(const Duration(seconds: 10));
      expect(await total(), 40000);
      await reader.link(tester, 'Auxiliary');
      await settle();
      expect(recorder.recording, true);
      clock.advance(const Duration(seconds: 10));
      expect(await total(), 50000);
      final view = reader.view(tester);
      view.actions.contentLink!(
        reader.book.links.firstWhere(
          (l) => l.source == view.content.key && l.footnoteText != null,
        ),
      );
      await settle();
      expect(recorder.recording, true);
      clock.advance(const Duration(seconds: 10));
      expect(await total(), 60000);
      await tester.binding.handlePopRoute();
      await settle();

      final exit = tester.state<AppExitScopeState>(find.byType(AppExitScope));
      final saving = Completer<bool>();
      final remove = exit.register(() => saving.future);
      final quitting = exit.didRequestAppExit();
      await tester.pump();
      await tester.pump();
      expect(recorder.recording, false);
      clock.advance(const Duration(seconds: 10));
      expect(await total(), 60000);
      saving.complete(false);
      await tester.pumpAndSettle();
      await quitting;
      remove();
      await settle();
      expect(recorder.recording, true);
      expect(find.byType(ReadingActivity), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
