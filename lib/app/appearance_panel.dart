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
    // showShioriSheet already applies the safe-area insets.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.appAppearance, style: Theme.of(context).textTheme.titleLarge),
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
                  avatar: Icon(switch (mode) {
                    AppThemeMode.system => Icons.brightness_auto_outlined,
                    AppThemeMode.light => Icons.light_mode_outlined,
                    AppThemeMode.dark => Icons.dark_mode_outlined,
                  }, size: 18),
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
          Text(
            l.appAccentTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
                  avatar: controller.settings.accent == accent
                      ? const Icon(Icons.check, size: 18)
                      : Icon(
                          Icons.circle,
                          size: 16,
                          color: accentFillColor(
                            accent,
                            Theme.of(context).brightness,
                          ),
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
