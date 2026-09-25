import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/shiori_sheet.dart';
import 'reader_margin.dart';
import 'reader_preferences.dart';
import 'reader_theme.dart';

/// Opens the typography panel as a sheet over a lightly dimmed page, so paper
/// and type changes stay readable, and flushes the edits when it closes.
Future<void> showReaderSettings(
  BuildContext context,
  ReaderPreferences preferences,
) async {
  await showShioriSheet<void>(
    context,
    barrierColor: Colors.black.withValues(alpha: .18),
    // The panel owns the handle so it follows live reading-theme changes.
    owned: true,
    builder: (sheet) => ReaderSettingsPanel(
      preferences: preferences,
      onDone: () => Navigator.of(sheet).pop(),
      sheet: true,
    ),
  );
  await preferences.flush();
}

/// Reading colours and typography. Placement agnostic: [sheet] adds the drag
/// handle, rounded top and lift a modal host needs; a docked host omits them.
class ReaderSettingsPanel extends StatefulWidget {
  const ReaderSettingsPanel({
    super.key,
    required this.preferences,
    this.onDone,
    this.sheet = false,
  });
  final ReaderPreferences preferences;

  /// Close control for a docked host; a sheet closes by drag or outside tap.
  final VoidCallback? onDone;
  final bool sheet;

  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  /// Settings before the last reset, offered back while nothing else changed.
  ReaderSettings? _beforeReset, _afterReset;

  ReaderPreferences get _preferences => widget.preferences;

  ReaderSettings _defaults(ReaderSettings s) =>
      ReaderSettings(controlsHintSeen: s.controlsHintSeen);

  void _reset(ReaderSettings s) {
    _preferences.update(_defaults(s));
    setState(() {
      _beforeReset = s;
      _afterReset = _preferences.value;
    });
  }

  void _undoReset() {
    final before = _beforeReset;
    setState(() => _beforeReset = _afterReset = null);
    if (before != null) _preferences.update(before);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _preferences,
    builder: (context, _) => Theme(
      data: readerTheme(
        _preferences.value,
        MediaQuery.platformBrightnessOf(context),
        accent: appAccentOf(context),
      ),
      child: Builder(builder: _panel),
    ),
  );

