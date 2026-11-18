import 'package:flutter/material.dart';
import '../shared/widgets/shiori_panel.dart';
import '../domain/models/models.dart';
import '../l10n/generated/app_localizations.dart';
import 'app_controller.dart';
import 'theme/shiori_theme.dart';

class AppAppearanceScope extends InheritedWidget {
  const AppAppearanceScope({
    super.key,
    required this.settings,
    this.onThemeModeChanged,
    required super.child,
  });
  final AppSettings settings;
  final ValueChanged<AppThemeMode>? onThemeModeChanged;
  static AppAppearanceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppAppearanceScope>();

  static String? summaryOf(BuildContext context) {
    final settings = maybeOf(context)?.settings;
    if (settings == null) return null;
    final l = AppLocalizations.of(context);
    return '${_modeLabel(l, settings.themeMode)} · ${_accentLabel(l, settings.accent)}';
  }

  @override
  bool updateShouldNotify(AppAppearanceScope oldWidget) =>
      oldWidget.settings.themeMode != settings.themeMode ||
      oldWidget.settings.accent != settings.accent ||
      oldWidget.onThemeModeChanged != onThemeModeChanged;
}

String _modeLabel(AppLocalizations l, AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => l.readerThemeSystem,
  AppThemeMode.light => l.readerThemeLight,
  AppThemeMode.dark => l.readerThemeDark,
};
String _accentLabel(AppLocalizations l, AppAccent accent) => switch (accent) {
  AppAccent.teal => l.appAccentTeal,
  AppAccent.blueGrey => l.appAccentBlueGrey,
  AppAccent.warmBrown => l.appAccentWarmBrown,
  AppAccent.softPink => l.appAccentSoftPink,
};

/// Live samples of the shelf: system mode pairs the light and dark papers.
class AppThemePreviews extends StatelessWidget {
  const AppThemePreviews({super.key, required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final appearance = AppAppearanceScope.maybeOf(context);
    final select = appearance?.onThemeModeChanged;
    if (appearance == null || select == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, bounds) {
        final stacked =
            bounds.maxWidth < MediaQuery.textScalerOf(context).scale(14) * 17;
        Widget option(AppThemeMode mode) {
          final selected = mode == appearance.settings.themeMode;
          final label = Text(
            _modeLabel(l, mode),
            textAlign: stacked ? TextAlign.start : TextAlign.center,
          );
          final sample = ClipRRect(
            borderRadius: BorderRadius.circular(ShioriShape.cover),
            child: SizedBox(
              height: stacked ? 40 : 58,
              width: stacked ? 64 : double.infinity,
              child: CustomPaint(
                painter: _ShelfSample(mode, appearance.settings.accent),
              ),
            ),
          );
          const check = Icon(Icons.check_rounded, size: 16);
          return Semantics(
            selected: selected,
            child: TextButton(
              onPressed: enabled ? () => select(mode) : null,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.standard,
                padding: const EdgeInsets.all(ShioriSpace.small),
                foregroundColor: theme.colorScheme.onSurface,
                backgroundColor: selected
                    ? summarySurfaceColor(theme.colorScheme)
                    : null,
                side: BorderSide(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ShioriShape.control),
                ),
              ),
              child: stacked
                  ? Row(
                      children: [
                        sample,
                        const SizedBox(width: ShioriSpace.medium),
                        Expanded(child: label),
                        if (selected) check,
                      ],
                    )
                  : Column(
                      children: [
                        sample,
                        const SizedBox(height: ShioriSpace.small),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: ShioriSpace.tight,
                          children: [if (selected) check, label],
                        ),
                      ],
                    ),
            ),
          );
        }

        if (stacked) {
          return Column(
            spacing: ShioriSpace.small,
            children: [for (final mode in AppThemeMode.values) option(mode)],
          );
        }
        return Row(
          spacing: ShioriSpace.small,
          children: [
            for (final mode in AppThemeMode.values)
              Expanded(child: option(mode)),
          ],
        );
      },
    );
  }
}

