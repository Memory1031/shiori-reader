import 'package:flutter/material.dart';
import '../shared/capabilities.dart';
import '../shared/widgets/shiori_sheet.dart';
import '../domain/models/models.dart';
import '../l10n/generated/app_localizations.dart';
import 'app_controller.dart';
import 'theme/shiori_theme.dart';

/// A dialog on pointer-first platforms, a sheet on touch ones. Either way
/// it opens above the current page and leaves it as it was.
Future<void> showAppAppearance(
  BuildContext context,
  AppController controller,
) => ShioriCapabilities.of(context).pointerFirst
    ? showDialog<void>(
        context: context,
        builder: (dialog) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ShioriLayout.panel),
            child: Padding(
              padding: const EdgeInsets.only(top: ShioriSpace.page),
              child: _AppearancePanel(
                controller: controller,
                onClose: () => Navigator.pop(dialog),
              ),
            ),
          ),
        ),
      )
    : showShioriSheet<void>(
        context,
        builder: (_) => _AppearancePanel(controller: controller),
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
    // showShioriSheet already applies the safe-area insets.
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
                  label: Text(switch (mode) {
                    AppThemeMode.system => l.readerThemeSystem,
                    AppThemeMode.light => l.readerThemeLight,
                    AppThemeMode.dark => l.readerThemeDark,
                  }),
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
                  label: Text(switch (accent) {
                    AppAccent.teal => l.appAccentTeal,
                    AppAccent.blueGrey => l.appAccentBlueGrey,
                    AppAccent.warmBrown => l.appAccentWarmBrown,
                    AppAccent.softPink => l.appAccentSoftPink,
                  }),
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
