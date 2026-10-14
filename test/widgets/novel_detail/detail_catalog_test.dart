import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/novel_detail/volume_preview.dart';
import 'package:shiori/features/novel_detail/catalog_view.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'desktop_detail_test.dart' as detail;
import 'detail_sections_test.dart' show page, LocalPreviewRepo;
import 'catalog_test.dart' show app;

class CatalogRepo extends detail.Requests {
  CatalogRepo() : super(detail.book(detail.online));
  final events = StreamController<Result<LoadResult<Catalog>>>.broadcast(
    sync: true,
  );
  final tokens = <CancellationToken>[];
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      events.stream;
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    tokens.add(cancellation);
    return super.loadCatalog(key, mode: mode, cancellation: cancellation);
  }
}

class PreviewHarness extends detail.DetailHarness {
  PreviewHarness(super.tester, super.repo) : super(host: detail.Host.root);
  @override
  Widget page() => Builder(
    builder: (context) {
      final theme = Theme.of(context);
      // AppBar's unspecified family uses the test face instead of the preview font.
      return Theme(
        data: theme.copyWith(
          appBarTheme: theme.appBarTheme.copyWith(
            titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontFamily: 'Roboto',
            ),
          ),
        ),
        child: super.page(),
      );
    },
  );
}

LoadResult<Catalog> observation({
  int count = 8,
  int day = 1,
  bool stale = false,
  AppFailure? failure,
  bool longTitles = false,
}) => LoadResult(
  value: longTitles
      ? Catalog(
          novelKey: detail.online,
          volumes: [
            Volume(
              groupId: 'v1',
              title: '第一卷 · Long authored volume title with several words',
              chapters: [
                for (final c
                    in detail.catalogOf(detail.online, count).flatChapters)
                  Chapter(
                    key: c.key,
                    title:
                        '${c.title} 长目录名称 Long chapter title that wraps within a narrow viewport',
                    ordinal: c.ordinal,
                    volumeGroupId: c.volumeGroupId,
                  ),
              ],
            ),
          ],
        )
      : detail.catalogOf(detail.online, count),
  origin: stale ? LoadOrigin.local : LoadOrigin.remote,
  fetchedAt: DateTime.utc(2026, 10, day, 13, 20),
  isStale: stale,
  refreshFailure: failure,
);
Finder refresh() => find.byKey(const ValueKey('detail-catalog-refresh'));
Finder chapters() => find.byKey(
  ValueKey((
    'preview-chapter',
    ChapterKey(novelKey: detail.online, chapterId: 'c0'),
  )),
);
String fetched(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .firstWhere((s) => s.startsWith('Last fetched:') || s.startsWith('上次获取：'));
Future<void> mount(WidgetTester tester, CatalogRepo repo) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await repo.events.close();
    await repo.detailEvents.close();
  });
  await tester.pumpWidget(
    page(VolumePreview(novel: detail.online, repository: repo)),
  );
  await tester.pump();
}

