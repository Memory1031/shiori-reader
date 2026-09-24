import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';

import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'reader_preferences.dart';
import 'reader_theme.dart';
import 'reader_margin.dart';

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
        accent: appAccentOf(context),
      ),
      child: Builder(
        builder: (context) {
          final s = preferences.value;
          final l = AppLocalizations.of(context);
          Widget stepper(
            String label,
            double value,
            double min,
            double max,
            double step,
            ReaderSettings Function(double) change,
          ) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(ShioriShape.card),
            ),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                IconButton(
                  tooltip: l.readerDecrease(label),
                  onPressed: value <= min
                      ? null
                      : () {
                          preferences.update(
                            change(
                              double.parse(
                                (value - step)
                                    .clamp(min, max)
                                    .toStringAsFixed(1),
                              ),
                            ),
                          );
                          preferences.flush();
                        },
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    value.toStringAsFixed(step < 1 ? 1 : 0),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: l.readerIncrease(label),
                  onPressed: value >= max
                      ? null
                      : () {
                          preferences.update(
                            change(
                              double.parse(
                                (value + step)
                                    .clamp(min, max)
                                    .toStringAsFixed(1),
                              ),
                            ),
                          );
                          preferences.flush();
                        },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          );
          return Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ShioriShape.sheet),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                    child: Column(
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(
                              ShioriShape.indicator,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.readerSettings,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).closeButtonTooltip,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (preferences.failure != null)
                            TextButton(
                              onPressed: preferences.retry,
                              child: Text(
                                '${l.readerSettingsFailure} ${l.retryAction}',
                              ),
                            ),
                          const SizedBox(height: 16),
                          stepper(
                            l.readerFontSize,
                            s.fontSize,
                            14,
                            32,
                            1,
                            (v) => s.copyWith(fontSize: v),
                          ),
                          stepper(
                            l.readerLineHeight,
                            s.lineHeight,
                            1.2,
                            2.4,
                            .1,
                            (v) => s.copyWith(lineHeight: v),
                          ),
                          stepper(
                            l.readerParagraphSpacing,
                            s.paragraphSpacing,
                            0,
                            32,
                            2,
                            (v) => s.copyWith(paragraphSpacing: v),
                          ),
                          Text(
                            l.readerHorizontalPadding,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final entry in [
                                l.readerMarginVeryNarrow,
                                l.readerMarginNarrow,
                                l.readerMarginMedium,
                                l.readerMarginWide,
                                l.readerMarginVeryWide,
                              ].asMap().entries)
                                ChoiceChip(
                                  label: Text(entry.value),
                                  selected:
                                      readerMarginTier(s.horizontalPadding) ==
                                      entry.key,
                                  onSelected: (_) {
                                    preferences.update(
                                      s.copyWith(
                                        horizontalPadding:
                                            readerMarginValues[entry.key],
                                      ),
                                    );
                                    preferences.flush();
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(),
                          const SizedBox(height: 16),
                          Text(
                            l.readerColors,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final paper in ReaderPaper.values)
                                ChoiceChip(
                                  avatar: CircleAvatar(
                                    backgroundColor: paper == ReaderPaper.paper
                                        ? ShioriReaderPaper.paper
                                        : ShioriReaderPaper.warm,
                                  ),
                                  label: Text(
                                    paper == ReaderPaper.paper
                                        ? l.readerPaper
                                        : l.readerWarm,
                                  ),
                                  selected:
                                      s.themeMode != ReaderThemeMode.dark &&
                                      s.paper == paper &&
                                      (s.themeMode != ReaderThemeMode.system ||
                                          MediaQuery.platformBrightnessOf(
                                                context,
                                              ) !=
                                              Brightness.dark),
                                  onSelected: (_) => preferences.update(
                                    s.copyWith(
                                      paper: paper,
                                      themeMode: ReaderThemeMode.light,
                                    ),
                                  ),
                                ),
                              ChoiceChip(
                                avatar: const CircleAvatar(
                                  backgroundColor: ShioriReaderPaper.night,
                                ),
                                label: Text(l.readerNight),
                                selected:
                                    s.themeMode == ReaderThemeMode.dark ||
                                    (s.themeMode == ReaderThemeMode.system &&
                                        MediaQuery.platformBrightnessOf(
                                              context,
                                            ) ==
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
                                    : MediaQuery.platformBrightnessOf(
                                            context,
                                          ) ==
                                          Brightness.dark
                                    ? ReaderThemeMode.dark
                                    : ReaderThemeMode.light,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => preferences.update(
                              ReaderSettings(
                                controlsHintSeen: s.controlsHintSeen,
                              ),
                            ),
                            child: Text(l.readerReset),
                          ),
                        ],
                      ),
                    ),
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
