import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_preferences.dart';
import 'package:shiori/features/reader/settings_panel.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

Future<ReaderPreferences> _pumpPanel(
  WidgetTester tester,
  ReaderSettings settings, {
  String locale = 'en',
  double textScale = 1,
  bool txt = false,
}) async {
  final preferences = ReaderPreferences(null)..value = settings;
  addTearDown(preferences.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ReaderSettingsPanel(preferences: preferences, txt: txt),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return preferences;
}

Finder get _reset => find.byKey(const ValueKey('reader-settings-reset'));

void main() {
  for (final locale in ['zh', 'en']) {
    testWidgets('TXT blank line choice at narrow width in $locale', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preferences = await _pumpPanel(
        tester,
        ReaderSettings(),
        locale: locale,
        textScale: 1.3,
        txt: true,
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(ReaderSettingsPanel)),
      );
      expect(preferences.value.txtBlankLines, TxtBlankLineMode.merge);
      final preserve = find.text(l.readerTxtBlankLinesPreserve);
      expect(
        tester.renderObject<RenderParagraph>(preserve).didExceedMaxLines,
        isFalse,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.text(l.readerTxtBlankLinesMerge),
            )
            .didExceedMaxLines,
        isFalse,
      );
      await tester.ensureVisible(preserve);
      await tester.tap(preserve);
      await tester.pumpAndSettle();
      expect(preferences.value.txtBlankLines, TxtBlankLineMode.preserve);
      expect(
        ReaderSettings.fromJson(preferences.value.toJson()).txtBlankLines,
        TxtBlankLineMode.preserve,
      );
      await tester.tap(find.text(l.readerTxtBlankLinesMerge));
      await tester.pumpAndSettle();
      expect(preferences.value.txtBlankLines, TxtBlankLineMode.merge);
      expect(tester.takeException(), isNull);
      await _pumpPanel(tester, preferences.value, locale: locale);
      expect(find.text(l.readerTxtBlankLines), findsNothing);
    });
  }
  for (final (width, locale, textScale, platform) in [
    (360.0, 'zh', 1.0, TargetPlatform.android),
    (320.0, 'en', 1.3, TargetPlatform.iOS),
  ]) {
    testWidgets(
      'six touch targets at $width/$locale/$textScale',
      (tester) async {
        tester.view
          ..physicalSize = Size(width, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final preferences = await _pumpPanel(
          tester,
          ReaderSettings(),
          locale: locale,
          textScale: textScale,
        );
        final strings = AppLocalizations.of(
          tester.element(find.byType(ReaderSettingsPanel)),
        );
        final labels = [
          strings.readerFontSize,
          strings.readerLineHeight,
          strings.readerParagraphSpacing,
        ];
        final steps = [1.0, .1, 2.0];
        final values = [
          () => preferences.value.fontSize,
          () => preferences.value.lineHeight,
          () => preferences.value.paragraphSpacing,
        ];
        for (var i = 0; i < labels.length; i++) {
          for (final increase in [false, true]) {
            final control = find.bySemanticsLabel(
              increase
                  ? strings.readerIncrease(labels[i])
                  : strings.readerDecrease(labels[i]),
            );
            await tester.ensureVisible(control);
            await tester.pumpAndSettle();
            final rect = tester.getRect(control);
            expect(rect.size, const Size(48, 48));
            final before = values[i]();
            // 22px from center lies outside the old 40px target.
            await tester.tapAt(rect.center + Offset(increase ? 22 : -22, 0));
            await tester.pumpAndSettle();
            expect(
              values[i](),
              closeTo(before + (increase ? steps[i] : -steps[i]), .001),
            );
            expect(tester.takeException(), isNull);
          }
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'pointer-first step buttons stay compact',
    (tester) async {
      await _pumpPanel(tester, ReaderSettings());
      for (final label in ['Font size', 'Line height', 'Paragraph spacing']) {
        for (final action in ['Decrease', 'Increase']) {
          expect(
            tester.getSize(find.bySemanticsLabel('$action $label')),
            const Size(40, 40),
          );
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'holding the expanded edge repeats and releasing stops',
    (tester) async {
      final preferences = await _pumpPanel(
        tester,
        ReaderSettings(lineHeight: 1.6),
      );
      final increase = find.bySemanticsLabel('Increase Line height');
      final gesture = await tester.startGesture(
        tester.getCenter(increase) + const Offset(22, 0),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
      expect(preferences.value.lineHeight, 1.7);
      await tester.pump(const Duration(milliseconds: 90));
      expect(preferences.value.lineHeight, 1.8);
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 900));
      expect(preferences.value.lineHeight, 1.8);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

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

  testWidgets(
    'holding a step repeats until the range limit',
    (tester) async {
      final preferences = await _pumpPanel(
        tester,
        ReaderSettings(lineHeight: 2),
      );
      final increase = find.bySemanticsLabel('Increase Line height');
      final gesture = await tester.startGesture(tester.getCenter(increase));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
      // The first step lands with the hold; repeats follow while it lasts.
      expect(preferences.value.lineHeight, 2.1);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 90));
      }
      expect(preferences.value.lineHeight, 2.4);
      expect(
        tester
            .widget<IconButton>(
              find.descendant(of: increase, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNull,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(preferences.value.lineHeight, 2.4);

      // A tap steps once.
      await tester.tap(find.bySemanticsLabel('Decrease Line height'));
      await tester.pumpAndSettle();
      expect(preferences.value.lineHeight, 2.3);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'all typography limits keep the enlarged buttons disabled',
    (tester) async {
      for (final maximum in [false, true]) {
        final settings = ReaderSettings(
          fontSize: maximum ? 32 : 14,
          lineHeight: maximum ? 2.4 : 1.2,
          paragraphSpacing: maximum ? 32 : 0,
        );
        final preferences = await _pumpPanel(tester, settings);
        for (final label in ['Font size', 'Line height', 'Paragraph spacing']) {
          final control = find.bySemanticsLabel(
            '${maximum ? 'Increase' : 'Decrease'} $label',
          );
          expect(
            tester
                .widget<IconButton>(
                  find.descendant(
                    of: control,
                    matching: find.byType(IconButton),
                  ),
                )
                .onPressed,
            isNull,
          );
          await tester.tapAt(tester.getCenter(control) + const Offset(22, 0));
          await tester.pumpAndSettle();
          expect(preferences.value, settings);
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

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
}
