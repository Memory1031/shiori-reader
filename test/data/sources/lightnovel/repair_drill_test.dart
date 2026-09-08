import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/data/repositories/novel_repository.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_source.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_identity.dart';
import 'package:shiori/data/sources/source_registry.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/shared/app_logger.dart';
import '../../../../integration_test/support/mvp_fixture.dart';

void main() {
  for (final stage in [
    Operation.search,
    Operation.novelDetail,
    Operation.catalog,
    Operation.chapter,
  ]) {
    test(
      'source repair drill: ${stage.name} isolates failure and preserves cache',
      () async {
        final root = await Directory.systemTemp.createTemp('mvp-repair-');
        final db =
            (await LocalDatabases.open(
                      AppPaths(
                        support: root,
                        temporary: root,
                        environment: StorageEnvironment.development,
                      ),
                    )
                    as Success<LocalDatabases>)
                .value;
        final fixture = MvpFixture();
        final scheduler = RequestScheduler(startInterval: Duration.zero);
        final logger = AppLogger();
        final source = LightNovelSource(
          scheduler: scheduler,
          logger: logger,
          adapter: fixture,
        );
        final repo = createNovelRepository(
          sources: SourceRegistry([source]),
          cache: db.cache,
          logger: logger,
        );
        final key = lightNovelKey(1),
            chapter = lightNovelChapterKey(lightNovelKey(1), 1);
        final token = CancellationSource().token;
        Future<Result> load(Operation operation, ReadMode mode) =>
            switch (operation) {
              Operation.search => repo.search(
                source.descriptor.sourceId,
                'MVP',
                cancellation: token,
              ),
              Operation.novelDetail => repo.loadDetail(
                key,
                mode: mode,
                cancellation: token,
              ),
              Operation.catalog => repo.loadCatalog(
                key,
                mode: mode,
                cancellation: token,
              ),
              _ => repo.loadChapter(chapter, mode: mode, cancellation: token),
            };
        Future<List<Object?>> cached() async => [
          for (final table in ['novel_cache', 'catalog_cache', 'chapter_cache'])
            (await db.cache
                    .customSelect('SELECT payload FROM $table ORDER BY payload')
                    .get())
                .map((r) => r.data)
                .toList(),
        ];
        try {
          await db.users.customStatement(
            "INSERT INTO bookshelf VALUES('sentinel','n','keep',1,2)",
          );
          for (final op in [
            Operation.search,
            Operation.novelDetail,
            Operation.catalog,
            Operation.chapter,
          ]) {
            expect(await load(op, ReadMode.refresh), isA<Success>());
          }
          final before = await cached();
          fixture.broken = stage;
          final calls = fixture.calls;
          final result = await load(stage, ReadMode.refresh);
          final AppFailure failure;
          if (stage == Operation.search) {
            failure = (result as Failure).failure;
          } else {
            final value = (result as Success).value as LoadResult;
            expect(value.isStale, true);
            expect(value.origin, LoadOrigin.local);
            failure = value.refreshFailure!;
          }
          expect(failure.operation, stage);
          expect(failure.kind, FailureKind.parse);
          expect(
            fixture.calls - calls,
            1,
          ); // No retry or subsequent catalog page.
          expect(await cached(), before);
          expect(
            (await db.users
                    .customSelect('SELECT summary_json FROM bookshelf')
                    .getSingle())
                .read<String>('summary_json'),
            'keep',
          );
          fixture.broken =
              null; // Replay the known valid protocol after the drill.
          expect(await load(stage, ReadMode.refresh), isA<Success>());
          final afterRepair = fixture.calls;
          for (final op in [
            Operation.novelDetail,
            Operation.catalog,
            Operation.chapter,
          ]) {
            expect(await load(op, ReadMode.cacheOnly), isA<Success>());
          }
          expect(fixture.calls, afterRepair);
        } finally {
          await repo.close();
          source.close();
          scheduler.close();
          await db.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
