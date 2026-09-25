import 'package:flutter/services.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_completion_page.dart';
import 'completion_test.dart' show CompletionRepository;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/features/reader/epub_layout_page.dart';
import 'package:shiori/features/reader/epub_webview_host.dart';
import 'package:shiori/features/reader/svg_paper_art.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import '../../support/contract_fakes.dart';
import '../../data/local/epub_svg_links_test.dart' show svgLinksParser;
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import 'local_reading_test.dart' show MemoryBooks;
import 'package:shiori/data/repositories/local_reading_repository.dart';

const document = '<html><head></head><body>Static page</body></html>';

Future<String> svgArtworkPage({required Color paper, Color? accent}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(paper, BlendMode.src);
  canvas.drawRect(
    const Rect.fromLTWH(8, 8, 16, 16),
    Paint()..color = accent ?? const Color(0xff777777),
  );
  final image = await recorder.endRecording().toImage(64, 64);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final data = base64Encode(png!.buffer.asUint8List());
    return '<html><head></head><body class="shiori-svg-page">'
        '<svg><image href="data:image/png;base64,$data"/></svg>'
        '</body></html>';
  } finally {
    image.dispose();
  }
}

Future<(int, int, Color)> svgArtworkPixels(String html) async {
  const prefix = 'data:image/png;base64,';
  final start = html.indexOf(prefix) + prefix.length;
  final end = html.indexOf('"', start);
  final codec = await ui.instantiateImageCodec(
    base64Decode(html.substring(start, end)),
  );
  final image = (await codec.getNextFrame()).image;
  try {
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    final detail = (16 * image.width + 16) * 4;
    return (
      pixels.getUint8(3),
      pixels.getUint8(detail + 3),
      Color.fromARGB(
        pixels.getUint8(detail + 3),
        pixels.getUint8(detail),
        pixels.getUint8(detail + 1),
        pixels.getUint8(detail + 2),
      ),
    );
  } finally {
    image.dispose();
    codec.dispose();
  }
}

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

