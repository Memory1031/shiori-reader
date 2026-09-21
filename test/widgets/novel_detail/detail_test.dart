import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/novel_detail/detail_controller.dart';
import 'package:shiori/features/novel_detail/detail_screen.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/shared/source_image.dart';
import 'package:shiori/dev/ui/search_page.dart';

final keyA = NovelKey(sourceId: SourceId('synthetic'), novelId: 'opaque/a');
final keyB = NovelKey(sourceId: SourceId('synthetic'), novelId: 'opaque:b');
final network = AppFailure(
  kind: FailureKind.network,
  operation: Operation.novelDetail,
  retryPolicy: RetryPolicy.manual,
);
LoadResult<NovelDetail> detail({
  NovelKey? key,
  String title = 'Book',
  bool stale = false,
  AppFailure? failure,
  bool rich = false,
}) => LoadResult(
  value: NovelDetail(
    summary: NovelSummary(
      key: key ?? keyA,
      title: title,
      authors: rich ? ['Author'] : [],
      cover: rich
          ? MediaRef(sourceId: (key ?? keyA).sourceId, mediaId: 'cover')
          : null,
    ),
    synopsis: rich ? List.filled(30, '很长的简介 A long synopsis.\n').join() : '',
    tags: rich ? ['幻想 Fantasy', List.filled(15, '长标签').join()] : [],
    status: rich ? NovelStatus.ongoing : NovelStatus.unknown,
  ),
  origin: stale ? LoadOrigin.local : LoadOrigin.remote,
  fetchedAt: DateTime.utc(2026),
  isStale: stale,
  refreshFailure: failure,
);

class Call {
  Call(this.key, this.mode, this.token);
  final NovelKey key;
  final ReadMode mode;
  final CancellationToken token;
  final pending = Completer<Result<LoadResult<NovelDetail>>>();
}

