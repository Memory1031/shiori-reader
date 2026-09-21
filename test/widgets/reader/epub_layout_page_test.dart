import 'package:flutter/services.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_completion_page.dart';
import 'completion_test.dart' show CompletionRepository;
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/features/reader/epub_layout_page.dart';
import 'package:shiori/features/reader/epub_webview_host.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import '../../support/contract_fakes.dart';

const document = '<html><head></head><body>Static page</body></html>';

class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'test'),
      );
}

class _Headless extends PlatformHeadlessInAppWebView {
  _Headless(super.params, this.owner) : super.implementation();
  final _Platform owner;
  bool disposed = false;
  final controller = _Controller();
  dynamic get wrapped => params.controllerFromPlatform!(controller);
  @override
  Future<void> run() async {
    if (owner.failCreation) throw StateError('native creation failed');
    await owner.gate?.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  void finish() => params.onLoadStop!(wrapped, WebUri('about:blank'));
}

class _View extends PlatformInAppWebViewWidget {
  _View(super.params) : super.implementation();
  bool attached = false;
  final controller = _Controller();
  dynamic get wrapped => params.controllerFromPlatform!(controller);
  void finish() => params.onLoadStop!(wrapped, WebUri('about:blank'));
  @override
  Widget build(BuildContext context) {
    if (!attached) {
      attached = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        params.onWebViewCreated!(wrapped);
      });
    }
    return const SizedBox.expand();
  }

  @override
  void dispose() {}
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
}

class _Environment extends PlatformWebViewEnvironment {
  _Environment(this.owner)
    : super.implementation(const PlatformWebViewEnvironmentCreationParams());
  final _Platform owner;
  @override
  Future<String?> getAvailableVersion({
    String? browserExecutableFolder,
  }) async => owner.runtime;
  @override
  Future<PlatformWebViewEnvironment> create({
    WebViewEnvironmentSettings? settings,
  }) async {
    owner.dataFolder = settings?.userDataFolder;
    owner.environments++;
    return this;
  }

  @override
  String get id => 'environment';
  @override
  Future<void> dispose() async {
    owner.environmentClosed = true;
  }
}

class _Platform extends InAppWebViewPlatform {
  final heads = <_Headless>[];
  final views = <_View>[];
  bool failCreation = false, environmentClosed = false;
  String? runtime = '123.0', dataFolder;
  int environments = 0;
  Completer<void>? gate;
  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
    PlatformHeadlessInAppWebViewCreationParams params,
  ) {
    final head = _Headless(params, this);
    heads.add(head);
    return head;
  }

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    final view = _View(params);
    views.add(view);
    return view;
  }

  @override
  PlatformWebViewEnvironment createPlatformWebViewEnvironmentStatic() =>
      _Environment(this);
}

class _CompletionPresentation extends CompletionRepository
    implements LocalPagePresentationRepository {
  _CompletionPresentation() : super(local: true);
  @override
  Future<Result<String?>> loadPagePresentation(
    ChapterKey chapter, {
    required CancellationToken cancellation,
  }) async => const Success(document);
}

