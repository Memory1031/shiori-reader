import 'package:shiori/features/reader/reader_margin.dart';
import '../../support/reader_actions.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_preferences.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/settings_panel.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

class Store implements SettingsStore {
  ReaderSettings value = ReaderSettings();
  final writes = <ReaderSettings>[];
  Completer<Result<ReaderSettings>>? loading;
  Completer<void>? saving;
  bool fail = false;
  @override
  Future<Result<ReaderSettings>> load({
    required CancellationToken cancellation,
  }) async => loading == null ? Success(value) : loading!.future;
  @override
  Future<Result<void>> save(
    ReaderSettings settings, {
    required CancellationToken cancellation,
  }) async {
    writes.add(settings);
    if (fail) {
      return Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.settingsWrite,
        ),
      );
    }
    await saving?.future;
    value = settings;
    return const Success(null);
  }
}

void main() {
  test(
    'legacy scroll settings open paged without changing other preferences',
    () async {
      final store = Store()
        ..value = ReaderSettings(
          mode: ReaderMode.scroll,
          fontSize: 26,
          paragraphSpacing: 24,
          paper: ReaderPaper.warm,
          themeMode: ReaderThemeMode.dark,
          controlsHintSeen: true,
        );
      final old = store.value;
      final preferences = ReaderPreferences(store);
      await preferences.load();
      expect(preferences.value, old.copyWith(mode: ReaderMode.paged));
      preferences.update(
        preferences.value.copyWith(fontSize: 28, mode: ReaderMode.scroll),
      );
      await preferences.flush();
      expect(store.value, old.copyWith(mode: ReaderMode.paged, fontSize: 28));
      preferences.dispose();
    },
  );

  testWidgets('failed save exposes retry and preserves preview', (
    tester,
  ) async {
    final store = Store()..fail = true;
    final preferences = ReaderPreferences(store);
    preferences.update(ReaderSettings(fontSize: 27));
    await preferences.flush();
    expect(preferences.failure?.kind, FailureKind.database);
    expect(preferences.value.fontSize, 27);
    store.fail = false;
    preferences.retry();
    await tester.pump();
    expect(preferences.failure, isNull);
    expect(store.value.fontSize, 27);
    preferences.dispose();
  });

  testWidgets(
    'system theme follows brightness and explicit light overrides it',
    (tester) async {
      final env = FixtureEnvironment();
      final store = Store();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => ReaderContentView(
              content: env.source.data.content(FixtureScenario.typography),
              settings: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(PagedReaderViewport))).brightness,
        Brightness.dark,
      );
      await openReaderSettings(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Paper'));
      await tester.tap(find.text('Paper'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(PagedReaderViewport))).brightness,
        Brightness.light,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
  );

  test(
    'v1 migrates without losing preferences; v2 clamps finite stored values',
    () {
      final old =
          ReaderSettings(fontSize: 26, themeMode: ReaderThemeMode.dark).toJson()
            ..['schemaVersion'] = 1
            ..remove('mode');
      final settings = ReaderSettings.fromJson(old);
      expect(settings.mode, ReaderMode.paged);
      expect(settings.fontSize, 26);
      expect(settings.themeMode, ReaderThemeMode.dark);
      expect(
        ReaderSettings.fromJson({
          ...settings.toJson(),
          'fontSize': 999,
          'lineHeight': -1,
        }).fontSize,
        32,
      );
      expect(
        ReaderSettings.fromJson({
          ...settings.toJson(),
          'lineHeight': -1,
        }).lineHeight,
        1.2,
      );
      expect(
        () => ReaderSettings.fromJson({
          ...settings.toJson(),
          'fontSize': double.nan,
        }),
        throwsFormatException,
      );
      final scroll = settings.copyWith(mode: ReaderMode.scroll);
      expect(ReaderSettings.fromJson(scroll.toJson()), scroll);
    },
  );

  testWidgets(
    'preview coalesces, slow writes stay ordered and dispose flushes latest',
    (tester) async {
      final store = Store();
      final preferences = ReaderPreferences(store);
      await preferences.load();
      for (var i = 0; i < 20; i++) {
        preferences.update(ReaderSettings(fontSize: 20 + i / 2));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(store.writes, isEmpty);
      store.saving = Completer<void>();
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.writes, hasLength(1));
      preferences.update(ReaderSettings(fontSize: 31));
      preferences.update(ReaderSettings(fontSize: 32));
      preferences.dispose();
      store.saving!.complete();
      await tester.pump();
      expect(store.writes.map((s) => s.fontSize), [29.5, 32]);
      expect(store.value.fontSize, 32);
      final reopened = ReaderPreferences(store);
      await reopened.load();
      expect(reopened.value.fontSize, 32);
      reopened.dispose();
    },
  );

  testWidgets('late settings load cannot replace a user preview', (
    tester,
  ) async {
    final store = Store()..loading = Completer<Result<ReaderSettings>>();
    final preferences = ReaderPreferences(store);
    final load = preferences.load();
    preferences.update(ReaderSettings(fontSize: 28));
    store.loading!.complete(Success(ReaderSettings(fontSize: 14)));
    await load;
    expect(preferences.value.fontSize, 28);
    preferences.dispose();
    await tester.pump();
  });

  testWidgets(
    'panel previews typography and theme; paged reflow keeps the visible anchor',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // One paragraph crosses default chunks and several pages before its
      // 60% target. Numbered Chinese text prevents a wrong page matching it.
      final source = List.generate(
        400,
        (i) => '第${i.toString().padLeft(3, '0')}段内合成文字星空山川😀。',
      ).join().runes.toList();
      final targetOffset = (source.length * .6).round();
      const marker = '📚';
      source[targetOffset] = marker.runes.single;
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.extremeParagraph),
        title: 'Settings reflow',
        blocks: [ParagraphBlock(text: String.fromCharCodes(source))],
      );
      final store = Store();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => ReaderContentView(content: content, settings: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = find.byType(PagedReaderViewport);
      var paged = tester.widget<PagedReaderViewport>(viewport);
      final controller = paged.controller;
      final readerState = tester.state(find.byType(ReaderContentView));
      final viewportState = tester.state(viewport);
      final chunks = ChunkIndex(
        content,
        maxCodePoints: paged.maxChunkCodePoints,
      );
      expect(chunks.chunks.length, greaterThan(1));
      expect(
        chunks.chunks.indexWhere(
          (c) => c.start <= targetOffset && c.end > targetOffset,
        ),
        greaterThan(0),
      );
      final anchor = ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks.first.blockKey,
        blockIndex: 0,
        blockFraction: .6,
        chapterFraction: .6 / content.blocks.length,
      );
      List<(int, int)> visibleRanges() => tester
          .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
          .map((w) => (w.blockOffset, w.blockOffset + w.text.runes.length))
          .toList();
      // The initial page ends before the target, rather than fitting the
      // shortened fixture or its deep anchor onto the first screen.
      expect(visibleRanges().last.$2, lessThan(targetOffset));
      final initialPaper = Theme.of(
        tester.element(viewport),
      ).scaffoldBackgroundColor;
      controller.restore(anchor);
      await tester.pump();
      expect(
        controller.isRestoring,
        isTrue,
        reason: 'deep seek still spans frames',
      );
      await tester.pumpAndSettle();

      void expectVisibleAnchor({
        required double font,
        required double height,
        required double scale,
      }) {
        expect(tester.state(find.byType(ReaderContentView)), same(readerState));
        expect(tester.state(viewport), same(viewportState));
        expect(
          tester.widget<PagedReaderViewport>(viewport).controller,
          same(controller),
        );
        expect(controller.isRestoring, isFalse);
        expect(controller.capture()!.blockKey, anchor.blockKey);
        final ranges = visibleRanges();
        expect(ranges.first.$1, greaterThan(0), reason: 'not the first page');
        expect(
          ranges.last.$2,
          lessThan(source.length),
          reason: 'more pages remain',
        );
        final fragment = find.byWidgetPredicate(
          (w) => w is ReaderLinkedText && w.text.contains(marker),
        );
        expect(fragment, findsOneWidget);
        final text = tester.widget<ReaderLinkedText>(fragment);
        expect(text.blockOffset, lessThanOrEqualTo(targetOffset));
        expect(
          text.blockOffset + text.text.runes.length,
          greaterThan(targetOffset),
        );
        expect(
          text.text,
          String.fromCharCodes(
            source.skip(text.blockOffset).take(text.text.runes.length),
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: fragment, matching: find.byType(RichText)),
        );
        expect(paragraph.text.style!.fontSize, font);
        expect(paragraph.text.style!.height, height);
        expect(paragraph.textScaler.scale(font), font * scale);
        // Source offsets are code points; RenderParagraph selections include
        // the indentation prefix and use UTF-16 (including the emoji marker).
        final start =
            text.prefix.length +
            String.fromCharCodes(
              source.sublist(text.blockOffset, targetOffset),
            ).length;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + marker.length),
        );
        expect(boxes, isNotEmpty);
        final page = tester.getRect(viewport);
        for (final box in boxes) {
          final rect = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
          expect(rect.isEmpty, isFalse);
          expect(page.contains(rect.topLeft), isTrue);
          expect(page.contains(rect.bottomRight), isTrue);
        }
      }

      expectVisibleAnchor(font: 20, height: 1.6, scale: 1);
      final beforeSettings = visibleRanges();
      final generation = controller.layoutGeneration;
      await openReaderSettings(tester);
      await tester.pumpAndSettle();
      final panel = tester.widget<ReaderSettingsPanel>(
        find.byType(ReaderSettingsPanel),
      );
      final updated = ReaderSettings(
        fontSize: 30,
        horizontalPadding: 40,
        paragraphSpacing: 24,
        lineHeight: 2,
        themeMode: ReaderThemeMode.dark,
      );
      panel.preferences.update(updated);
      await tester.pumpAndSettle();
      paged = tester.widget<PagedReaderViewport>(viewport);
      expect(paged.textStyle.fontSize, 30);
      expect(paged.textStyle.height, 2);
      expect(paged.paragraphSpacing, 24);
      expect(
        tester.getSize(viewport).width,
        400 -
            2 *
                readerHorizontalMargin(
                  panel.preferences.value,
                  MediaQuery.textScalerOf(tester.element(viewport)),
                  TextDirection.ltr,
                ),
      );
      expect(Theme.of(tester.element(viewport)).brightness, Brightness.dark);
      expect(
        Theme.of(tester.element(viewport)).scaffoldBackgroundColor,
        isNot(initialPaper),
      );
      expect(controller.capture()!.blockFraction, closeTo(.6, .002));
      expect(controller.layoutGeneration, greaterThan(generation));
      expect(visibleRanges(), isNot(beforeSettings));
      expectVisibleAnchor(font: 30, height: 2, scale: 1);
      Navigator.of(tester.element(find.byType(ReaderSettingsPanel))).pop();
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockFraction, closeTo(.6, .002));
      expectVisibleAnchor(font: 30, height: 2, scale: 1);
      final beforeRotation = visibleRanges();
      final rotationGeneration = controller.layoutGeneration;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(900, 400);
      await tester.pumpAndSettle();
      paged = tester.widget<PagedReaderViewport>(viewport);
      expect(paged.controller.capture()!.blockFraction, closeTo(.6, .004));
      expect(controller.layoutGeneration, greaterThan(rotationGeneration));
      expect(visibleRanges(), isNot(beforeRotation));
      expectVisibleAnchor(font: 30, height: 2, scale: 2);
      final rotatedRanges = visibleRanges();
      // Continue reading through actual keyboard input, then return to the
      // target before checking that the rotated settings panel still opens.
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(controller.capture()!.blockFraction, greaterThan(.6));
      expect(visibleRanges(), isNot(rotatedRanges));
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expectVisibleAnchor(font: 30, height: 2, scale: 2);
      await openReaderSettings(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSettingsPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(store.value.mode, ReaderMode.paged);
      expect(store.value.fontSize, updated.fontSize);
      expect(store.value.horizontalPadding, updated.horizontalPadding);
      expect(store.value.paragraphSpacing, updated.paragraphSpacing);
      expect(store.value.lineHeight, updated.lineHeight);
      expect(store.value.themeMode, updated.themeMode);
      expect(store.writes.last, store.value);
    },
  );
}