class Repo implements NovelRepository {
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      const Stream.empty();
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async => Failure(
    AppFailure(
      kind: FailureKind.cache,
      operation: Operation.catalog,
      context: FailureContext.cacheMiss,
    ),
  );
  final events = StreamController<Result<LoadResult<NovelDetail>>>.broadcast(
    sync: true,
  );
  final calls = <Call>[];
  @override
  Stream<Result<LoadResult<NovelDetail>>> detailUpdates(NovelKey key) =>
      events.stream;
  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    expect(events.hasListener, isTrue);
    final call = Call(key, mode, cancellation);
    calls.add(call);
    return call.pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> mount(
  WidgetTester tester,
  Repo repo, {
  String locale = 'en',
  double scale = 1,
  NovelKey? novel,
  ValueChanged<NovelKey>? onRead,
  ValueChanged<NovelKey>? onShelf,
}) => tester.pumpWidget(
  MaterialApp(
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: shioriTheme(locale == 'zh' ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: DetailScreen(
      novel: novel ?? keyA,
      repository: repo,
      onRead: onRead,
      onShelf: onShelf,
    ),
  ),
);

void main() {
  test(
    'failure notification before cache retains cache; retry policy blocks refresh',
    () async {
      final repo = Repo();
      final controller = DetailController(repository: repo, novel: keyA)
        ..onStart();
      final denied = AppFailure(
        kind: FailureKind.accessRestricted,
        operation: Operation.novelDetail,
        retryPolicy: RetryPolicy.never,
      );
      repo.events.add(Failure(denied));
      repo.calls.single.pending.complete(Success(detail(stale: true)));
      await Future<void>.delayed(Duration.zero);
      expect(controller.loaded, isNotNull);
      expect(controller.failure, denied);
      await controller.refreshDetail();
      expect(repo.calls.length, 1);
      controller.onDelete();
      await controller.resourcesReleased;
      controller.dispose();
      await repo.events.close();
    },
  );

  test('raw failure is sanitized and cancellation is silent', () async {
    final repo = Repo();
    final controller = DetailController(repository: repo, novel: keyA)
      ..onStart();
    repo.calls.single.pending.completeError(
      StateError('synthetic private error'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.failure!.kind, FailureKind.sourceUnavailable);
    final retry = controller.refreshDetail();
    repo.calls.last.pending.complete(
      Failure(AppFailure.cancelled(Operation.novelDetail)),
    );
    await retry;
    expect(controller.failure, isNull);
    controller.onDelete();
    await controller.resourcesReleased;
    controller.dispose();
    await repo.events.close();
  });

  testWidgets(
    'offline search opens selected detail and returns to retained query',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DevSearchPage(),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('search-input')),
        'shortChapter',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('search-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Short chapter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen), findsOneWidget);
      expect(find.textContaining('Short chapter'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Results for “shortChapter”'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  test(
    'subscribe before load; newest event wins; refresh is single flight; dispose cancels',
    () async {
      final repo = Repo();
      final controller = DetailController(repository: repo, novel: keyA)
        ..onStart();
      expect(repo.calls.single.mode, ReadMode.cacheFirst);
      repo.events.add(Success(detail(title: 'new')));
      repo.calls.single.pending.complete(
        Success(detail(title: 'old', stale: true)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.loaded!.value.summary.title, 'new');
      final refresh = controller.refreshDetail();
      await controller.refreshDetail();
      expect(repo.calls.length, 2);
      expect(repo.calls.last.mode, ReadMode.refresh);
      controller.onDelete();
      await controller.resourcesReleased;
      expect(repo.events.hasListener, isFalse);
      expect(repo.calls.last.token.isCancelled, isTrue);
      repo.calls.last.pending.complete(Success(detail(title: 'late')));
      await refresh;
      expect(controller.loaded!.value.summary.title, 'new');
      controller.dispose();
      await repo.events.close();
    },
  );

  testWidgets(
    'missing metadata remains readable, actions honestly unavailable',
    (tester) async {
      final repo = Repo();
      addTearDown(repo.events.close);
      await mount(tester, repo);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.calls.single.pending.complete(Success(detail()));
      await tester.pumpAndSettle();
      expect(find.text('Book'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('detail-read')))
            .onPressed,
        isNull,
      );
      expect(
        find.text(
          'Unavailable reading and bookshelf actions are still in development.',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('No synopsis available.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No synopsis available.'), findsOneWidget);
    },
  );

  testWidgets(
    'initial error retries; stale and refresh failures never erase metadata',
    (tester) async {
      final repo = Repo();
      addTearDown(repo.events.close);
      await mount(tester, repo);
      repo.calls.single.pending.complete(Failure(network));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      repo.calls.last.pending.complete(
        Success(detail(stale: true, failure: network)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Book'), findsOneWidget);
      expect(find.text('Saved details may be out of date.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('detail-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('detail-refresh')));
      await tester.pump();
      expect(find.text('Book'), findsOneWidget);
      repo.calls.last.pending.complete(Failure(network));
      await tester.pumpAndSettle();
      expect(find.text('Book'), findsOneWidget);
      repo.events.add(Success(detail(title: 'Updated')));
      await tester.pumpAndSettle();
      expect(find.text('Updated'), findsOneWidget);
      expect(find.text('Saved details may be out of date.'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    },
  );

  testWidgets(
    'identity change cancels old request; actions receive full key; wrong data rejected',
    (tester) async {
      final repo = Repo();
      addTearDown(repo.events.close);
      NovelKey? read, shelf;
      await mount(tester, repo);
      await mount(
        tester,
        repo,
        novel: keyB,
        onRead: (key) => read = key,
        onShelf: (key) => shelf = key,
      );
      expect(repo.calls.first.token.isCancelled, isTrue);
      repo.calls.first.pending.complete(Success(detail(title: 'old route')));
      repo.calls.last.pending.complete(Success(detail(key: keyB)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('detail-read')));
      await tester.tap(find.byKey(const ValueKey('detail-shelf')));
      expect(read, keyB);
      expect(shelf, keyB);
      expect(find.text('old route'), findsNothing);
      repo.events.add(Success(detail(title: 'wrong novel')));
      await tester.pumpAndSettle();
      expect(find.text('wrong novel'), findsNothing);
      expect(find.text('Book'), findsOneWidget);
    },
  );

  for (final locale in ['en', 'zh']) {
    testWidgets('$locale large text small/landscape layout and long metadata', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = Repo();
      addTearDown(repo.events.close);
      await mount(tester, repo, locale: locale, scale: 2);
      repo.calls.single.pending.complete(
        Success(
          detail(rich: true, title: List.filled(10, '长书名 Long title ').join()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('detail-read')),
        250,
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(840, 400);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.calls.length, 1);
    });
  }

  testWidgets('fixture cover decodes through shared image repository', (
    tester,
  ) async {
    final env = FixtureEnvironment();
    addTearDown(env.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DetailScreen(
          novel: fixtureNovelKey(FixtureScenario.shortChapter),
          repository: env.novels,
          images: env.images,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SourceImage), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
