import 'package:flutter/material.dart';

import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'reader_preferences.dart';
import 'reader_theme.dart';

class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({super.key, required this.preferences});
  final ReaderPreferences preferences;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => Theme(
      data: readerTheme(
        preferences.value,
        MediaQuery.platformBrightnessOf(context),
      ),
      child: Builder(
        builder: (context) {
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    value.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              Slider(
                semanticFormatterCallback: (v) =>
                    '$label ${v.toStringAsFixed(1)}',
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        final defaults = ReaderSettings();
                        preferences.update(
                          s.copyWith(
                            fontSize: defaults.fontSize,
                            lineHeight: defaults.lineHeight,
                            paragraphSpacing: defaults.paragraphSpacing,
                            horizontalPadding: defaults.horizontalPadding,
                          ),
                        );
                        preferences.flush();
                      },
                      child: Text(l.readerResetTypography),
                    ),
                  ),
                  if (preferences.failure != null)
                    TextButton(
                      onPressed: preferences.retry,
                      child: Text(
                        '${l.readerSettingsFailure} ${l.retryAction}',
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mode in ReaderMode.values)
                        ChoiceChip(
                          label: Text(
                            mode == ReaderMode.paged
                                ? l.pagedReading
                                : l.scrollReading,
                          ),
                          selected: s.mode == mode,
                          onSelected: (_) =>
                              preferences.update(s.copyWith(mode: mode)),
                        ),
                    ],
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
                  Text(
                    l.readerColors,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final paper in ReaderPaper.values)
                        ChoiceChip(
                          label: Text(
                            paper == ReaderPaper.paper
                                ? l.readerPaper
                                : l.readerWarm,
                          ),
                          selected:
                              s.themeMode != ReaderThemeMode.dark &&
                              s.paper == paper &&
                              (s.themeMode != ReaderThemeMode.system ||
                                  MediaQuery.platformBrightnessOf(context) !=
                                      Brightness.dark),
                          onSelected: (_) => preferences.update(
                            s.copyWith(
                              paper: paper,
                              themeMode: ReaderThemeMode.light,
                            ),
                          ),
                        ),
                      ChoiceChip(
                        label: Text(l.readerNight),
                        selected:
                            s.themeMode == ReaderThemeMode.dark ||
                            (s.themeMode == ReaderThemeMode.system &&
                                MediaQuery.platformBrightnessOf(context) ==
                                    Brightness.dark),
                        onSelected: (_) => preferences.update(
                          s.copyWith(themeMode: ReaderThemeMode.dark),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.readerThemeSystem),
                    subtitle: Text(
                      s.paper == ReaderPaper.paper
                          ? l.readerPaper
                          : l.readerWarm,
                    ),
                    value: s.themeMode == ReaderThemeMode.system,
                    onChanged: (follow) => preferences.update(
                      s.copyWith(
                        themeMode: follow
                            ? ReaderThemeMode.system
                            : MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark
                            ? ReaderThemeMode.dark
                            : ReaderThemeMode.light,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => preferences.update(
                      ReaderSettings(controlsHintSeen: s.controlsHintSeen),
                    ),
                    child: Text(l.readerReset),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
