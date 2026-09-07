import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_preferences.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/settings_panel.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/reader_viewport.dart';

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
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Light'));
      await tester.tap(find.text('Light'));
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
    'panel previews typography and theme; both modes preserve anchor at large scale',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final env = FixtureEnvironment();
      final store = Store();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => ReaderContentView(
              content: env.source.data.content(
                FixtureScenario.extremeParagraph,
              ),
              settings: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var paged = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      final content = paged.content;
      final anchor = ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks.first.blockKey,
        blockIndex: 0,
        blockFraction: .6,
        chapterFraction: .6 / content.blocks.length,
      );
      paged.controller.restore(anchor);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      final panel = tester.widget<ReaderSettingsPanel>(
        find.byType(ReaderSettingsPanel),
      );
      panel.preferences.update(
        ReaderSettings(
          fontSize: 30,
          horizontalPadding: 40,
          paragraphSpacing: 24,
          lineHeight: 2,
          themeMode: ReaderThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      paged = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      expect(paged.textStyle.fontSize, 30);
      expect(paged.paragraphSpacing, 24);
      expect(tester.getSize(find.byType(PagedReaderViewport)).width, 320);
      expect(
        Theme.of(tester.element(find.byType(PagedReaderViewport))).brightness,
        Brightness.dark,
      );
      expect(paged.controller.capture()!.blockFraction, closeTo(.6, .002));
      Navigator.of(tester.element(find.byType(ReaderSettingsPanel))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scroll'));
      await tester.pumpAndSettle();
      var scroll = tester.widget<ReaderViewport>(find.byType(ReaderViewport));
      expect(scroll.controller.capture()!.blockFraction, closeTo(.6, .002));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(900, 400);
      await tester.pumpAndSettle();
      scroll = tester.widget<ReaderViewport>(find.byType(ReaderViewport));
      expect(scroll.controller.capture()!.blockFraction, closeTo(.6, .004));
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(store.value.mode, ReaderMode.scroll);
      await env.close();
    },
  );
}
