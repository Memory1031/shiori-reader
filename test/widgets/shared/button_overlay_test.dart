import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/domain/models/app_settings.dart';

void main() {
  const hovered = {WidgetState.hovered};
  const focused = {WidgetState.focused};
  const pressed = {WidgetState.pressed};

  test('button themes use the accent tints of the other controls', () {
    for (final accent in AppAccent.values) {
      for (final brightness in Brightness.values) {
        final theme = shioriTheme(brightness, accent: accent);
        final reason = '$accent $brightness';
        final styles = [
          theme.textButtonTheme.style!,
          theme.outlinedButtonTheme.style!,
          theme.iconButtonTheme.style!,
          theme.segmentedButtonTheme.style!,
          if (brightness == Brightness.light) theme.filledButtonTheme.style!,
        ];
        for (final style in styles) {
          final overlay = style.overlayColor!;
          expect(overlay.resolve(hovered), theme.hoverColor, reason: reason);
          expect(overlay.resolve(focused), theme.focusColor, reason: reason);
          expect(
            overlay.resolve(pressed),
            theme.highlightColor,
            reason: reason,
          );
          expect(overlay.resolve({}), isNull, reason: reason);
        }
        // The tints are the accent's, not the ink's.
        expect(
          theme.hoverColor.withValues(alpha: 1),
          theme.colorScheme.primary.withValues(alpha: 1),
          reason: reason,
        );
        if (brightness == Brightness.dark) {
          // A dark filled button is the accent; it keeps its own overlay.
          expect(theme.filledButtonTheme.style!.overlayColor, isNull);
        }
      }
    }
  });

  testWidgets('buttons hover in the accent; local colours keep theirs', (
    tester,
  ) async {
    final theme = shioriTheme(Brightness.light);
    final error = theme.colorScheme.error;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              TextButton(
                key: const ValueKey('text'),
                onPressed: () {},
                child: const Text('Text'),
              ),
              OutlinedButton(
                key: const ValueKey('outlined'),
                onPressed: () {},
                child: const Text('Outlined'),
              ),
              FilledButton(
                key: const ValueKey('filled'),
                onPressed: () {},
                child: const Text('Filled'),
              ),
              IconButton(
                key: const ValueKey('icon'),
                onPressed: () {},
                icon: const Icon(Icons.more_horiz),
              ),
              const BackButton(key: ValueKey('back')),
              SegmentedButton<bool>(
                key: const ValueKey('segmented'),
                segments: const [
                  ButtonSegment(value: true, label: Text('Grid')),
                  ButtonSegment(value: false, label: Text('List')),
                ],
                selected: const {true},
                onSelectionChanged: (_) {},
              ),
              TextButton(
                key: const ValueKey('error'),
                style: TextButton.styleFrom(foregroundColor: error),
                onPressed: () {},
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
    Color? hoverOf(String key) => tester
        .widget<InkWell>(
          find
              .descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(InkWell),
              )
              .first,
        )
        .overlayColor!
        .resolve(hovered);
    for (final key in [
      'text',
      'outlined',
      'filled',
      'icon',
      'back',
      'segmented',
    ]) {
      expect(hoverOf(key), theme.hoverColor, reason: key);
    }
    expect(hoverOf('error')!.withValues(alpha: 1), error.withValues(alpha: 1));
  });
}
