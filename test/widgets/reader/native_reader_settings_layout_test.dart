import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_chrome.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_preferences.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/block_style.dart';
import 'package:shiori/features/reader/viewport/page_boundaries.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

import '../../support/legacy_native_reader_settings.dart';
import 'settings_test.dart' show Store;

final _platforms = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.windows,
});

ChapterContent _content() => ChapterContent(
  key: fixtureChapterKey(FixtureScenario.longChapter),
  title: 'Native settings equivalence',
  blocks: [
    HeadingBlock(text: 'A quiet reading page', level: 1),
    ParagraphBlock(text: '正文排版，保留字体、段距与语义位置。' * 12),
    ParagraphBlock(
      text: List.generate(
        200,
        (i) => 'Passage $i: Stars above the river. 😀 ',
      ).join(),
    ),
    ImageBlock(
      media: fixtureMediaRef(0),
      width: 240,
      height: 360,
      alt: 'Illustration',
    ),
    ParagraphBlock(text: 'The chapter ends here. ' * 35),
  ],
);

ReaderPosition _anchor(ChapterContent content, int block, double fraction) =>
    ReaderPosition(
      contentRevision: content.contentRevision,
      blockKey: content.blocks[block].blockKey,
      blockIndex: block,
      blockFraction: fraction,
      chapterFraction: (block + fraction) / content.blocks.length,
    );

Object _pageSignature(ReaderPage page) => [
  (page.start.unit, page.start.offset),
  (page.end.unit, page.end.offset),
  page.columnBreak,
  page.fullWidth,
  page.centered,
  [
    for (final f in page.fragments)
      (f.unit, f.start, f.end, f.height, f.text, f.boxTop, f.boxBottom),
  ],
];

// Use the old settings conversions and geometry, then the unchanged pagination
// engine. Never derive expected dimensions or typography from adapter outputs.
PageLayout _legacyLayout(WidgetTester tester, ReaderSettings settings) {
  final finder = find.byType(PagedReaderViewport);
  final context = tester.element(finder);
  final widget = tester.widget<PagedReaderViewport>(finder);
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  final margin = legacyNativeMargin(settings, scaler, direction);
  final pageSize = tester.getSize(find.byType(ReaderContentView));
  final columns = pageSize.width - 2 * margin >= 1072 ? 2 : 1;
  final width = math.min(
    pageSize.width - 2 * margin,
    columns == 2 ? 1432.0 : 680.0,
  );
  final chrome = ReaderChromeMetrics.of(context);
  final defaults = DefaultTextStyle.of(context);
  final style = defaults.style
      .merge(
        legacyNativeBodyStyle(
          settings,
          Theme.of(context),
          explicitUiTypeface: defaultTargetPlatform == TargetPlatform.windows,
        ),
      )
      .copyWith(inherit: false);
  return PageLayout(
    index: ChunkIndex(widget.content, maxCodePoints: widget.maxChunkCodePoints),
    width: (width - (columns - 1) * 72) / columns,
    height: pageSize.height - chrome.header - chrome.footer,
    columns: columns,
    style: style,
    scaler: scaler,
    direction: direction,
    locale: Localizations.maybeLocaleOf(context),
    textHeightBehavior:
        defaults.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context),
    paragraphSpacing: settings.paragraphSpacing,
    // Image sizing is outside this extraction and is already supplied by the
    // host; the independent width/height assertions also protect its inputs.
    imageExtent: widget.imageExtent,
  );
}

ReaderPage _legacyPage(PageLayout layout, ReaderPosition? anchor) {
  final target = layout.cursor(anchor);
  final pages = PageBoundaries(layout);
  var cursor = const PageCursor(0, 0);
  while (true) {
    final page = pages.forward(cursor)!;
    if (PageBoundaries.compare(target, page.end) < 0 ||
        page.end.unit == layout.index.chunks.length) {
      return page;
    }
    cursor = page.end;
  }
}

