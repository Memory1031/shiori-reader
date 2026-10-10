import 'package:flutter/services.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_completion_page.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
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
import 'package:shiori/app/window_caption.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/features/reader/epub_layout_page.dart';
import 'package:shiori/features/reader/epub_webview_host.dart';
import 'package:shiori/features/reader/svg_paper_art.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/settings_panel.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import '../../support/contract_fakes.dart';
import '../../data/local/epub_svg_links_test.dart' show svgLinksParser;
import '../../data/local/epub_html_links_test.dart' show htmlLinksParser;
import 'package:shiori/shared/epub_link_address.dart';
import '../../data/local/support/epub_fixtures.dart';
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
  final documents = <String>[];
  final scripts = <String>[];
  Object? scrollPosition = <num>[0, 0];
  Completer<dynamic>? readScroll, restoreScroll;
  Object? hitAddress;
  Completer<dynamic>? readHit;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    scripts.add(source);
    if (source.startsWith('(function(){\nconst v=')) {
      return readHit == null ? hitAddress : readHit!.future;
    }
    if (source.startsWith('[')) {
      return readScroll == null ? scrollPosition : readScroll!.future;
    }
    return restoreScroll?.future;
  }

  @override
  Future<void> loadData({
    required String data,
    String mimeType = 'text/html',
    String encoding = 'utf8',
    WebUri? baseUrl,
    WebUri? historyUrl,
    Uri? androidHistoryUrl,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async {
    documents.add(data);
  }
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
  test(
    'host bounds paragraph boxes without clipping visible overflow or SVG',
    () {
      final source =
          '<html><head><meta http-equiv="Content-Security-Policy" content="script-src none"></head><body><p style="width:600px;white-space:nowrap">Synthetic wide text</p></body></html>';
      final html = epubLayoutDocument(
        source,
        Colors.white,
        Colors.black,
        Brightness.light,
        false,
      );
      expect(
        html,
        contains(
          '@layer{:where(body:not(.shiori-svg-page) p){max-width:100%;}}',
        ),
      );
      expect(html, contains('width:600px;white-space:nowrap'));
      expect(html, contains('Synthetic wide text'));
      expect(html, isNot(contains('overflow-x:')));
      expect(html, isNot(contains('overflow:hidden')));
      expect(html, contains('script-src none'));
    },
  );

  test('host width default precedes authored rules and cascade layers', () {
    for (final limit in [
      for (final selector in ['.left', 'p.left', 'p', '*', ':where(p)'])
        '$selector{max-width:120px;}',
      '@layer publisher{.left{max-width:120px;}}',
      '@layer publisher{#left{max-width:120px;}}',
    ]) {
      final files = epubFiles();
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<html><head><style>'
        '.stage{position:relative;height:260px;}'
        'p{margin:0;font:20px/1.4 monospace;}'
        '.left{position:absolute;top:0;left:0;width:100%;}'
        '.right{position:absolute;top:0;left:150px;width:120px;}'
        '$limit</style></head><body><div class="stage">'
        '<p id="left" class="left">Left synthetic text wraps inside its narrow region.</p>'
        '<p class="right">Right synthetic text stays in its own region.</p>'
        '</div></body></html>',
      );
      final parser = EpubParser(
        zipFiles(files),
        NovelKey(sourceId: SourceId('local'), novelId: 'width-test'),
        'width-test.epub',
        includePresentations: true,
      );
      parser.parse();
      final source = parser.presentations.values.single;
      final html = epubLayoutDocument(
        source,
        Colors.white,
        Colors.black,
        Brightness.light,
        false,
      );
      const fallback =
          '<style>@layer{:where(body:not(.shiori-svg-page) p){max-width:100%;}}</style>';
      expect(html.indexOf(fallback), greaterThanOrEqualTo(0));
      expect(html.indexOf(fallback), lessThan(html.indexOf(limit)));
      expect(html, isNot(contains('body:not(.shiori-svg-page) p{')));
      expect(
        html,
        isNot(
          contains(
            '<style>:where(body:not(.shiori-svg-page) p){max-width:100%;}</style>',
          ),
        ),
      );
      expect(html, contains('class="left"'));
      expect(html, contains('class="right"'));
      expect(html, contains("script-src 'none'"));
    }
  });

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
    Future<String> Function(String, Color) prepareArtwork =
        themedSvgPaperArtwork,
  }) => EpubWebViewHost(
    userDataDirectory: temp,
    operatingSystem: os,
    child: MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: ThemeData(
        brightness: brightness,
      ).copyWith(scaffoldBackgroundColor: paper),
      home: EpubLayoutPage(
        html: html,
        links: links,
        onLink: onLink,
        prepareArtwork: prepareArtwork,
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

  for (final os in ['android', 'ios', 'windows']) {
    testWidgets('HTML links consume taps and cancel native navigation on $os', (
      tester,
    ) async {
      final parser = htmlLinksParser();
      final content = parser.parse().content;
      final source = content.chapters.first;
      final links = content.links
          .where((link) => link.source == source.key)
          .toList();
      final followed = <LocalContentLink>[];
      await tester.pumpWidget(
        page(
          os: os,
          html: parser.presentations[source.key.chapterId]!,
          links: links,
          onLink: followed.add,
        ),
      );
      await tester.pumpAndSettle();
      if (os == 'windows') {
        // The shared profile directory is created outside the fake clock.
        for (var i = 0; i < 100 && platform.views.isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pumpAndSettle();
        }
        expect(platform.views, hasLength(1), reason: 'Native host not created');
      }
      dynamic native = os == 'windows'
          ? platform.views.single
          : platform.heads.single;
      Future<NavigationActionPolicy> navigate(
        String address, {
        bool main = true,
        bool gesture = true,
      }) async => await native.params.shouldOverrideUrlLoading!(
        native.wrapped,
        NavigationAction(
          request: URLRequest(url: WebUri(address)),
          isForMainFrame: main,
          hasGesture: gesture,
        ),
      );
      expect(await navigate(epubLinkAddress(0)), NavigationActionPolicy.CANCEL);
      expect(followed, isEmpty); // The document is not ready yet.
      native.finish();
      await tester.pumpAndSettle();
      final controller = platform.views.single.controller;
      expect(native.params.initialSettings!.javaScriptEnabled, isTrue);
      expect(native.params.initialData!.data, contains("script-src 'none'"));
      controller.hitAddress = epubLinkAddress(0);
      await tester.tapAt(const Offset(30, 200));
      expect(await navigate(epubLinkAddress(0)), NavigationActionPolicy.CANCEL);
      await tester.pumpAndSettle();
      expect(followed.single, same(links.first));
      expect([previous, center, next], [0, 0, 0]);
      native.params.onReceivedError!(
        native.wrapped,
        WebResourceRequest(
          url: WebUri(epubLinkAddress(0)),
          isForMainFrame: true,
        ),
        WebResourceError(
          type: WebResourceErrorType.CANCELLED,
          description: 'Canceled by navigation policy',
        ),
      );
      await tester.pumpAndSettle();
      expect(failed, 0);
      expect(platform.views, hasLength(1));

      // Native keyboard/accessibility activation resolves by ID, not label.
      expect(await navigate(epubLinkAddress(1)), NavigationActionPolicy.CANCEL);
      expect(followed.last.target, content.auxiliaryChapters.single.key);
      expect(followed, hasLength(2));
      for (final address in [
        epubLinkAddress(9876),
        '${epubLinkAddress(0)}#other',
        'https://example.invalid',
        'file:///private/book',
        'javascript:alert(1)',
      ]) {
        expect(await navigate(address), NavigationActionPolicy.CANCEL);
      }
      await navigate(epubLinkAddress(0), main: false);
      await navigate(epubLinkAddress(0), gesture: false);
      expect(followed, hasLength(2));

      await tester.dragFrom(const Offset(30, 200), const Offset(100, 0));
      expect(previous, 1);
      expect(followed, hasLength(2));
      controller.hitAddress = null;
      await tester.tapAt(const Offset(400, 200));
      await tester.pumpAndSettle();
      expect(center, 1);

      // Native activation wins even if its hit query is still pending.
      controller.readHit = Completer<dynamic>();
      await tester.tapAt(const Offset(770, 200));
      await navigate(epubLinkAddress(0));
      controller.readHit!.complete(null);
      await tester.pumpAndSettle();
      expect(followed, hasLength(3));
      expect(next, 0);
      await tester.pumpWidget(page(os: os));
      await tester.pumpAndSettle();
      await navigate(epubLinkAddress(0));
      expect(followed, hasLength(3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late or failed HTML hit queries cannot tap another document', (
    tester,
  ) async {
    final parser = htmlLinksParser();
    final content = parser.parse().content;
    final source = content.chapters.first;
    await tester.pumpWidget(
      page(
        html: parser.presentations[source.key.chapterId]!,
        links: content.links,
      ),
    );
    await tester.pumpAndSettle();
    platform.heads.single.finish();
    await tester.pumpAndSettle();
    final controller = platform.views.single.controller;
    controller.readHit = Completer<dynamic>();
    await tester.tapAt(const Offset(400, 200));
    controller.readHit!.completeError(StateError('native hit test failed'));
    await tester.pumpAndSettle();
    expect(previous + center + next, 0);
    controller.readHit = Completer<dynamic>();
    await tester.tapAt(const Offset(400, 200));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    controller.readHit!.complete(null);
    await tester.pumpAndSettle();
    expect(previous + center + next, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Windows A-B-A artwork restores loaded hotspots without navigation',
    (tester) async {
      final html = (await tester.runAsync(() async {
        final html = await svgArtworkPage(paper: Colors.red);
        expect(await themedSvgPaperArtwork(html, Colors.black), same(html));
        return html;
      }))!;
      final gates = <Completer<String>>[];
      Future<String> prepare(String source, Color ink) {
        expect(source, same(html));
        final gate = Completer<String>();
        gates.add(gate);
        return gate.future;
      }

      final link = svgLinksParser().parse().content.links.singleWhere(
        (link) => link.region != null,
      );
      var taps = 0;
      Widget themed(Brightness brightness) => page(
        os: 'windows',
        html: html,
        brightness: brightness,
        prepareArtwork: prepare,
        links: [link],
        onLink: (_) => taps++,
      );
      await tester.pumpWidget(themed(Brightness.light));
      gates[0].complete(html);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      final view = platform.views.single;
      view.finish();
      await tester.pumpAndSettle();
      expect(ready, 1);
      await tester.pumpWidget(themed(Brightness.dark));
      expect(gates.length, 2);
      await tester.pumpWidget(themed(Brightness.light));
      expect(gates.length, 3);
      gates[2].complete(html);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(link.label), findsOneWidget);
      final size = tester.getSize(find.byType(EpubLayoutPage));
      final region = link.region!;
      final width = size.width < size.height * region.aspectRatio
          ? size.width
          : size.height * region.aspectRatio;
      await tester.tapAt(
        tester.getTopLeft(find.byType(EpubLayoutPage)) +
            Offset(
              (size.width - width) / 2 +
                  width * (region.left + region.right) / 2,
              width / region.aspectRatio * (region.top + region.bottom) / 2,
            ),
      );
      expect(taps, 1);
      // Obsolete B must not replace A, even if its output would be different.
      gates[1].complete(html.replaceFirst('</body>', 'obsolete B</body>'));
      await tester.pumpAndSettle();
      expect(view.controller.documents, isEmpty);
      expect(platform.views.single, same(view));
      expect(ready, 1);
      expect(find.bySemanticsLabel(link.label), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

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

  for (final auxiliary in [false, true]) {
    testWidgets(
      'HTML TOC reaches a real ${auxiliary ? 'auxiliary' : 'main'} Reader target',
      (tester) async {
        final parser = htmlLinksParser();
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
        final native = platform.heads.single;
        native.finish();
        await tester.pumpAndSettle();
        final before = tester.widget<ReaderContentView>(
          find.byType(ReaderContentView),
        );
        expect(before.session!.contentLinks.first.presentationId, 0);
        expect(
          await native.params.shouldOverrideUrlLoading!(
            native.wrapped,
            NavigationAction(
              request: URLRequest(
                url: WebUri(epubLinkAddress(auxiliary ? 1 : 0)),
              ),
              isForMainFrame: true,
              hasGesture: true,
            ),
          ),
          NavigationActionPolicy.CANCEL,
        );
        await tester.pumpAndSettle();
        final reader = tester.widget<ReaderContentView>(
          find.byType(ReaderContentView),
        );
        expect(
          reader.content.key,
          auxiliary
              ? content.auxiliaryChapters.single.key
              : content.chapters.last.key,
        );
        final displayed = tester
            .widgetList<RichText>(find.byType(RichText))
            .map((w) => w.text.toPlainText())
            .join();
        expect(
          displayed,
          contains(auxiliary ? 'AUXILIARY_DESTINATION' : 'DESTINATION'),
        );
        if (auxiliary) {
          expect(reader.session!.library, isNull);
          // A late native event from the covered TOC must not change it.
          await native.params.shouldOverrideUrlLoading!(
            native.wrapped,
            NavigationAction(
              request: URLRequest(url: WebUri(epubLinkAddress(0))),
              isForMainFrame: true,
              hasGesture: true,
            ),
          );
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<ReaderContentView>(find.byType(ReaderContentView))
                .content
                .key,
            before.content.key,
          );
          expect(
            tester
                .widget<ReaderContentView>(find.byType(ReaderContentView))
                .session,
            same(before.session),
          );
        } else {
          expect(reader.session!.library, same(library));
          expect(displayed, isNot(contains('BEFORE')));
          final viewport = tester.widget<PagedReaderViewport>(
            find.byType(PagedReaderViewport),
          );
          expect(viewport.controller.capture()!.blockFraction, greaterThan(0));
          expect(find.byType(BookReaderScreen), findsOneWidget);
          expect(find.byType(ReaderCompletionPage), findsNothing);
          await reader.session!.flushProgress();
          final saved =
              (await library.getProgress(
                        content.detail.summary.key,
                        cancellation: CancellationSource().token,
                      )
                      as Success<ReadingProgress?>)
                  .value!;
          expect(saved.chapterKey, reader.content.key);
          expect(saved.position.blockFraction, greaterThan(0));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await library.close();
      },
    );
  }

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
    'Windows reader panels cover the page view without reloading it',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
      final captions = <CaptionAppearance>[];
      await settings.save(
        ReaderSettings(controlsHintSeen: true),
        cancellation: CancellationSource().token,
      );
      await tester.pumpWidget(
        EpubWebViewHost(
          userDataDirectory: temp,
          operatingSystem: 'windows',
          child: ShioriApp(
            captionSender: (value) async {
              captions.add(value);
            },
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
      final hotspot = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Go 1',
      );
      for (var i = 0; i < 20 && hotspot.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        if (platform.views.isNotEmpty) platform.views.last.finish();
        await tester.pumpAndSettle();
      }
      expect(hotspot, findsOneWidget);
      expect(platform.heads, isEmpty);
      final view = platform.views.last;
      final views = platform.views.length;
      final layout = tester.state(find.byType(EpubLayoutPage));
      final first = content.chapters.first.key;
      ChapterKey showing() => tester
          .widget<ReaderContentView>(find.byType(ReaderContentView))
          .content
          .key;
      final spot = tester.getCenter(hotspot);
      final panel = find.byKey(const ValueKey('reader-panel'));

      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      for (final control in [
        find.byIcon(Icons.list),
        find.byTooltip('Reading settings (Ctrl+,)'),
        find.text('Chapter 100%'),
      ]) {
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(panel, findsOneWidget);
        expect(tester.getRect(panel).contains(spot), isFalse);
        // The barrier takes the click meant for the link below it, and
        // only closes the panel.
        await tester.tapAt(spot);
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(showing(), first, reason: 'no click reaches the hotspot');
        expect(platform.views.length, views, reason: 'no new native view');
        expect(platform.views.last, same(view), reason: 'no reload');
        expect(platform.heads, isEmpty);
        expect(tester.state(find.byType(EpubLayoutPage)), same(layout));
        expect(hotspot, findsOneWidget);
      }

      // The real settings panel changes the paper while keeping both the
      // Flutter page and Windows native view owner alive, including SVG work.
      await tester.tap(find.byTooltip('Reading settings (Ctrl+,)'));
      await tester.pumpAndSettle();
      final preferences = tester
          .widget<ReaderSettingsPanel>(find.byType(ReaderSettingsPanel))
          .preferences;
      preferences.update(
        preferences.value.copyWith(themeMode: ReaderThemeMode.dark),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 40 && view.controller.documents.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      expect(
        view.controller.documents,
        hasLength(1),
        reason:
            'views=${platform.views.length}, heads=${platform.heads.length}, last=${platform.views.last.controller.documents.length}',
      );
      expect(captions.last.brightness, Brightness.dark);
      expect(platform.views.length, views);
      expect(tester.state(find.byType(EpubLayoutPage)), same(layout));
      view.finish();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(hotspot, findsOneWidget);
      expect(view.params.initialSettings!.javaScriptEnabled, isFalse);
      expect(view.params.initialSettings!.blockNetworkLoads, isTrue);
      expect(view.params.initialSettings!.allowFileAccess, isFalse);
      expect(view.params.initialSettings!.disableContextMenu, isTrue);

      // Closed, the same link navigates again.
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      await tester.tapAt(spot);
      await tester.pumpAndSettle();
      expect(showing(), content.chapters.last.key);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await library.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
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
      final owner = platform.heads.single;
      final completionReader = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView),
      );
      if (!completionReader.chrome!.value) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
      }
      expect(
        tester.widget<ReaderTopBar>(find.byType(ReaderTopBar)).title,
        'Book',
      );
      expect(
        tester
            .widget<ReaderBottomBar>(find.byType(ReaderBottomBar))
            .showProgress,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(platform.heads.single, same(owner));
      expect(owner.disposed, isFalse);
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

  testWidgets(
    'Windows theme loads serialize on one owner and acknowledge only the latest document',
    (tester) async {
      await tester.pumpWidget(page(os: 'windows'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      final view = platform.views.single;
      final owner = tester.state(find.byType(EpubLayoutPage));
      // The first document is still loading. Two changes should load only the
      // newest one after its completion; neither may acknowledge the old page.
      await tester.pumpWidget(page(os: 'windows', brightness: Brightness.dark));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        page(os: 'windows', paper: const Color(0xffffeedd)),
      );
      await tester.pumpAndSettle();
      expect(view.controller.documents, isEmpty);
      view.finish();
      await tester.pumpAndSettle();
      expect(ready, 0);
      expect(view.controller.documents.single, contains('#ffeedd'));
      expect(platform.views.single, same(view));
      expect(tester.state(find.byType(EpubLayoutPage)), same(owner));
      await tester.pumpWidget(page(os: 'windows', brightness: Brightness.dark));
      await tester.pumpAndSettle();
      view.finish();
      await tester.pumpAndSettle();
      expect(ready, 0);
      expect(view.controller.documents, hasLength(2));
      view.finish();
      await tester.pumpAndSettle();
      expect(ready, 1);
      expect(platform.views.single, same(view));
      await tester.pumpWidget(const SizedBox());
      view.finish();
      await tester.pumpAndSettle();
      expect(ready, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Windows retains scroll through pending theme reads, loads and restoration',
    (tester) async {
      await tester.pumpWidget(page(os: 'windows'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      final view = platform.views.single;
      final controller = view.controller;
      view.finish();
      await tester.pumpAndSettle();
      expect(ready, 1);
      controller.readScroll = Completer<dynamic>();
      await tester.pumpWidget(page(os: 'windows', brightness: Brightness.dark));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        page(os: 'windows', paper: const Color(0xffffeedd)),
      );
      await tester.pumpAndSettle();
      expect(controller.documents, isEmpty);
      controller.readScroll!.complete(<num>[12.5, 650.25]);
      await tester.pumpAndSettle();
      expect(controller.documents.single, contains('#ffeedd'));
      await tester.pumpWidget(page(os: 'windows', brightness: Brightness.dark));
      await tester.pumpAndSettle();
      view.finish();
      await tester.pumpAndSettle();
      expect(controller.documents, hasLength(2));
      expect(controller.scripts, ['[window.scrollX, window.scrollY]']);
      controller.restoreScroll = Completer<dynamic>();
      view.finish();
      await tester.pumpAndSettle();
      expect(ready, 1);
      expect(controller.scripts.last, 'window.scrollTo(12.5, 650.25)');
      // Another theme arrives while restoration is still in flight.
      await tester.pumpWidget(page(os: 'windows'));
      await tester.pumpAndSettle();
      expect(controller.documents, hasLength(2));
      controller.restoreScroll!.complete();
      await tester.pumpAndSettle();
      expect(controller.documents, hasLength(3));
      expect(ready, 1);
      view.finish();
      await tester.pumpAndSettle();
      expect(ready, 2);
      expect(controller.scripts, [
        '[window.scrollX, window.scrollY]',
        'window.scrollTo(12.5, 650.25)',
        'window.scrollTo(12.5, 650.25)',
      ]);
      expect(platform.views.single, same(view));
      expect(view.params.initialSettings!.javaScriptEnabled, isFalse);
      // The next settled theme change must capture the user's new position.
      controller.readScroll = Completer<dynamic>();
      await tester.pumpWidget(page(os: 'windows', brightness: Brightness.dark));
      await tester.pumpAndSettle();
      expect(controller.scripts.last, '[window.scrollX, window.scrollY]');
      await tester.pumpWidget(const SizedBox());
      controller.readScroll!.complete(<num>[0, 900]);
      await tester.pumpAndSettle();
      expect(controller.documents, hasLength(3));
      expect(tester.takeException(), isNull);
    },
  );

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