void main() {
  late _Platform platform;
  late Directory temp;
  var ready = 0, failed = 0, previous = 0, next = 0, center = 0;
  setUp(() async {
    platform = _Platform();
    InAppWebViewPlatform.instance = platform;
    temp = await Directory.systemTemp.createTemp('shiori-webview-test-');
    ready = failed = previous = next = center = 0;
  });
  tearDown(() async {
    await temp.delete();
  });

  Widget page({
    String html = document,
    String os = 'android',
    Brightness brightness = Brightness.light,
  }) => EpubWebViewHost(
    userDataDirectory: temp,
    operatingSystem: os,
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: EpubLayoutPage(
        html: html,
        onReady: () => ready++,
        onFailed: () => failed++,
        onPrevious: () => previous++,
        onNext: () => next++,
        onCenterTap: () => center++,
      ),
    ),
  );

  testWidgets(
    'last main WebView page enters completion and returns without reopening platform view',
    (tester) async {
      final repo = _CompletionPresentation();
      final library = FixtureLibraryRepository();
      await tester.pumpWidget(
        EpubWebViewHost(
          userDataDirectory: temp,
          operatingSystem: 'android',
          child: ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (_) => BookReaderScreen(
                chapter: repo.order.last,
                repository: repo,
                library: library,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      platform.heads.single.finish();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCompletionPage), findsNothing);
      final requests = repo.loads;
      // Keyboard and WebView tap callbacks both go through the same end boundary.
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCompletionPage), findsOneWidget);
      final saved =
          (await library.getProgress(
                    repo.key,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value!;
      expect(saved.bookProgress!.terminal, BookTerminalState.finished);
      expect(saved.position.chapterFraction, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCompletionPage), findsNothing);
      expect(platform.heads.length, 1);
      tester.widget<EpubLayoutPage>(find.byType(EpubLayoutPage)).onNext!();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCompletionPage), findsOneWidget);
      expect(repo.loads, requests);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(platform.heads.single.disposed, isTrue);
      // A new route/platform view restores EOF rather than treating ready as restart.
      await tester.pumpWidget(
        EpubWebViewHost(
          userDataDirectory: temp,
          operatingSystem: 'android',
          child: ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (_) => BookReaderScreen(
                chapter: repo.order.last,
                repository: repo,
                library: library,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      platform.heads.last.finish();
      await tester.pumpAndSettle();
      final reopened = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView),
      );
      await reopened.session!.flushProgress();
      final restored =
          (await library.getProgress(
                    repo.key,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value!;
      expect(restored.position.chapterFraction, 1);
      expect(restored.bookProgress!.terminal, BookTerminalState.finished);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await repo.updates.close();
      await library.close();
    },
  );

  testWidgets(
    'static policy blocks scripts, remote navigation and popups; taps and swipes survive',
    (tester) async {
      await tester.pumpWidget(page());
      await tester.pump();
      final head = platform.heads.single;
      final settings = head.params.initialSettings!;
      expect(settings.javaScriptEnabled, isFalse);
      expect(settings.blockNetworkLoads, isTrue);
      expect(settings.allowFileAccess, isFalse);
      expect(settings.disallowOverScroll, isTrue);
      final html = head.params.initialData!.data;
      expect(html, contains('scrollbar-width:none'));
      expect(html, contains('::-webkit-scrollbar{display:none;}'));
      expect(html, isNot(contains('overflow:hidden')));
      for (final url in [
        'https://example.invalid',
        'file:///private/book',
        'data:text/html,other',
        'javascript:alert(1)',
      ]) {
        expect(
          await head.params.shouldOverrideUrlLoading!(
            head.wrapped,
            NavigationAction(
              request: URLRequest(url: WebUri(url)),
              isForMainFrame: true,
            ),
          ),
          NavigationActionPolicy.CANCEL,
        );
      }
      expect(ready, 0);
      head.finish();
      await tester.pump();
      expect(ready, 1);
      head.finish();
      await tester.pump();
      expect(ready, 1);
      await tester.tapAt(const Offset(30, 200));
      await tester.tapAt(const Offset(400, 200));
      await tester.tapAt(const Offset(770, 200));
      await tester.dragFrom(const Offset(500, 200), const Offset(-100, 0));
      expect([previous, center, next], [1, 1, 2]);
      await tester.pumpWidget(const SizedBox());
      expect(head.disposed, isTrue);
    },
  );

  testWidgets('theme change retires document and ignores its late completion', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.pump();
    final old = platform.heads.single;
    await tester.pumpWidget(page(brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(platform.heads.length, greaterThan(1));
    expect(
      platform.heads.last.params.initialData!.data,
      isNot(old.params.initialData!.data),
    );
    old.finish();
    await tester.pump();
    expect(ready, 0);
    platform.heads.last.finish();
    await tester.pump();
    expect(ready, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('creation failure and stalled load notify fallback once', (
    tester,
  ) async {
    platform.failCreation = true;
    await tester.pumpWidget(page());
    await tester.pump();
    expect(failed, 1);
    await tester.pump(const Duration(seconds: 16));
    expect(failed, 1);
    platform.failCreation = false;
    await tester.pumpWidget(
      page(html: document.replaceFirst('Static', 'Other')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    expect(failed, 2);
    platform.heads.last.finish();
    await tester.pump();
    expect(ready, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Windows loads the visible document and waits for its completion',
    (tester) async {
      await tester.pumpWidget(page(os: 'windows'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(platform.heads, isEmpty);
      final view = platform.views.single;
      expect(view.params.headlessWebView, isNull);
      expect(view.params.initialData!.data, contains('Static page'));
      expect(view.params.initialSettings!.javaScriptEnabled, isFalse);
      expect(view.params.initialSettings!.blockNetworkLoads, isTrue);
      expect(view.params.initialSettings!.allowFileAccess, isFalse);
      expect(ready, 0);
      view.finish();
      await tester.pump();
      expect(ready, 1);
      await tester.pumpWidget(
        page(os: 'windows', html: document.replaceFirst('Static', 'Other')),
      );
      await tester.pumpAndSettle();
      final nextView = platform.views.last;
      expect(nextView.params.initialData!.data, contains('Other page'));
      view.finish();
      await tester.pump();
      expect(ready, 1);
      await tester.pump(const Duration(seconds: 16));
      expect(failed, 1);
      nextView.finish();
      await tester.pump();
      expect(ready, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Windows missing runtime falls back before creating a native view',
    (tester) async {
      platform.runtime = null;
      await tester.pumpWidget(page(os: 'windows'));
      await tester.pump();
      expect(failed, 1);
      expect(platform.heads, isEmpty);
      expect(platform.environments, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late native creation is disposed after the page leaves', (
    tester,
  ) async {
    platform.gate = Completer<void>();
    await tester.pumpWidget(page());
    await tester.pump();
    final pending = platform.heads.single;
    await tester.pumpWidget(const SizedBox());
    platform.gate!.complete();
    await tester.pump();
    pending.finish();
    await tester.pump();
    expect(pending.disposed, isTrue);
    expect([ready, failed], [0, 0]);
  });

  testWidgets(
    'Windows uses the injected writable profile and releases its shared environment',
    (tester) async {
      await tester.pumpWidget(page(os: 'windows'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(platform.dataFolder, temp.path);
      expect(platform.environments, 1);
      await tester.pumpWidget(
        page(os: 'windows', html: document.replaceFirst('Static', 'Other')),
      );
      await tester.pump();
      expect(platform.environments, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(platform.environmentClosed, isTrue);
    },
  );

  testWidgets('reader falls back to semantic pagination and reports ready', (
    tester,
  ) async {
    platform.failCreation = true;
    final repository = ContractNovelRepository(ContractSource());
    final session = ReaderController(
      repository: repository,
      chapter: contractChapter,
    )..pagePresentation = document;
    await tester.pumpWidget(
      EpubWebViewHost(
        userDataDirectory: temp,
        operatingSystem: 'android',
        child: ShioriApp(
          routes: AppRoutes(
            home: (_) => ReaderContentView(
              content: contractContent('原生正文回退'),
              session: session,
              onReady: () => ready++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EpubLayoutPage), findsNothing);
    expect(find.byType(PagedReaderViewport), findsOneWidget);
    expect(ready, 1);
    expect(session.restoreStatus, ReaderRestoreStatus.ready);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    await repository.close();
  });
  testWidgets('wide authored pages stay centered in one capped WebView', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = ContractNovelRepository(ContractSource());
    final session = ReaderController(
      repository: repository,
      chapter: contractChapter,
    )..pagePresentation = document;
    await tester.pumpWidget(
      EpubWebViewHost(
        userDataDirectory: temp,
        operatingSystem: 'android',
        child: ShioriApp(
          routes: AppRoutes(
            home: (_) => ReaderContentView(
              content: contractContent('Authored page'),
              session: session,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final rect = tester.getRect(find.byType(EpubLayoutPage));
    expect(rect.width, 680);
    expect(rect.center.dx, 900);
    expect(find.byType(PagedReaderViewport), findsNothing);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    await repository.close();
  });
}