void _expectLegacyPage(
  WidgetTester tester,
  ReaderSettings settings,
  ReaderPosition? anchor,
) {
  final finder = find.byType(PagedReaderViewport);
  final widget = tester.widget<PagedReaderViewport>(finder);
  final actual = widget.controller.inspectDisplayedPage()!;
  final layout = _legacyLayout(tester, settings);
  final expected = _legacyPage(layout, anchor);
  expect(actual.columns, layout.columns);
  expect(actual.width, layout.width);
  expect(actual.height, layout.height);
  final rect = tester.getRect(finder);
  final expectedWidth =
      layout.width * layout.columns + (layout.columns - 1) * 72;
  expect(rect.width, expectedWidth);
  expect(
    rect.left,
    (tester.getSize(find.byType(ReaderContentView)).width - expectedWidth) / 2,
  );
  expect(
    rect.right,
    tester.getSize(find.byType(ReaderContentView)).width - rect.left,
  );
  expect(_pageSignature(actual.page), _pageSignature(expected));
  final textFragments = expected.fragments
      .where((f) => f.text != null && f.text != '')
      .toList();
  final rendered = tester
      .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
      .toList();
  expect(rendered.map((w) => (w.blockOffset, w.text)), [
    for (final f in textFragments)
      (layout.index.chunks[f.unit].start + f.start, f.text),
  ]);
  for (var i = 0; i < rendered.length; i++) {
    final fragment = textFragments[i];
    final block =
        widget.content.blocks[layout.index.chunks[fragment.unit].blockIndex];
    final expectedStyle = readerBlockStyle(
      block,
      layout.style,
      chapter: widget.content.key,
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byWidget(rendered[i]),
            matching: find.byType(RichText),
          )
          .first,
    );
    expect(paragraph.text.style!.fontSize, expectedStyle.fontSize);
    expect(paragraph.text.style!.height, expectedStyle.height);
    expect(paragraph.text.style!.fontFamily, expectedStyle.fontFamily);
    expect(
      paragraph.text.style!.fontFamilyFallback,
      expectedStyle.fontFamilyFallback,
    );
    expect(
      paragraph.textScaler.scale(settings.fontSize),
      layout.scaler.scale(settings.fontSize),
    );
  }
  final position = widget.controller.capture()!;
  final expectedPosition = anchor ?? layout.position(expected.start);
  expect(position.blockKey, expectedPosition.blockKey);
  expect(position.blockIndex, expectedPosition.blockIndex);
  expect(
    position.blockFraction,
    closeTo(expectedPosition.blockFraction, .000001),
  );
  expect(
    position.chapterFraction,
    closeTo(expectedPosition.chapterFraction, .000001),
  );
  expect(widget.controller.usedFallback, isFalse);
}

