import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/app_controller.dart';
import 'package:shiori/app/bootstrap.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/controllers/scoped_controller.dart';
import 'package:shiori/shared/widgets/app_scaffold.dart';
import 'package:shiori/shared/widgets/controller_scope.dart';
import 'package:shiori/shared/widgets/state_views.dart';

import '../../support/contract_fakes.dart';

class _AppStore implements AppSettingsStore {
  AppSettings settings = AppSettings();
  @override
  Future<Result<AppSettings>> load({
    required CancellationToken cancellation,
  }) async => Success(settings);
  @override
  Future<Result<void>> save(
    AppSettings value, {
    required CancellationToken cancellation,
  }) async {
    settings = value;
    return const Success(null);
  }
}

class _PendingSettings implements AppSettingsStore {
  final requests = <Completer<Result<AppSettings>>>[];
  final tokens = <CancellationToken>[];
  @override
  Future<Result<AppSettings>> load({required CancellationToken cancellation}) {
    tokens.add(cancellation);
    final request = Completer<Result<AppSettings>>();
    requests.add(request);
    return request
        .future; // Deliberately allows late results to test the owner.
  }

  @override
  Future<Result<void>> save(
    AppSettings settings, {
    required CancellationToken cancellation,
  }) => throw UnimplementedError('No settings editing in CORE-004');
}

class _PendingRepository implements NovelRepository {
  _PendingRepository() {
    events = StreamController<Result<LoadResult<ChapterContent>>>.broadcast(
      sync: true,
      onListen: () => listeners++,
      onCancel: () => listeners--,
    );
  }
  final pending = Completer<Result<LoadResult<ChapterContent>>>();
  late final StreamController<Result<LoadResult<ChapterContent>>> events;
  int listeners = 0;
  CancellationToken? requestToken;

  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    requestToken = cancellation;
    return pending.future;
  }

  @override
  Stream<Result<LoadResult<ChapterContent>>> chapterUpdates(ChapterKey key) =>
      events.stream;

  // Unused operations are errors, never accidental successful empty results.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

