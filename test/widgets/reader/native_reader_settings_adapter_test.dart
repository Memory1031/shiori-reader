import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/native_reader_settings_adapter.dart';
import 'package:shiori/features/reader/reader_margin.dart';
import 'package:shiori/features/reader/reader_theme.dart';

import '../../support/legacy_native_reader_settings.dart';

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
