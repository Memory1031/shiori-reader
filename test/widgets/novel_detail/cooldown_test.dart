import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/novel_detail/catalog_controller.dart';
import 'package:shiori/features/novel_detail/catalog_view.dart';
import 'package:shiori/features/novel_detail/detail_controller.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

final novel = NovelKey(sourceId: SourceId('fixture'), novelId: 'cooldown');
final start = DateTime.utc(2026, 10, 13);
AppFailure limited(
  DateTime? deadline, {
  RetryPolicy policy = RetryPolicy.manual,
}) => AppFailure(
  kind: FailureKind.rateLimited,
  operation: Operation.catalog,
  retryPolicy: policy,
  retryNotBefore: deadline,
);

class Repo implements NovelRepository {
  final details = StreamController<Result<LoadResult<NovelDetail>>>.broadcast(
    sync: true,
  );
  final catalogs = StreamController<Result<LoadResult<Catalog>>>.broadcast(
    sync: true,
  );
  final detailRequests = <Completer<Result<LoadResult<NovelDetail>>>>[];
  final catalogRequests = <Completer<Result<LoadResult<Catalog>>>>[];
  @override
  Stream<Result<LoadResult<NovelDetail>>> detailUpdates(NovelKey key) =>
      details.stream;
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      catalogs.stream;
  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    final request = Completer<Result<LoadResult<NovelDetail>>>();
    detailRequests.add(request);
    return request.future;
  }

  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    final request = Completer<Result<LoadResult<Catalog>>>();
    catalogRequests.add(request);
    return request.future;
  }

  void finish(bool catalog, AppFailure failure) {
    if (catalog) {
      catalogRequests.last.complete(Failure(failure));
    } else {
      detailRequests.last.complete(Failure(failure));
    }
  }

  void notify(bool catalog, AppFailure failure) {
    if (catalog) {
      catalogs.add(Failure(failure));
    } else {
      details.add(Failure(failure));
    }
  }

  void succeed(bool catalog) {
    if (catalog) {
      catalogs.add(
        Success(
          LoadResult(
            value: Catalog(novelKey: novel, volumes: []),
            origin: LoadOrigin.remote,
            fetchedAt: start,
          ),
        ),
      );
    } else {
      details.add(
        Success(
          LoadResult(
            value: NovelDetail(
              summary: NovelSummary(key: novel, title: 'Fixture'),
            ),
            origin: LoadOrigin.remote,
            fetchedAt: start,
          ),
        ),
      );
    }
  }

  int calls(bool catalog) =>
      catalog ? catalogRequests.length : detailRequests.length;
  Future<void> close() async {
    await details.close();
    await catalogs.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final catalog in [false, true]) {
    for (final scenario in [
      'expiry',
      'replacement',
      'success',
      'unknown',
      'never',
      'loading',
      'close',
    ]) {
      test(
        '${catalog ? 'Catalog' : 'Detail'} cooldown $scenario only notifies',
        () {
          fakeAsync((clock) {
            final repo = Repo();
            final dynamic controller = catalog
                ? CatalogController(
                    repository: repo,
                    novel: novel,
                    now: () => start.add(clock.elapsed),
                  )
                : DetailController(
                    repository: repo,
                    novel: novel,
                    now: () => start.add(clock.elapsed),
                  );
            controller.onStart();
            var notifications = 0;
            controller.addListener(() => notifications++);
            final failure = limited(
              scenario == 'unknown'
                  ? null
                  : start.add(const Duration(minutes: 1)),
              policy: scenario == 'never'
                  ? RetryPolicy.never
                  : RetryPolicy.manual,
            );
            if (scenario == 'loading') {
              repo.notify(catalog, failure);
            } else {
              repo.finish(catalog, failure);
            }
            clock.flushMicrotasks();
            expect(controller.canLoad, isFalse);
            notifications = 0;
            switch (scenario) {
              case 'expiry':
                expect(clock.nonPeriodicTimerCount, 1);
                clock.elapse(const Duration(seconds: 59));
                expect(notifications, 0);
                expect(controller.canLoad, isFalse);
                clock.elapse(const Duration(seconds: 1));
                expect(controller.canLoad, isTrue);
                expect(notifications, 1);
                expect(clock.nonPeriodicTimerCount, 0);
                expect(repo.calls(catalog), 1);
                controller.load();
                expect(repo.calls(catalog), 2);
                repo.finish(
                  catalog,
                  AppFailure(
                    kind: FailureKind.network,
                    operation: Operation.catalog,
                    retryPolicy: RetryPolicy.manual,
                  ),
                );
                clock.flushMicrotasks();
              case 'replacement':
                clock.elapse(const Duration(seconds: 30));
                repo.notify(
                  catalog,
                  limited(start.add(const Duration(seconds: 90))),
                );
                notifications = 0;
                expect(clock.nonPeriodicTimerCount, 1);
                clock.elapse(const Duration(seconds: 30));
                expect(controller.canLoad, isFalse);
                expect(notifications, 0);
                clock.elapse(const Duration(seconds: 30));
                expect(controller.canLoad, isTrue);
                expect(notifications, 1);
              case 'success':
                repo.succeed(catalog);
                notifications = 0;
                expect(clock.nonPeriodicTimerCount, 0);
                clock.elapse(const Duration(minutes: 2));
                expect(controller.canLoad, isTrue);
                expect(notifications, 0);
              case 'unknown':
              case 'never':
                expect(clock.nonPeriodicTimerCount, 0);
                clock.elapse(const Duration(minutes: 2));
                expect(controller.canLoad, isFalse);
                expect(notifications, 0);
              case 'loading':
                clock.elapse(const Duration(minutes: 1));
                expect(controller.canLoad, isFalse);
                expect(controller.loading, isTrue);
                expect(repo.calls(catalog), 1);
                repo.finish(catalog, failure);
                clock.flushMicrotasks();
                expect(controller.canLoad, isTrue);
              case 'close':
                controller.onDelete();
                expect(clock.nonPeriodicTimerCount, 0);
                clock.elapse(const Duration(minutes: 2));
                expect(notifications, 0);
            }
            expect(repo.calls(catalog), scenario == 'expiry' ? 2 : 1);
            controller.onDelete();
            controller.dispose();
            unawaited(repo.close());
            clock.flushMicrotasks();
            expect(clock.nonPeriodicTimerCount, 0);
          });
        },
      );
    }
  }

  testWidgets(
    'real catalog header and retry enable at expiry without requesting',
    (tester) async {
      final repo = Repo();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CatalogScreen(novel: novel, repository: repo),
        ),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      repo.finish(true, limited(deadline));
      await tester.pump();
      final header = find.widgetWithIcon(IconButton, Icons.refresh);
      expect(tester.widget<IconButton>(header).onPressed, isNull);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.runAsync(
        () => Future<void>.delayed(
          deadline.difference(DateTime.now()) +
              const Duration(milliseconds: 10),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<IconButton>(header).onPressed, isNotNull);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(repo.catalogRequests, hasLength(1));
      await tester.pump(const Duration(minutes: 2));
      expect(repo.catalogRequests, hasLength(1));
      await tester.tap(header);
      await tester.pump();
      expect(repo.catalogRequests, hasLength(2));
      expect(tester.widget<IconButton>(header).onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      repo.finish(true, AppFailure.cancelled(Operation.catalog));
      await tester.pump();
      await repo.close();
      expect(tester.takeException(), isNull);
    },
  );
}