// A test-only consumer of a real domain interface, not a production reader.
class _ChapterController extends ScopedController {
  _ChapterController(this.repository, this.key);
  final NovelRepository repository;
  final ChapterKey key;
  int accepted = 0;
  @override
  void onInit() {
    super.onInit();
    listenTo(repository.chapterUpdates(key), (_) {
      accepted++;
      update();
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    await repository.loadChapter(
      key,
      mode: ReadMode.cacheFirst,
      cancellation: cancellation,
    );
    if (isClosed || cancellation.isCancelled) return;
    accepted++;
    update();
  }
}

Widget _screen(Widget body) => MaterialApp(
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: AppScaffold(title: '测试', body: body),
);

void main() {
  testWidgets(
    'composition injects settings and applies theme without globals',
    (tester) async {
      final settings = _AppStore()
        ..settings = AppSettings(themeMode: AppThemeMode.dark);
      await tester.pumpWidget(createApp(settings: settings));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(find.text('Shiori'), findsOneWidget);
      expect(find.byType(SafeArea), findsWidgets);
    },
  );

  testWidgets('settings supersession and disposal reject late responses', (
    tester,
  ) async {
    final store = _PendingSettings();
    late AppController controller;
    await tester.pumpWidget(
      ShioriApp(
        createController: () {
          controller = AppController(settingsStore: store);
          return controller;
        },
      ),
    );
    final second = controller.loadSettings();
    expect(store.tokens.first.isCancelled, isTrue);
    store.requests[1].complete(
      Success(AppSettings(themeMode: AppThemeMode.dark)),
    );
    await second;
    store.requests[0].complete(
      Success(AppSettings(themeMode: AppThemeMode.light)),
    );
    await tester.pump();
    expect(controller.settings.themeMode, AppThemeMode.dark);
    final third = controller.loadSettings();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.isClosed, isTrue);
    expect(store.tokens.last.isCancelled, isTrue);
    store.requests.last.complete(
      Success(AppSettings(themeMode: AppThemeMode.light)),
    );
    await third;
    expect(controller.settings.themeMode, AppThemeMode.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings failure keeps home usable and explicit retry recovers',
    (tester) async {
      final store = _PendingSettings();
      await tester.pumpWidget(
        createApp(settings: store, locale: const Locale('zh')),
      );
      expect(find.text('Shiori'), findsOneWidget);
      store.requests.first.complete(
        Failure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.settingsRead,
            retryPolicy: RetryPolicy.manual,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shiori'), findsOneWidget);
      expect(find.text('本地存储发生问题，暂时无法完成操作。'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      store.requests.last.complete(
        Success(AppSettings(themeMode: AppThemeMode.dark)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FailureView), findsNothing);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform route push/pop releases page request and subscription',
      (tester) async {
        final repository = _PendingRepository();
        addTearDown(repository.events.close);
        late _ChapterController controller;
        late AppRoutes routes;
        routes = AppRoutes(
          home: (context) => AppScaffold(
            title: '入口',
            body: TextButton(
              onPressed: () =>
                  routes.open(context, ReaderDestination(contractChapter)),
              child: const Text('打开'),
            ),
          ),
          reader: (_, key) => ControllerScope<_ChapterController>(
            create: () => controller = _ChapterController(repository, key),
            builder: (_, value) =>
                AppScaffold(title: '测试页', body: Text('收到 ${value.accepted}')),
          ),
        );
        await tester.pumpWidget(createApp(routes: routes));
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        expect(controller.key, contractChapter);
        expect(identical(controller.repository, repository), isTrue);
        final pageContext = tester.element(find.text('测试页'));
        final route = ModalRoute.of(pageContext)!;
        expect(route.settings.name, '/reader');
        expect(route.settings.arguments, isNull);
        if (platform == TargetPlatform.iOS) {
          expect(route, isA<CupertinoPageRoute<void>>());
          await tester.dragFrom(const Offset(1, 250), const Offset(650, 0));
        } else {
          expect(route, isA<MaterialPageRoute<void>>());
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.text('入口'), findsOneWidget);
        expect(controller.isClosed, isTrue);
        expect(controller.cancellation.isCancelled, isTrue);
        expect(repository.requestToken!.isCancelled, isTrue);
        await tester.runAsync(() => controller.resourcesReleased);
        expect(repository.listeners, 0);
        final accepted = controller.accepted;
        final lateContent = contractContent('晚到的内容');
        final lateResult = Success(
          LoadResult(
            value: lateContent,
            origin: LoadOrigin.remote,
            fetchedAt: contractNow,
          ),
        );
        repository.pending.complete(lateResult);
        repository.events.add(lateResult);
        await tester.pumpAndSettle();
        expect(controller.accepted, accepted);
        expect(repository.events.isClosed, isFalse);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'each push owns a fresh controller; rebuild preserves the owner',
    (tester) async {
      final repository = ContractNovelRepository(ContractSource())
        ..cached = contractContent('缓存')
        ..stale = false;
      addTearDown(repository.close);
      final controllers = <_ChapterController>[];
      late AppRoutes routes;
      routes = AppRoutes(
        home: (context) => TextButton(
          onPressed: () =>
              routes.open(context, ReaderDestination(contractChapter)),
          child: const Text('打开'),
        ),
        reader: (_, key) => ControllerScope<_ChapterController>(
          create: () {
            final controller = _ChapterController(repository, key);
            controllers.add(controller);
            return controller;
          },
          builder: (_, controller) =>
              AppScaffold(title: '页面', body: Text('收到 ${controller.accepted}')),
        ),
      );
      await tester.pumpWidget(createApp(routes: routes));
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        controllers.last.update();
        await tester.pump();
        expect(controllers.length, i + 1);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(controllers.last.isClosed, isTrue);
      }
      expect(identical(controllers.first, controllers.last), isFalse);
    },
  );

  testWidgets('typed destination factories receive unmodified opaque keys', (
    tester,
  ) async {
    SourceId? receivedSource;
    NovelKey? receivedNovel;
    final routes = AppRoutes(
      search: (_, source) {
        receivedSource = source;
        return const Text('搜索页');
      },
      novel: (_, key) {
        receivedNovel = key;
        return const Text('详情页');
      },
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (value) {
            context = value;
            return const Text('首页');
          },
        ),
      ),
    );
    unawaited(routes.open(context, SearchDestination(contractSourceId)));
    await tester.pumpAndSettle();
    expect(receivedSource, same(contractSourceId));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    unawaited(routes.open(context, NovelDestination(contractNovel)));
    await tester.pumpAndSettle();
    expect(receivedNovel, same(contractNovel));
    expect(find.text(contractNovel.novelId), findsNothing);
  });

  testWidgets(
    'failure actions distinguish retry, cache, back and cancellation',
    (tester) async {
      var retries = 0, caches = 0, backs = 0;
      await tester.pumpWidget(
        _screen(
          FailureView(
            failure: AppFailure(
              kind: FailureKind.network,
              operation: Operation.chapter,
              retryPolicy: RetryPolicy.manual,
            ),
            onRetry: () => retries++,
            onReadCache: () => caches++,
            onBack: () => backs++,
          ),
        ),
      );
      await tester.tap(find.text('重试'));
      await tester.tap(find.text('读取缓存'));
      await tester.tap(find.text('返回'));
      expect([retries, caches, backs], [1, 1, 1]);
      for (final kind in [
        FailureKind.accessRestricted,
        FailureKind.unsupported,
        FailureKind.tooLarge,
        FailureKind.cancelled,
      ]) {
        await tester.pumpWidget(
          _screen(
            FailureView(
              failure: AppFailure(kind: kind, operation: Operation.chapter),
              onRetry: () => retries++,
              onBack: () => backs++,
            ),
          ),
        );
        expect(find.text('重试'), findsNothing);
        if (kind == FailureKind.cancelled) {
          expect(find.text('返回'), findsNothing);
        }
      }
    },
  );

  testWidgets(
    'rate limits require a known expired cooldown and owner eligibility',
    (tester) async {
      final now = DateTime.utc(2026, 9, 7);
      var retries = 0;
      Future<void> render(DateTime? deadline, {bool enabled = true}) =>
          tester.pumpWidget(
            _screen(
              FailureView(
                failure: AppFailure(
                  kind: FailureKind.rateLimited,
                  operation: Operation.chapter,
                  retryPolicy: RetryPolicy.manual,
                  retryNotBefore: deadline,
                ),
                onRetry: () => retries++,
                retryAvailable: enabled,
                now: () => now,
              ),
            ),
          );
      await render(null);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await render(now.add(const Duration(minutes: 1)));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await render(now, enabled: false);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await render(now);
      await tester.tap(find.text('重试'));
      expect(retries, 1);
    },
  );

  testWidgets('all failures use safe messages and fit small scaled viewports', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final kind in FailureKind.values) {
      final failure = AppFailure(
        kind: kind,
        operation: Operation.chapter,
        diagnosticId: '0123456789abcdef0123456789abcdef',
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 300),
              padding: EdgeInsets.only(top: 30, bottom: 20),
              viewInsets: EdgeInsets.only(bottom: 80),
              textScaler: TextScaler.linear(2),
            ),
            child: AppScaffold(
              title: '测试',
              body: FailureView(
                failure: failure,
                onBack: () {},
                onReadCache: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text(failure.diagnosticId!), findsNothing);
      expect(tester.takeException(), isNull, reason: kind.name);
    }
    await tester.pumpWidget(_screen(const LoadingView()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(_screen(const EmptyView(message: '暂无内容')));
    expect(find.text('暂无内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