  Widget _panel(BuildContext context) {
    final s = _preferences.value;
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Any later edit retires the undo for good, even one that lands back
    // on the defaults.
    if (_afterReset != null && s != _afterReset) {
      _beforeReset = _afterReset = null;
    }
    final canUndo = _beforeReset != null;
    final isDefault = s == _defaults(s).copyWith(mode: s.mode);

    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        ShioriSpace.page,
        widget.sheet ? ShioriSpace.medium : ShioriSpace.small,
        ShioriSpace.small,
        0,
      ),
      child: Column(
        children: [
          if (widget.sheet) ...[
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(ShioriShape.indicator),
              ),
            ),
            const SizedBox(height: ShioriSpace.tight),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  l.readerSettings,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton(
                key: const ValueKey('reader-settings-reset'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: canUndo
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                onPressed: canUndo
                    ? _undoReset
                    : isDefault
                    ? null
                    : () => _reset(s),
                child: Text(canUndo ? l.readerUndo : l.readerReset),
              ),
              if (widget.onDone != null && !widget.sheet)
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: widget.onDone,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ],
      ),
    );

    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ShioriSpace.page,
        ShioriSpace.small,
        ShioriSpace.page,
        ShioriSpace.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_preferences.failure != null) ...[
            _FailureBanner(
              message: l.readerSettingsFailure,
              action: l.retryAction,
              onRetry: _preferences.retry,
            ),
            const SizedBox(height: ShioriSpace.medium),
          ],
          _Appearance(settings: s, onChanged: _preferences.update),
          Divider(height: ShioriSpace.item, color: scheme.outlineVariant),
          _Typography(settings: s, onChanged: _preferences.update),
        ],
      ),
    );

    final size = MediaQuery.sizeOf(context);
    return Material(
      // Night paper sits a step below the dark surface, so the panel lifts
      // off the page by tone where a shadow would not show.
      color: theme.brightness == Brightness.dark
          ? scheme.surface
          : theme.scaffoldBackgroundColor,
      elevation: widget.sheet ? 8 : 0,
      shadowColor: Colors.black.withValues(alpha: .3),
      borderRadius: widget.sheet
          ? const BorderRadius.vertical(top: Radius.circular(ShioriShape.sheet))
          : null,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: ConstrainedBox(
          // A sheet sizes to its content but leaves the page mostly in view.
          constraints: BoxConstraints(
            maxHeight: widget.sheet ? size.height * .72 : double.infinity,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paper swatches plus the follow-system switch.
///
/// A swatch picks the look to show now. Following the system survives the
/// pick when the system already shows that brightness, so choosing a day
/// paper while the system is light keeps night switching automatic.
class _Appearance extends StatelessWidget {
  const _Appearance({required this.settings, required this.onChanged});
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = settings;
    final systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final following = s.themeMode == ReaderThemeMode.system;
    final dark = switch (s.themeMode) {
      ReaderThemeMode.system => systemDark,
      ReaderThemeMode.light => false,
      ReaderThemeMode.dark => true,
    };
    ReaderSettings day(ReaderPaper paper) => s.copyWith(
      paper: paper,
      themeMode: following && !systemDark
          ? ReaderThemeMode.system
          : ReaderThemeMode.light,
    );
    final swatches = [
      _PaperSwatch(
        label: l.readerPaper,
        paper: ShioriReaderPaper.paper,
        ink: ShioriPalette.light.ink,
        selected: !dark && s.paper == ReaderPaper.paper,
        onTap: () => onChanged(day(ReaderPaper.paper)),
      ),
      _PaperSwatch(
        label: l.readerWarm,
        paper: ShioriReaderPaper.warm,
        ink: ShioriPalette.light.ink,
        selected: !dark && s.paper == ReaderPaper.warm,
        onTap: () => onChanged(day(ReaderPaper.warm)),
      ),
      _PaperSwatch(
        label: l.readerNight,
        paper: ShioriReaderPaper.night,
        ink: ShioriPalette.dark.ink,
        selected: dark,
        onTap: () => onChanged(
          s.copyWith(
            themeMode: following && systemDark
                ? ReaderThemeMode.system
                : ReaderThemeMode.dark,
          ),
        ),
      ),
    ];
    final theme = Theme.of(context);
    void follow(bool on) => onChanged(
      s.copyWith(
        themeMode: on
            ? ReaderThemeMode.system
            : dark
            ? ReaderThemeMode.dark
            : ReaderThemeMode.light,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: l.readerColors,
          child: Row(
            children: [
              for (final (index, swatch) in swatches.indexed) ...[
                if (index > 0) const SizedBox(width: ShioriSpace.small),
                Expanded(child: swatch),
              ],
            ],
          ),
        ),
        const SizedBox(height: ShioriSpace.small),
        MergeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => follow(!following),
            child: Padding(
              padding: const EdgeInsets.only(top: ShioriSpace.tight),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.readerFollowSystem,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          l.readerFollowSystemHint,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: ShioriSpace.medium),
                  Switch.adaptive(
                    key: const ValueKey('reader-follow-system'),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    value: following,
                    onChanged: follow,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A miniature page in its own paper and ink.
class _PaperSwatch extends StatelessWidget {
  const _PaperSwatch({
    required this.label,
    required this.paper,
    required this.ink,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Color paper, ink;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(ShioriShape.control);
    final duration = ShioriMotion.of(context, ShioriMotion.feedback);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        decoration: BoxDecoration(color: paper, borderRadius: radius),
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: selected ? scheme.primary : Color.lerp(paper, ink, .16)!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: ink.withValues(alpha: .04),
            highlightColor: ink.withValues(alpha: .08),
            focusColor: ink.withValues(alpha: .08),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ShioriSpace.small,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Aa',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: ink,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: ink.withValues(alpha: .72),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: AnimatedOpacity(
                    duration: duration,
                    opacity: selected ? 1 : 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        size: 12,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Label column plus one full-width control per row.
class _Typography extends StatelessWidget {
  const _Typography({required this.settings, required this.onChanged});
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = settings;

    /// The next value one [delta] away, or null at the range limit.
    VoidCallback? step(
      double value,
      double delta,
      double min,
      double max,
      ReaderSettings Function(double) change,
    ) {
      final next = double.parse(
        (value + delta).clamp(min, max).toStringAsFixed(1),
      );
      return next == value ? null : () => onChanged(change(next));
    }

    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final labels = [
      l.readerFontSize,
      l.readerLineHeight,
      l.readerParagraphSpacing,
      l.readerHorizontalPadding,
      l.readerPageTurn,
    ];
    // One label column sized to the longest label; long translations wrap.
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    var labelWidth = 0.0;
    for (final label in labels) {
      painter
        ..text = TextSpan(text: label, style: labelStyle)
        ..layout();
      if (painter.width > labelWidth) labelWidth = painter.width;
    }
    painter.dispose();
    labelWidth = labelWidth.ceilToDouble().clamp(0.0, 96.0);

    Widget row(String label, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: ShioriSpace.tight),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: labelStyle),
          ),
          const SizedBox(width: ShioriSpace.item),
          Expanded(child: control),
        ],
      ),
    );

    ReaderSettings font(double v) => s.copyWith(fontSize: v);
    ReaderSettings line(double v) => s.copyWith(lineHeight: v);
    ReaderSettings paragraph(double v) => s.copyWith(paragraphSpacing: v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          l.readerFontSize,
          _FontSize(
            label: l.readerFontSize,
            value: s.fontSize,
            onChanged: (v) => onChanged(font(v)),
            onDecrease: step(s.fontSize, -1, 14, 32, font),
            onIncrease: step(s.fontSize, 1, 14, 32, font),
          ),
        ),
        row(
          l.readerLineHeight,
          _Stepper(
            label: l.readerLineHeight,
            value: s.lineHeight.toStringAsFixed(1),
            onDecrease: step(s.lineHeight, -.1, 1.2, 2.4, line),
            onIncrease: step(s.lineHeight, .1, 1.2, 2.4, line),
          ),
        ),
        row(
          l.readerParagraphSpacing,
          _Stepper(
            label: l.readerParagraphSpacing,
            value: s.paragraphSpacing.toStringAsFixed(0),
            onDecrease: step(s.paragraphSpacing, -2, 0, 32, paragraph),
            onIncrease: step(s.paragraphSpacing, 2, 0, 32, paragraph),
          ),
        ),
        row(
          l.readerHorizontalPadding,
          _Segmented<int>(
            selected: readerMarginTier(s.horizontalPadding),
            options: [
              (0, l.readerMarginVeryNarrow),
              (1, l.readerMarginNarrow),
              (2, l.readerMarginMedium),
              (3, l.readerMarginWide),
              (4, l.readerMarginVeryWide),
            ],
            onSelect: (tier) => onChanged(
              s.copyWith(horizontalPadding: readerMarginValues[tier]),
            ),
          ),
        ),
        row(
          l.readerPageTurn,
          _Segmented<PageTurnStyle>(
            selected: s.pageTurn,
            options: [
              for (final style in PageTurnStyle.values)
                (
                  style,
                  switch (style) {
                    PageTurnStyle.curl => l.readerPageTurnCurl,
                    PageTurnStyle.cover => l.readerPageTurnCover,
                    PageTurnStyle.slide => l.readerPageTurnSlide,
                    PageTurnStyle.none => l.readerPageTurnNone,
                  },
                ),
            ],
            onSelect: (style) => onChanged(s.copyWith(pageTurn: style)),
          ),
        ),
      ],
    );
  }
}

/// Shared recessed track behind steppers and segmented controls.
BoxDecoration _track(BuildContext context) => BoxDecoration(
  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .05),
  borderRadius: BorderRadius.circular(ShioriShape.control),
);

