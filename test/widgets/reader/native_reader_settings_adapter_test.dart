import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/native_reader_settings_adapter.dart';
import 'package:shiori/features/reader/reader_margin.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/features/reader/reader_preferences.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import '../../support/legacy_native_reader_settings.dart';
import '../../data/local/support/synthetic_font.dart';

// A scale whose ratio varies by input size catches accidental prescaling too.
class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize + 8;
  @override
  double get textScaleFactor => 1.4;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('margin measures the effective body face and fallback once', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await (FontLoader('MarginLatin')..addFont(
            Future.value(ByteData.sublistView(syntheticFont(advance: 900))),
          ))
          .load();
      await (FontLoader('MarginCJK')..addFont(
            Future.value(
              ByteData.sublistView(syntheticFont(advance: 400, cjk: true)),
            ),
          ))
          .load();
    });
    final settings = ReaderSettings(horizontalPadding: 48);
    for (final typography in const [
      TextStyle(fontFamily: 'MarginCJK'),
      TextStyle(fontFamily: 'MarginLatin', fontFamilyFallback: ['MarginCJK']),
    ]) {
      final theme = ThemeData().copyWith(
        textTheme: TextTheme(bodyLarge: typography),
      );
      final actual = NativeReaderSettingsAdapter.resolve(
        settings,
        theme: theme,
        textScaler: const TextScaler.linear(1.5),
        textDirection: TextDirection.ltr,
        explicitUiTypeface: true,
      );
      // Four 400/1000-em glyphs at 20sp, scaled once: one cell is 12dp.
      expect(
        actual.horizontalMargin,
        closeTo(42, .01),
        reason: typography.toString(),
      );
      final medium = NativeReaderSettingsAdapter.resolve(
        settings.copyWith(horizontalPadding: 30),
        theme: theme,
        textScaler: const _NonlinearScaler(),
        textDirection: TextDirection.rtl,
        explicitUiTypeface: true,
      );
      expect(medium.horizontalMargin, 30);
    }
  });

  testWidgets(
    'Windows font-based gutters reflow without losing the anchor',
    (tester) async {
      await tester.runAsync(() async {
        await (FontLoader('Microsoft YaHei UI')..addFont(
              Future.value(
                ByteData.sublistView(syntheticFont(advance: 400, cjk: true)),
              ),
            ))
            .load();
      });
      tester.view
        ..physicalSize = const Size(400, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preferences = ReaderPreferences(null)
        ..value = ReaderSettings(horizontalPadding: 12, controlsHintSeen: true);
      final controller = PagedReaderController();
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.longChapter),
        title: 'Font and anchor',
        blocks: [
          for (var i = 0; i < 10; i++) ParagraphBlock(text: '正文排版' * 100),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        preferences.dispose();
      });
      await tester.pumpWidget(
        ShioriApp(
          routes: AppRoutes(
            home: (_) => ReaderContentView(
              content: content,
              preferences: preferences,
              viewportController: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(PagedReaderViewport)).width,
        closeTo(356, .01),
      );
      final anchor = ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks[5].blockKey,
        blockIndex: 5,
        blockFraction: .4,
        chapterFraction: .54,
      );
      final restored = controller.restoreConfirmed(
        anchor,
        isCurrent: () => true,
      );
      await tester.pumpAndSettle();
      expect(await restored, isTrue);
      preferences.update(preferences.value.copyWith(fontSize: 28));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(PagedReaderViewport)).width,
        closeTo(362.4, .01),
      );
      expect(controller.capture()!.blockKey, anchor.blockKey);
      expect(controller.capture()!.blockFraction, closeTo(.4, .002));
      expect(controller.usedFallback, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  test('native mappings equal the independent legacy computations', () {
    var comparisons = 0;
    for (final (font, line, spacing) in [
      (14.0, 1.2, 0.0),
      (20.0, 1.6, 20.0),
      (32.0, 2.4, 32.0),
    ]) {
      for (final padding in [...readerMarginValues, 40.0]) {
        for (final scaler in const [
          TextScaler.noScaling,
          TextScaler.linear(1.5),
          TextScaler.linear(2),
          _NonlinearScaler(),
        ]) {
          for (final direction in TextDirection.values) {
            for (final explicit in [false, true]) {
              for (final mode in ReaderThemeMode.values) {
                for (final paper in ReaderPaper.values) {
                  for (final system in Brightness.values) {
                    final settings = ReaderSettings(
                      fontSize: font,
                      lineHeight: line,
                      paragraphSpacing: spacing,
                      horizontalPadding: padding,
                      themeMode: mode,
                      paper: paper,
                    );
                    final readingTheme = readerTheme(settings, system);
                    final theme = readingTheme.copyWith(
                      textTheme: readingTheme.textTheme.copyWith(
                        bodyLarge: const TextStyle(
                          fontFamily: 'Synthetic UI Face',
                          fontFamilyFallback: [
                            'Synthetic CJK',
                            'Synthetic Emoji',
                          ],
                          // These unrelated typography fields were never copied.
                          fontSize: 47,
                          height: 3,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                    );
                    final actual = NativeReaderSettingsAdapter.resolve(
                      settings,
                      theme: theme,
                      textScaler: scaler,
                      textDirection: direction,
                      explicitUiTypeface: explicit,
                    );
                    expect(
                      actual.bodyStyle,
                      legacyNativeBodyStyle(
                        settings,
                        theme,
                        explicitUiTypeface: explicit,
                      ),
                    );
                    expect(
                      actual.horizontalMargin,
                      legacyNativeMargin(settings, scaler, direction),
                    );
                    expect(actual.paragraphSpacing, spacing);
                    expect(actual.bodyStyle.fontSize, font);
                    expect(
                      scaler.scale(actual.bodyStyle.fontSize!),
                      scaler.scale(font),
                    );
                    expect(actual.bodyStyle.fontWeight, isNull);
                    expect(actual.bodyStyle.letterSpacing, isNull);
                    comparisons++;
                  }
                }
              }
            }
          }
        }
      }
    }
    expect(comparisons, 3456);
  });

  test(
    'null UI typography and interaction preferences preserve old layout inputs',
    () {
      final theme = ThemeData().copyWith(textTheme: const TextTheme());
      final base = ReaderSettings();
      expect(theme.textTheme.bodyLarge, isNull);
      for (final turn in PageTurnStyle.values) {
        final actual = NativeReaderSettingsAdapter.resolve(
          base.copyWith(
            pageTurn: turn,
            mode: ReaderMode.scroll,
            controlsHintSeen: true,
          ),
          theme: theme,
          textScaler: TextScaler.noScaling,
          textDirection: TextDirection.ltr,
          explicitUiTypeface: true,
        );
        expect(
          actual.bodyStyle,
          legacyNativeBodyStyle(base, theme, explicitUiTypeface: true),
        );
        expect(
          actual.horizontalMargin,
          legacyNativeMargin(base, TextScaler.noScaling, TextDirection.ltr),
        );
        expect(actual.paragraphSpacing, base.paragraphSpacing);
      }
    },
  );
}
