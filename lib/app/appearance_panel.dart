import 'package:flutter/material.dart';
import '../domain/models/models.dart';
import '../l10n/generated/app_localizations.dart';
import 'app_controller.dart';
import 'theme/shiori_theme.dart';

Future<void> showAppAppearance(
  BuildContext context,
  AppController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (_) => _AppearancePanel(controller: controller),
);

class _AppearancePanel extends StatefulWidget {
  const _AppearancePanel({required this.controller});
  final AppController controller;
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.appAppearance,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(l.appAppearanceDescription),
            const SizedBox(height: 16),
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
            const SizedBox(height: 20),
            Text(
              l.appAccentTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final accent in AppAccent.values)
                  ChoiceChip(
                    avatar: Icon(
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
          ],
        ),
      ),
    );
  }
}