class _SvgBooks extends MemoryBooks implements LocalPagePresentationRepository {
  _SvgBooks(super.record, this.pages);
  final Map<String, String> pages;
  @override
  Future<Result<String?>> loadPagePresentation(
    ChapterKey chapter, {
    required CancellationToken cancellation,
  }) async => Success(pages[chapter.chapterId]);
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
    Color? paper,
    List<LocalContentLink> links = const [],
    ValueChanged<LocalContentLink>? onLink,
  }) => EpubWebViewHost(
    userDataDirectory: temp,
    operatingSystem: os,
    child: MaterialApp(
      theme: ThemeData(
        brightness: brightness,
      ).copyWith(scaffoldBackgroundColor: paper),
      home: EpubLayoutPage(
        html: html,
        links: links,
        onLink: onLink,
        onReady: () => ready++,
        onFailed: () => failed++,
        onPrevious: () => previous++,
        onNext: () => next++,
        onCenterTap: () => center++,
      ),
    ),
  );

  Future<void> settleSvgArtwork(WidgetTester tester, {int minHeads = 1}) async {
    // Engine image decodes complete outside the widget test's fake clock.
    for (var i = 0; i < 100 && platform.heads.length < minHeads; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    expect(platform.heads.length, greaterThanOrEqualTo(minHeads));
  }

  testWidgets('only neutral white SVG artwork blends with reader paper', (
    tester,
  ) async {
    final (neutral, colorful) = (await tester.runAsync(() async {
      final neutral = await svgArtworkPage(paper: Colors.white);
      final colorful = await svgArtworkPage(
        paper: Colors.white,
        accent: const Color(0xffe52c50),
      );
      final transparent = await svgArtworkPage(paper: Colors.transparent);
      final prepared = await themedSvgPaperArtwork(
        neutral,
        const Color(0xff332211),
      );
      expect(prepared, isNot(neutral));
      final (backgroundAlpha, detailAlpha, detailColor) =
          await svgArtworkPixels(prepared);
      expect(backgroundAlpha, 0);
      expect(detailAlpha, closeTo(136, 1));
      expect((detailColor.r * 255).round(), closeTo(0x33, 1));
      expect((detailColor.g * 255).round(), closeTo(0x22, 1));
      expect((detailColor.b * 255).round(), closeTo(0x11, 1));
      expect(await themedSvgPaperArtwork(colorful, Colors.black), colorful);
      expect(
        await themedSvgPaperArtwork(transparent, Colors.black),
        transparent,
      );
      expect(await themedSvgPaperArtwork(document, Colors.black), document);
      return (neutral, colorful);
    }))!;

    await tester.pumpWidget(
      page(html: neutral, paper: const Color(0xfff2e8d5)),
    );
    await settleSvgArtwork(tester);
    final warm = platform.heads.last.params.initialData!.data;
    expect(warm, contains('background:#f2e8d5!important'));
    expect(warm, contains('data:image/png;base64,'));
    expect(warm, isNot(contains('mix-blend-mode:')));
    await tester.pumpWidget(page(html: neutral, brightness: Brightness.dark));
    await settleSvgArtwork(tester, minHeads: 2);
    final dark = platform.heads.last.params.initialData!.data;
    expect(dark, contains('svg text:not([fill])'));

    await tester.pumpWidget(page(html: colorful));
    await settleSvgArtwork(tester, minHeads: 3);
    expect(
      platform.heads.last.params.initialData!.data,
      isNot(contains('mix-blend-mode:')),
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(320, 800), const Size(1200, 600)]) {
    testWidgets('SVG hotspots follow meet geometry and consume one tap: $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final parser = svgLinksParser();
      final content = parser.parse().content;
      final link = content.links.singleWhere((l) => l.region != null);
      final html = parser.presentations.values.first;
      var taps = 0;
      await tester.pumpWidget(
        page(html: html, links: [link], onLink: (_) => taps++),
      );
      await settleSvgArtwork(tester);
      platform.heads.single.finish();
      await tester.pumpAndSettle();
      final width = size.width < size.height * .5
          ? size.width
          : size.height * .5;
      final origin = (size.width - width) / 2;
      final point = Offset(origin + width * .15, width / .5 * .225);
      await tester.tapAt(point);
      await tester.pump();
      expect(taps, 1);
      expect(previous + next + center, 0);
      expect(find.bySemanticsLabel('Go 1'), findsOneWidget);
      await tester.dragFrom(point, const Offset(100, 0));
      await tester.pump();
      expect(taps, 1);
      expect(previous, 1);
      // Outside the rendered viewBox/region, normal reader tap controls remain.
      await tester.tapAt(Offset(size.width - 5, size.height - 5));
      await tester.pump();
      expect(next, 1);
      await tester.pumpWidget(page(html: document));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Go 1'), findsNothing);
      platform.heads.first
          .finish(); // Retired native callback cannot revive links.
      await tester.pump();
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('center SVG hotspot navigates through the page pointer layer', (
    tester,
  ) async {
    const size = Size(320, 800);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final parser = svgLinksParser();
    final content = parser.parse().content;
    final original = content.links.singleWhere((link) => link.region != null);
    final link = LocalContentLink(
      source: original.source,
      sourceBlockKey: original.sourceBlockKey,
      label: original.label,
      target: original.target,
      targetBlockKey: original.targetBlockKey,
      region: LocalLinkRegion(
        left: .4,
        top: .45,
        right: .6,
        bottom: .55,
        aspectRatio: .5,
      ),
    );
    var taps = 0;
    await tester.pumpWidget(
      page(
        html: parser.presentations.values.first,
        links: [link],
        onLink: (_) => taps++,
      ),
    );
    await settleSvgArtwork(tester);
    platform.heads.single.finish();
    await tester.pumpAndSettle();
    const point = Offset(160, 320);
    await tester.tapAt(point);
    await tester.pump();
    expect(taps, 1);
    expect(center, 0);

    // A native platform view may consume its child's gesture recognizer;
    // the outer pointer path must still deliver the hotspot exactly once.
    final listener = tester.widget<Listener>(
      find
          .descendant(
            of: find.byType(EpubLayoutPage),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Listener &&
                  widget.onPointerDown != null &&
                  widget.onPointerUp != null,
            ),
          )
          .first,
    );
    listener.onPointerDown!(
      const PointerDownEvent(position: point, timeStamp: Duration.zero),
    );
    listener.onPointerUp!(
      const PointerUpEvent(
        position: point,
        timeStamp: Duration(milliseconds: 100),
      ),
    );
    expect(taps, 2);
    expect(center, 0);

    for (final button in [kSecondaryButton, kTertiaryButton]) {
      listener.onPointerDown!(
        PointerDownEvent(
          position: point,
          timeStamp: const Duration(milliseconds: 200),
          buttons: button,
        ),
      );
      listener.onPointerUp!(
        const PointerUpEvent(
          position: point,
          timeStamp: Duration(milliseconds: 250),
        ),
      );
      expect(taps, 2);
      expect(center, 0);
      expect(previous, 0);
      expect(next, 0);
    }
  });

  testWidgets('SVG TOC tap reaches the real Reader chapter navigation', (
    tester,
  ) async {
    final parser = svgLinksParser();
    final content = parser.parse().content;
    final local = _SvgBooks(
      LocalBookRecord(
        content: content,
        format: LocalBookFormat.epub,
        importedAt: DateTime.utc(2025),
      ),
      parser.presentations,
    );
    final repo = LocalReadingRepository(
      online: ForbiddenOnline(),
      local: local,
    );
    final library = FixtureLibraryRepository();
    final settings = FixtureSettingsStore();
    await settings.save(
      ReaderSettings(controlsHintSeen: true),
      cancellation: CancellationSource().token,
    );
    await tester.pumpWidget(
      EpubWebViewHost(
        userDataDirectory: temp,
        operatingSystem: 'android',
        child: ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: content.chapters.first.key,
              repository: repo,
              library: library,
              settings: settings,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await settleSvgArtwork(tester);
    expect(find.byType(EpubLayoutPage), findsOneWidget);
    final before = tester.widget<ReaderContentView>(
      find.byType(ReaderContentView),
    );
    expect(
      before.session!.contentLinks.where((l) => l.region != null),
      isNotEmpty,
    );
    final hotspot = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Go 1',
    );
    for (var i = 0; i < 3 && hotspot.evaluate().isEmpty; i++) {
      platform.heads.last.finish();
      await tester.pumpAndSettle();
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Chapter 100%'), findsOneWidget);
    expect(
      tester.widget<EpubLayoutPage>(find.byType(EpubLayoutPage)).onLink,
      isNotNull,
    );
    expect(
      tester
          .widget<EpubLayoutPage>(find.byType(EpubLayoutPage))
          .links
          .where((l) => l.region != null),
      isNotEmpty,
    );
    await tester.tapAt(tester.getCenter(hotspot));
    await tester.pumpAndSettle();
    final reader = tester.widget<ReaderContentView>(
      find.byType(ReaderContentView),
    );
    expect(reader.content.key, content.chapters.last.key);
    expect(find.byType(BookReaderScreen), findsOneWidget);
    expect(find.byType(ReaderCompletionPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final progress = await library.getProgress(
      content.detail.summary.key,
      cancellation: CancellationSource().token,
    );
    expect(
      (progress as Success<ReadingProgress?>).value!.chapterKey,
      content.chapters.last.key,
    );
    await library.close();
  });

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