class _ShelfSample extends CustomPainter {
  const _ShelfSample(this.mode, this.accent);
  final AppThemeMode mode;
  final AppAccent accent;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Use the same shelf proportions in both the thumbnail and large-type row.
    canvas.scale(size.height / 58);
    final width = size.width * 58 / size.height;
    void shelf(Brightness brightness) {
      final palette = brightness == Brightness.light
          ? ShioriPalette.light
          : ShioriPalette.dark;
      final ink = accentColor(accent, brightness);
      final paint = Paint();
      canvas.drawRect(
        Offset.zero & Size(width, 58),
        paint..color = palette.surfaceSubtle,
      );
      void bar(double x, double y, double w, double h, Color color) =>
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, w, h),
              const Radius.circular(2),
            ),
            paint..color = color,
          );
      final gutter = width * .12, gap = width * .055;
      final coverWidth = ((width - gutter * 2 - gap * 2) / 3).clamp(8.0, 20.0);
      bar(gutter, 9, width * .31, 3, palette.secondary);
      for (var i = 0; i < 3; i++) {
        final x = gutter + i * (coverWidth + gap);
        final height = coverWidth * 1.5;
        bar(
          x,
          49 - height,
          coverWidth,
          height,
          Color.lerp(palette.surfaceSubtle, ink, [.88, .38, .62][i])!,
        );
        bar(
          x + coverWidth * .28,
          49 - height * .72,
          coverWidth * .47,
          1.6,
          palette.surface.withValues(alpha: .75),
        );
        bar(
          x + 2,
          49 - height + 3,
          1.2,
          height - 6,
          palette.surface.withValues(alpha: .35),
        );
      }
    }

    shelf(mode == AppThemeMode.dark ? Brightness.dark : Brightness.light);
    if (mode == AppThemeMode.system) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(width / 2, 0, width / 2, 58));
      shelf(Brightness.dark);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShelfSample old) =>
      old.mode != mode || old.accent != accent;
}

/// A dialog in wide windows, a sheet in compact ones. Either way
/// it opens above the current page and leaves it as it was.
Future<void> showAppAppearance(
  BuildContext context,
  AppController controller,
) => showShioriPanel<void>(
  context,
  builder: (context) => Padding(
    padding: EdgeInsets.only(
      top: ShioriPanelScope.isSheet(context) ? 0 : ShioriSpace.page,
    ),
    child: _AppearancePanel(
      controller: controller,
      onClose: ShioriPanelScope.isSheet(context)
          ? null
          : () => Navigator.pop(context),
    ),
  ),
);

class _AppearancePanel extends StatefulWidget {
  const _AppearancePanel({required this.controller, this.onClose});
  final AppController controller;

  /// Set in a dialog, which has no drag handle to close it by.
  final VoidCallback? onClose;
  @override
  State<_AppearancePanel> createState() => _AppearancePanelState();
}

class _AppearancePanelState extends State<_AppearancePanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), controller = widget.controller;
    final theme = Theme.of(context), scheme = theme.colorScheme;
    // The panel host already applies safe-area insets.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.appAppearance, style: theme.textTheme.titleLarge),
          const SizedBox(height: ShioriSpace.medium),
          Text(l.appAppearanceDescription),
          const SizedBox(height: ShioriSpace.item),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in AppThemeMode.values)
                ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(
                    switch (mode) {
                      AppThemeMode.system => Icons.brightness_auto_outlined,
                      AppThemeMode.light => Icons.light_mode_outlined,
                      AppThemeMode.dark => Icons.dark_mode_outlined,
                    },
                    size: 18,
                    // Follow the label in both states; the chip default tints
                    // only unselected icons with the accent.
                    color: controller.settings.themeMode == mode
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                  label: Text(_modeLabel(l, mode)),
                  selected: controller.settings.themeMode == mode,
                  onSelected: (_) => controller.setAppearance(mode),
                ),
            ],
          ),
          const SizedBox(height: ShioriSpace.page),
          Text(l.appAccentTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: ShioriSpace.small),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final accent in AppAccent.values)
                ChoiceChip(
                  // An explicit check avoids RawChip's selection scrim over
                  // the color swatch during avatar/checkmark painting.
                  showCheckmark: false,
                  avatar: _AccentSwatch(
                    color: accentColor(accent, theme.brightness),
                    check: scheme.onPrimary,
                    selected: controller.settings.accent == accent,
                  ),
                  label: Text(_accentLabel(l, accent)),
                  selected: controller.settings.accent == accent,
                  onSelected: (_) => controller.setAccent(accent),
                ),
            ],
          ),
          if (controller.settingsFailure != null)
            TextButton(
              onPressed: controller.retrySettings,
              child: Text(l.retryAction),
            ),
          if (widget.onClose case final close?) ...[
            const SizedBox(height: ShioriSpace.item),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: close,
                child: Text(MaterialLocalizations.of(context).closeButtonLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The accent the choice applies, at a fixed size whether or not selected,
/// with the selection check drawn on it rather than in its place.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.check,
    required this.selected,
  });
  final Color color, check;
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 18,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: selected ? Icon(Icons.check, size: 13, color: check) : null,
    ),
  );
}