void main() {
  for (final stale in [false, true]) {
    testWidgets(
      'cached preview stale=$stale never automatically networks or refetches on rebuild',
      (tester) async {
        final repo = CatalogRepo()
          ..catalog = (_) async => Success(observation(stale: stale));
        await mount(tester, repo);
        await tester.pumpAndSettle();
        expect(chapters(), findsOneWidget);
        final l = AppLocalizations.of(tester.element(refresh()));
        expect(
          fetched(tester),
          l.catalogLastFetched(
            DateFormat.yMd(
              l.localeName,
            ).add_Hm().format(observation().fetchedAt.toLocal()),
          ),
        );
        await tester.pumpWidget(
          page(VolumePreview(novel: detail.online, repository: repo)),
        );
        await tester.pumpAndSettle();
        expect(repo.catalogs, [ReadMode.cacheOnly]);
      },
    );
  }
  for (final success in [false, true]) {
    testWidgets(
      'cache miss automatically fetches once and then ${success ? 'shows data' : 'awaits a manual retry'}',
      (tester) async {
        final pending = Completer<Result<LoadResult<Catalog>>>();
        final repo = CatalogRepo()
          ..catalog = (mode) async => mode == ReadMode.cacheOnly
              ? Failure(detail.cacheMiss)
              : pending.future;
        await mount(tester, repo);
        await tester.pump();
        expect(repo.catalogs, [ReadMode.cacheOnly, ReadMode.cacheFirst]);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text('Browse volumes and chapters'), findsNothing);
        expect(tester.widget<IconButton>(refresh()).onPressed, isNull);
        pending.complete(
          success ? Success(observation()) : Failure(detail.catalogDown),
        );
        await tester.pumpAndSettle();
        if (success) {
          expect(chapters(), findsOneWidget);
          expect(fetched(tester), isNotEmpty);
        } else {
          expect(find.text('Retry'), findsOneWidget);
          expect(find.textContaining('Last fetched:'), findsNothing);
          await tester.pumpWidget(
            page(VolumePreview(novel: detail.online, repository: repo)),
          );
          await tester.pumpAndSettle();
          expect(repo.catalogs, hasLength(2));
          repo.catalog = (_) async => Success(observation());
          await tester.tap(find.text('Retry'));
          await tester.pumpAndSettle();
          expect(repo.catalogs, [
            ReadMode.cacheOnly,
            ReadMode.cacheFirst,
            ReadMode.cacheFirst,
          ]);
        }
      },
    );
  }
  for (final failure in [
    detail.catalogDown,
    AppFailure(
      kind: FailureKind.cache,
      operation: Operation.catalog,
      context: FailureContext.invalidContent,
    ),
    AppFailure(
      kind: FailureKind.accessRestricted,
      operation: Operation.catalog,
    ),
    AppFailure.cancelled(Operation.catalog),
  ]) {
    testWidgets('ordinary ${failure.kind} is not a cache miss', (tester) async {
      final repo = CatalogRepo()..catalog = (_) async => Failure(failure);
      await mount(tester, repo);
      await tester.pumpAndSettle();
      expect(repo.catalogs, [ReadMode.cacheOnly]);
      expect(find.textContaining('Last fetched:'), findsNothing);
      if (failure.isCancellation || failure.retryPolicy == RetryPolicy.never) {
        expect(find.text('Retry'), findsNothing);
      }
    });
  }
  testWidgets(
    'an observation during cache lookup prevents redundant automatic fetch',
    (tester) async {
      final pending = Completer<Result<LoadResult<Catalog>>>(),
          repo = CatalogRepo();
      repo.catalog = (_) => pending.future;
      await mount(tester, repo);
      repo.events.add(Success(observation(day: 2)));
      await tester.pump();
      pending.complete(Failure(detail.cacheMiss));
      await tester.pumpAndSettle();
      expect(repo.catalogs, [ReadMode.cacheOnly]);
      expect(chapters(), findsOneWidget);
    },
  );
  testWidgets(
    'the standalone catalog page retains its original cache-first initialization',
    (tester) async {
      final repo = CatalogRepo()
        ..catalog = (_) async => Failure(detail.cacheMiss);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await repo.events.close();
        await repo.detailEvents.close();
      });
      await tester.pumpWidget(
        app(CatalogScreen(novel: detail.online, repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(repo.catalogs, [ReadMode.cacheFirst]);
    },
  );
  testWidgets(
    'leaving while missing-catalog lookup waits cancels and cannot fetch later',
    (tester) async {
      final pending = Completer<Result<LoadResult<Catalog>>>(),
          repo = CatalogRepo();
      repo.catalog = (_) => pending.future;
      await mount(tester, repo);
      await tester.pumpWidget(const SizedBox());
      expect(repo.tokens.single.isCancelled, isTrue);
      pending.complete(Failure(detail.cacheMiss));
      await tester.pumpAndSettle();
      expect(repo.catalogs, [ReadMode.cacheOnly]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'refresh retains rows, navigation, scroll and time; newest observation wins',
    (tester) async {
      final repo = CatalogRepo()
        ..catalog = (_) async => Success(observation(count: 100));
      ChapterKey? selected;
      await mount(tester, repo);
      await tester.pumpWidget(
        page(
          VolumePreview(
            novel: detail.online,
            repository: repo,
            onChapter: (key) => selected = key,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final old = fetched(tester),
          pending = Completer<Result<LoadResult<Catalog>>>();
      repo.catalog = (_) => pending.future;
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      position.jumpTo(8);
      await tester.pumpAndSettle();
      await tester.tap(refresh());
      await tester.pump();
      expect(repo.catalogs, [ReadMode.cacheOnly, ReadMode.refresh]);
      expect(chapters(), findsOneWidget);
      expect(fetched(tester), old);
      expect(tester.widget<IconButton>(refresh()).onPressed, isNull);
      expect(position.pixels, 8);
      await tester.tap(chapters());
      expect(selected!.chapterId, 'c0');
      repo.events.add(Success(observation(count: 100, day: 3)));
      await tester.pump();
      final latest = fetched(tester);
      expect(latest, isNot(old));
      pending.complete(Success(observation(count: 100, day: 2)));
      await tester.pumpAndSettle();
      expect(fetched(tester), latest);
      expect(position.pixels, 8);
      repo.catalog = (_) async => Success(observation(count: 101, day: 4));
      await tester.tap(refresh());
      await tester.pumpAndSettle();
      expect(repo.catalogs, [
        ReadMode.cacheOnly,
        ReadMode.refresh,
        ReadMode.refresh,
      ]);
      expect(fetched(tester), isNot(latest));
      expect(position.pixels, 8);
      expect(find.byType(SnackBar), findsNothing);
    },
  );
  for (final retained in [false, true]) {
    testWidgets(
      'refresh failure retainedResult=$retained keeps old rows and timestamp with retry',
      (tester) async {
        final repo = CatalogRepo()
          ..catalog = (_) async => Success(observation());
        await mount(tester, repo);
        await tester.pumpAndSettle();
        final old = fetched(tester);
        repo.catalog = (_) async => retained
            ? Success(observation(stale: true, failure: detail.catalogDown))
            : Failure(detail.catalogDown);
        await tester.tap(refresh());
        await tester.pumpAndSettle();
        expect(chapters(), findsOneWidget);
        expect(fetched(tester), old);
        expect(tester.widget<IconButton>(refresh()).onPressed, isNotNull);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }
  testWidgets(
    'rate limit and never-retry keep cached navigation but disable refresh',
    (tester) async {
      final repo = CatalogRepo()..catalog = (_) async => Success(observation());
      await mount(tester, repo);
      await tester.pumpAndSettle();
      for (final failure in [
        AppFailure(
          kind: FailureKind.rateLimited,
          operation: Operation.catalog,
          retryPolicy: RetryPolicy.manual,
          retryNotBefore: DateTime.now().add(const Duration(hours: 1)),
        ),
        AppFailure(
          kind: FailureKind.accessRestricted,
          operation: Operation.catalog,
        ),
      ]) {
        repo.events.add(Failure(failure));
        await tester.pump();
        expect(chapters(), findsOneWidget);
        expect(tester.widget<IconButton>(refresh()).onPressed, isNull);
        expect(find.text('Retry'), findsNothing);
      }
      expect(repo.catalogs, [ReadMode.cacheOnly]);
    },
  );
  testWidgets(
    'metadata and catalog refreshes remain independent on the real detail page',
    (tester) async {
      final repo = CatalogRepo(), h = detail.DetailHarness(tester, repo);
      final actual = h.repo;
      await h.pump();
      await h.expectReachable(refresh());
      await tester.tap(refresh());
      await tester.pumpAndSettle();
      expect(actual.catalogs, [ReadMode.cacheOnly, ReadMode.refresh]);
      expect(actual.details, [ReadMode.cacheFirst]);
      await tester.tap(h.key('detail-more'));
      await tester.pumpAndSettle();
      await tester.tap(h.key('detail-refresh'));
      await tester.pumpAndSettle();
      expect(actual.details, [ReadMode.cacheFirst, ReadMode.refresh]);
      expect(actual.catalogs, hasLength(2));
      await h.close();
      await (actual as CatalogRepo).events.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  for (final format in ['epub', 'txt']) {
    testWidgets(
      'local $format preview keeps cache-only navigation without online controls',
      (tester) async {
        final key = LocalBookIdentity.book((format == 'epub' ? 'a' : 'b') * 64),
            chapter = LocalBookIdentity.chapter(
              LocalBookIdentity.book((format == 'epub' ? 'a' : 'b') * 64),
              '$format:first',
            );
        final repo = LocalPreviewRepo(Catalog(novelKey: key, volumes: []), [
          LocalNavigationEntry(title: 'Local entry', chapterKey: chapter),
        ]);
        addTearDown(() async {
          await repo.catalogEvents.close();
          await repo.events.close();
        });
        await tester.pumpWidget(
          page(VolumePreview(novel: key, repository: repo)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Local entry'), findsOneWidget);
        expect(refresh(), findsNothing);
        expect(find.textContaining('Last fetched:'), findsNothing);
        expect(repo.modes, [ReadMode.cacheOnly]);
      },
    );
  }
  for (final scene in [
    ('android-zh', TargetPlatform.android, 390.0, 'zh', 1.0, Brightness.light),
    ('ios-en', TargetPlatform.iOS, 320.0, 'en', 2.0, Brightness.dark),
    (
      'windows-narrow',
      TargetPlatform.windows,
      900.0,
      'zh',
      1.5,
      Brightness.dark,
    ),
    (
      'windows-wide',
      TargetPlatform.windows,
      1600.0,
      'en',
      1.0,
      Brightness.light,
    ),
  ]) {
    testWidgets(
      'render catalog preview ${scene.$1}',
      (tester) async {
        final font = Platform.environment['SHIORI_CATALOG_FONT'];
        await tester.runAsync(() async {
          if (font != null) {
            final bytes = ByteData.sublistView(await File(font).readAsBytes());
            for (final family in [
              'Roboto',
              'Microsoft YaHei UI',
              'CupertinoSystemText',
              'CupertinoSystemDisplay',
            ]) {
              await (FontLoader(family)..addFont(Future.value(bytes))).load();
            }
            await (FontLoader('MaterialIcons')..addFont(
                  File(
                    '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                  ).readAsBytes().then(ByteData.sublistView),
                ))
                .load();
          }
        });
        final repo = CatalogRepo()
              ..catalog = (_) async => Success(observation(longTitles: true)),
            h = PreviewHarness(tester, repo);
        h
          ..locale = scene.$4
          ..scale = scene.$5
          ..brightness = scene.$6;
        await h.pump(width: scene.$3, height: 900);
        await tester.scrollUntilVisible(
          refresh(),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(refresh());
        await tester.pumpAndSettle();
        expect(tester.getSize(refresh()).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(refresh()).height, greaterThanOrEqualTo(48));
        expect(
          tester.widget<IconButton>(refresh()).tooltip,
          h.l.catalogRefresh,
        );
        final pending = Completer<Result<LoadResult<Catalog>>>();
        h.repo.catalog = (_) => pending.future;
        Future<void> shot(String state) async {
          final dir = Platform.environment['SHIORI_CATALOG_SCREENSHOTS'];
          if (dir == null) return;
          await tester.pump();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(dir).create(recursive: true);
            await File(
              '$dir/${scene.$1}-$state.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await shot('cached');
        await tester.tap(refresh());
        await tester.pump();
        await shot('refreshing');
        pending.complete(Failure(detail.catalogDown));
        await tester.pumpAndSettle();
        await shot('failed');
        h.repo.catalog = (_) async =>
            Success(observation(count: 9, day: 2, longTitles: true));
        await tester.tap(refresh());
        await tester.pumpAndSettle();
        await shot('refreshed');
        expect(find.byType(SnackBar), findsNothing);
        final actual = h.repo as CatalogRepo;
        expect(tester.takeException(), isNull);
        await h.close();
        await actual.events.close();
      },
      variant: TargetPlatformVariant.only(scene.$2),
    );
  }
}
