import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_preferences.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/settings_panel.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

import '../../support/reader_actions.dart';
import 'settings_test.dart' show Store;

Future<ReaderPreferences> _pumpPanel(
  WidgetTester tester,
  ReaderSettings settings,
) async {
  final preferences = ReaderPreferences(null)..value = settings;
  addTearDown(preferences.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ReaderSettingsPanel(preferences: preferences)),
    ),
  );
  await tester.pumpAndSettle();
  return preferences;
}

Finder get _reset => find.byKey(const ValueKey('reader-settings-reset'));

void main() {
  testWidgets('reset offers undo until something else changes', (tester) async {
    final custom = ReaderSettings(
      fontSize: 26,
      lineHeight: 2,
      pageTurn: PageTurnStyle.slide,
      paper: ReaderPaper.warm,
      themeMode: ReaderThemeMode.light,
      controlsHintSeen: true,
    );
    final preferences = await _pumpPanel(tester, custom);

    await tester.tap(_reset);
    await tester.pumpAndSettle();
    expect(preferences.value, ReaderSettings(controlsHintSeen: true));
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(preferences.value, custom);
    expect(find.text('Reset defaults'), findsOneWidget);

    await tester.tap(_reset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cover'));
    await tester.pumpAndSettle();
    // A later edit retires the undo; the defaults stay otherwise.
    expect(find.text('Undo'), findsNothing);
    expect(preferences.value.pageTurn, PageTurnStyle.cover);
    expect(preferences.value.fontSize, ReaderSettings().fontSize);

    // Already at the defaults: nothing left to reset.
    preferences.update(ReaderSettings(controlsHintSeen: true));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(_reset).onPressed, isNull);
  });

  testWidgets('holding a step repeats until the range limit', (tester) async {
    final preferences = await _pumpPanel(tester, ReaderSettings(lineHeight: 2));
    final increase = find.bySemanticsLabel('Increase Line height');
    final gesture = await tester.startGesture(tester.getCenter(increase));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    // The first step lands with the hold; repeats follow while it lasts.
    expect(preferences.value.lineHeight, 2.1);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
    expect(preferences.value.lineHeight, 2.4);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(preferences.value.lineHeight, 2.4);

    // A tap steps once.
    await tester.tap(find.bySemanticsLabel('Decrease Line height'));
    await tester.pumpAndSettle();
    expect(preferences.value.lineHeight, 2.3);
  });

  testWidgets('the font slider and its end glyphs change the size', (
    tester,
  ) async {
    final preferences = await _pumpPanel(tester, ReaderSettings(fontSize: 20));
    await tester.tap(find.bySemanticsLabel('Increase Font size'));
    await tester.pumpAndSettle();
    expect(preferences.value.fontSize, 21);
    final slider = find.byType(Slider);
    await tester.tapAt(tester.getTopRight(slider).translate(-4, 12));
    await tester.pumpAndSettle();
    expect(preferences.value.fontSize, 32);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.bySemanticsLabel('Increase Font size'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('swatches keep following the system when they agree with it', (
    tester,
  ) async {
    final preferences = await _pumpPanel(tester, ReaderSettings());
    expect(preferences.value.themeMode, ReaderThemeMode.system);
    await tester.tap(find.text('Warm paper'));
    await tester.pumpAndSettle();
    expect(preferences.value.paper, ReaderPaper.warm);
    expect(preferences.value.themeMode, ReaderThemeMode.system);
    // Night disagrees with a light system, so it pins the dark theme.
    await tester.tap(find.text('Night'));
    await tester.pumpAndSettle();
    expect(preferences.value.themeMode, ReaderThemeMode.dark);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Night')),
      containsSemantics(isSelected: true),
    );
    // Turning following back on keeps the chosen day paper.
    await tester.tap(find.text('Follow system'));
    await tester.pumpAndSettle();
    expect(preferences.value.themeMode, ReaderThemeMode.system);
    expect(preferences.value.paper, ReaderPaper.warm);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Warm paper')),
      containsSemantics(isSelected: true),
    );
  });

  testWidgets('the settings sheet only lightly dims the page', (tester) async {
    final env = FixtureEnvironment();
    final store = Store()..value = ReaderSettings(controlsHintSeen: true);
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
    await openReaderSettings(tester);
    await tester.pumpAndSettle();
    final barrier = tester
        .widgetList<ModalBarrier>(find.byType(ModalBarrier))
        .last;
    expect(barrier.color, isNotNull);
    expect(barrier.color!.a, lessThan(.3));
    expect(barrier.color!.a, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await env.close();
  });
}