const _controlHeight = 40.0;

/// Font size: a slider for large jumps, small and large "A" for single steps.
class _FontSize extends StatelessWidget {
  const _FontSize({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onDecrease,
    required this.onIncrease,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onDecrease, onIncrease;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final glyph = theme.textTheme.labelLarge?.copyWith(height: 1);
    return Row(
      children: [
        _RepeatButton(
          label: l.readerDecrease(label),
          onStep: onDecrease,
          child: Text('A', style: glyph?.copyWith(fontSize: 13)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: scheme.primary,
              inactiveTrackColor: scheme.onSurface.withValues(alpha: .1),
              thumbColor: scheme.primary,
              overlayColor: scheme.primary.withValues(alpha: .12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              tickMarkShape: SliderTickMarkShape.noTickMark,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value.clamp(14, 32),
              min: 14,
              max: 32,
              divisions: 18,
              semanticFormatterCallback: (v) => v.toStringAsFixed(0),
              onChanged: (v) {
                if (v.roundToDouble() != value) onChanged(v.roundToDouble());
              },
            ),
          ),
        ),
        _RepeatButton(
          label: l.readerIncrease(label),
          onStep: onIncrease,
          child: Text('A', style: glyph?.copyWith(fontSize: 19)),
        ),
        SizedBox(
          width: 32,
          child: Text(
            value.toStringAsFixed(0),
            textAlign: TextAlign.end,
            style: theme.textTheme.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });
  final String label, value;
  final VoidCallback? onDecrease, onIncrease;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: _controlHeight),
      decoration: _track(context),
      child: Row(
        children: [
          _RepeatButton(
            label: l.readerDecrease(label),
            onStep: onDecrease,
            child: const Icon(Icons.remove, size: 18),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _RepeatButton(
            label: l.readerIncrease(label),
            onStep: onIncrease,
            child: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Steps once per tap and repeats while held. Labelled through semantics
/// rather than a tooltip, whose own long press would claim the hold.
class _RepeatButton extends StatefulWidget {
  const _RepeatButton({
    required this.label,
    required this.onStep,
    required this.child,
  });
  final String label;
  final VoidCallback? onStep;
  final Widget child;

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _repeat;

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void didUpdateWidget(_RepeatButton old) {
    super.didUpdateWidget(old);
    if (widget.onStep == null) _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onStep != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onStep,
      child: GestureDetector(
        onLongPressStart: enabled
            ? (_) {
                widget.onStep?.call();
                _repeat = Timer.periodic(
                  const Duration(milliseconds: 90),
                  (_) => widget.onStep?.call(),
                );
              }
            : null,
        onLongPressEnd: (_) => _stop(),
        onLongPressCancel: _stop,
        child: IconButton(
          onPressed: widget.onStep,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(_controlHeight),
            fixedSize: const Size.square(_controlHeight),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ShioriShape.control),
            ),
          ),
          icon: widget.child,
        ),
      ),
    );
  }
}

/// Equal-width choices on a recessed track; the chosen one is raised.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selected,
    required this.onSelect,
  });
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = ShioriMotion.of(context, ShioriMotion.feedback);
    const inset = 3.0;
    final raised = theme.brightness == Brightness.dark
        ? Color.lerp(scheme.surface, scheme.onSurface, .14)!
        : scheme.surface;
    final radius = BorderRadius.circular(ShioriShape.control - inset);
    return Container(
      padding: const EdgeInsets.all(inset),
      decoration: _track(context),
      child: Row(
        children: [
          for (final (value, label) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == selected,
                inMutuallyExclusiveGroup: true,
                child: AnimatedContainer(
                  duration: duration,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    color: value == selected
                        ? raised
                        : raised.withValues(alpha: 0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: value == selected ? .08 : 0,
                        ),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    borderRadius: radius,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: value == selected ? null : () => onSelect(value),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: _controlHeight - 2 * inset,
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ShioriSpace.tight,
                              vertical: ShioriSpace.tight,
                            ),
                            child: AnimatedDefaultTextStyle(
                              duration: duration,
                              style: theme.textTheme.bodyMedium!.copyWith(
                                height: 1.3,
                                color: value == selected
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                                fontWeight: value == selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({
    required this.message,
    required this.action,
    required this.onRetry,
  });
  final String message, action;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ShioriSpace.medium,
        ShioriSpace.tight,
        ShioriSpace.tight,
        ShioriSpace.tight,
      ),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(ShioriShape.control),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_problem, size: 18, color: scheme.error),
          const SizedBox(width: ShioriSpace.small),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
          TextButton(onPressed: onRetry, child: Text(action)),
        ],
      ),
    );
  }
}