Future<void> _screenshot(WidgetTester tester, String name) async {
  final directory = Platform.environment['SHIORI_ADAPTER_EVIDENCE'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first)
        .toImage();
    final data = await image.toByteData(format: ImageByteFormat.png);
    final file = File('$directory/${defaultTargetPlatform.name}-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  final configurations = [
    (
      name: 'phone',
      size: const Size(400, 900),
      scale: 1.0,
      direction: TextDirection.ltr,
      settings: ReaderSettings(controlsHintSeen: true),
    ),
    (
      name: 'landscape',
      size: const Size(900, 400),
      scale: 1.5,
      direction: TextDirection.rtl,
      settings: ReaderSettings(
        fontSize: 26,
        lineHeight: 1.2,
        paragraphSpacing: 0,
        horizontalPadding: 12,
        paper: ReaderPaper.warm,
        controlsHintSeen: true,
      ),
    ),
    (
      name: 'below-spread',
      size: const Size(1161.9, 800),
      scale: 1.5,
      direction: TextDirection.ltr,
      settings: ReaderSettings(horizontalPadding: 39, controlsHintSeen: true),
    ),
    (
      name: 'above-spread',
      size: const Size(1162.1, 800),
      scale: 1.5,
      direction: TextDirection.ltr,
      settings: ReaderSettings(horizontalPadding: 39, controlsHintSeen: true),
    ),
    (
      name: 'wide-night',
      size: const Size(1800, 900),
      scale: 2.0,
      direction: TextDirection.ltr,
      settings: ReaderSettings(
        fontSize: 32,
        lineHeight: 2.4,
        paragraphSpacing: 32,
        horizontalPadding: 48,
        themeMode: ReaderThemeMode.dark,
        controlsHintSeen: true,
      ),
    ),
  ];
  for (final config in configurations) {
    testWidgets('native reader matches old page layout: ${config.name}', (
      tester,
    ) async {
      tester.view.physicalSize = config.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = config.scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final content = _content();
      final store = Store()..value = config.settings;
      final controller = PagedReaderController();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => Directionality(
              textDirection: config.direction,
              child: ReaderContentView(
                content: content,
                settings: store,
                viewportController: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectLegacyPage(tester, config.settings, null);
      await _screenshot(tester, config.name);
      if (config.name == 'below-spread') {
        expect(controller.inspectDisplayedPage()!.columns, 1);
      } else if (config.name == 'above-spread') {
        expect(controller.inspectDisplayedPage()!.columns, 2);
      }
      for (final anchor in [
        _anchor(content, 2, .6),
        _anchor(content, 3, 0),
        _anchor(content, 4, 1),
      ]) {
        controller.restore(anchor);
        await tester.pumpAndSettle();
        _expectLegacyPage(tester, config.settings, anchor);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }, variant: _platforms);
  }

  testWidgets(
    'live settings and environment match old layout without losing the anchor',
    (tester) async {
      tester.view.physicalSize = const Size(1162.1, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final content = _content();
      final preferences = ReaderPreferences(null)
        ..value = ReaderSettings(controlsHintSeen: true);
      final chrome = ValueNotifier(false);
      final controller = PagedReaderController();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => ReaderContentView(
              content: content,
              preferences: preferences,
              viewportController: controller,
              chrome: chrome,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final anchor = _anchor(content, 2, .6);
      controller.restore(anchor);
      await tester.pumpAndSettle();
      for (final update in <ReaderSettings Function(ReaderSettings)>[
        (s) => s.copyWith(fontSize: 28),
        (s) => s.copyWith(lineHeight: 2.2),
        (s) => s.copyWith(paragraphSpacing: 32),
        (s) => s.copyWith(horizontalPadding: 48),
      ]) {
        final generation = controller.layoutGeneration;
        preferences.update(update(preferences.value));
        await tester.pumpAndSettle();
        expect(controller.layoutGeneration, greaterThan(generation));
        _expectLegacyPage(tester, preferences.value, anchor);
      }
      for (final update in <ReaderSettings Function(ReaderSettings)>[
        (s) => s.copyWith(paper: ReaderPaper.warm),
        (s) => s.copyWith(themeMode: ReaderThemeMode.dark),
        (s) => s.copyWith(themeMode: ReaderThemeMode.system),
      ]) {
        final generation = controller.layoutGeneration;
        final before = _pageSignature(controller.inspectDisplayedPage()!.page);
        final brightness = Theme.of(
          tester.element(find.byType(PagedReaderViewport)),
        ).brightness;
        final ink = tester
            .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
            .textStyle
            .color;
        preferences.update(update(preferences.value));
        await tester.pumpAndSettle();
        // The legacy reader already re-lays out on a brightness change as
        // inherited Material typography changes. Paper alone keeps its layout.
        expect(
          controller.layoutGeneration,
          Theme.of(
                    tester.element(find.byType(PagedReaderViewport)),
                  ).brightness !=
                  brightness
              ? greaterThan(generation)
              : generation,
        );
        expect(_pageSignature(controller.inspectDisplayedPage()!.page), before);
        _expectLegacyPage(tester, preferences.value, anchor);
        if (preferences.value.themeMode == ReaderThemeMode.dark) {
          expect(
            tester
                .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
                .textStyle
                .color,
            isNot(ink),
          );
        }
      }
      var generation = controller.layoutGeneration;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(controller.layoutGeneration, greaterThan(generation));
      expect(
        Theme.of(tester.element(find.byType(PagedReaderViewport))).brightness,
        Brightness.dark,
      );
      _expectLegacyPage(tester, preferences.value, anchor);
      generation = controller.layoutGeneration;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      await tester.pumpAndSettle();
      expect(controller.layoutGeneration, greaterThan(generation));
      _expectLegacyPage(tester, preferences.value, anchor);
      generation = controller.layoutGeneration;
      for (final visible in [true, false]) {
        chrome.value = visible;
        await tester.pumpAndSettle();
        expect(controller.layoutGeneration, generation);
        _expectLegacyPage(tester, preferences.value, anchor);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      preferences.dispose();
      chrome.dispose();
    },
    variant: _platforms,
  );
}
