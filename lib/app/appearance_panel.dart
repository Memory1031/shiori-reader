import 'package:flutter/material.dart';
import '../domain/models/models.dart';
import '../l10n/generated/app_localizations.dart';
import 'app_controller.dart';

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
