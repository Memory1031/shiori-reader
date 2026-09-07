import 'package:flutter/material.dart';

import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'reader_preferences.dart';

class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({super.key, required this.preferences});
  final ReaderPreferences preferences;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) {
      final s = preferences.value;
      final l = AppLocalizations.of(context);
      Widget slider(
        String label,
        double value,
        double min,
        double max,
        ReaderSettings Function(double) change,
      ) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label ${value.toStringAsFixed(1)}'),
          Slider(
            semanticFormatterCallback: (v) => '$label ${v.toStringAsFixed(1)}',
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: (v) => preferences.update(
              change(v.isFinite ? v.clamp(min, max) : value),
            ),
            onChangeEnd: (_) => preferences.flush(),
          ),
        ],
      );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.readerSettings,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (preferences.failure != null)
                TextButton(
                  onPressed: preferences.retry,
                  child: Text('${l.readerSettingsFailure} ${l.retryAction}'),
                ),
              slider(
                l.readerFontSize,
                s.fontSize,
                14,
                32,
                (v) => s.copyWith(fontSize: v),
              ),
              slider(
                l.readerLineHeight,
                s.lineHeight,
                1.2,
                2.4,
                (v) => s.copyWith(lineHeight: v),
              ),
              slider(
                l.readerParagraphSpacing,
                s.paragraphSpacing,
                0,
                32,
                (v) => s.copyWith(paragraphSpacing: v),
              ),
              slider(
                l.readerHorizontalPadding,
                s.horizontalPadding,
                12,
                48,
                (v) => s.copyWith(horizontalPadding: v),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final mode in ReaderThemeMode.values)
                    ChoiceChip(
                      label: Text(switch (mode) {
                        ReaderThemeMode.system => l.readerThemeSystem,
                        ReaderThemeMode.light => l.readerThemeLight,
                        ReaderThemeMode.dark => l.readerThemeDark,
                      }),
                      selected: s.themeMode == mode,
                      onSelected: (_) =>
                          preferences.update(s.copyWith(themeMode: mode)),
                    ),
                ],
              ),
              TextButton(
                onPressed: () => preferences.update(ReaderSettings()),
                child: Text(l.readerReset),
              ),
            ],
          ),
        ),
      );
    },
  );
}
