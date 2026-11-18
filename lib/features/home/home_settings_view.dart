import 'package:flutter/material.dart';

import '../../app/appearance_panel.dart';
import '../../app/theme/shiori_theme.dart';
import '../../l10n/generated/app_localizations.dart';

class HomeSettingsView extends StatelessWidget {
  const HomeSettingsView({
    super.key,
    this.onAppearance,
    this.onLocalBooks,
    this.onOfflineContent,
    this.onUpdates,
    this.availableUpdateTag,
    this.enabled = true,
  });

  final VoidCallback? onAppearance, onLocalBooks, onOfflineContent, onUpdates;
  final bool enabled;
  final String? availableUpdateTag;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), theme = Theme.of(context);
    final storage = [
      if (onLocalBooks case final open?)
        _StorageAction(
          icon: Icons.folder_open_outlined,
          label: l.localBooksTitle,
          detail: l.homeSettingsLocalBooksDescription,
          onTap: enabled ? open : null,
        ),
      if (onOfflineContent case final open?)
        _StorageAction(
          icon: Icons.offline_pin_outlined,
          label: l.cacheTitle,
          detail: l.homeSettingsOfflineDescription,
          onTap: enabled ? open : null,
        ),
    ];
    final summary = AppAppearanceScope.summaryOf(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ShioriLayout.list),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ShioriSpace.page,
            ShioriSpace.medium,
            ShioriSpace.page,
            ShioriSpace.section,
          ),
          children: [
            if (onAppearance case final open?) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: enabled,
                onTap: enabled ? open : null,
                title: Text(
                  l.appAppearance,
                  style: theme.textTheme.titleMedium,
                ),
                subtitle: summary == null
                    ? null
                    : Text(summary, style: theme.textTheme.bodySmall),
                trailing: const Icon(Icons.chevron_right),
              ),
              const SizedBox(height: ShioriSpace.small),
              AppThemePreviews(enabled: enabled),
            ],
            if (storage.isNotEmpty) ...[
              if (onAppearance != null)
                const SizedBox(height: ShioriSpace.section),
              Semantics(
                header: true,
                child: Text(
                  l.homeSettingsStorage,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: ShioriSpace.medium),
              LayoutBuilder(
                builder: (context, bounds) {
                  if (storage.length == 1 ||
                      bounds.maxWidth <
                          MediaQuery.textScalerOf(context).scale(14) * 20) {
                    return Column(
                      spacing: ShioriSpace.small,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: storage,
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: storage.first),
                      const SizedBox(width: ShioriSpace.medium),
                      Expanded(child: storage.last),
                    ],
                  );
                },
              ),
            ],
            if (onUpdates case final open?) ...[
              if (storage.isNotEmpty || onAppearance != null)
                const Divider(height: ShioriSpace.section),
              ListTile(
                enabled: enabled,
                onTap: enabled ? open : null,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: Text(l.updateTitle),
                subtitle: availableUpdateTag == null
                    ? null
                    : Text(l.updateAvailable(availableUpdateTag!)),
                trailing: const Icon(Icons.chevron_right),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StorageAction extends StatelessWidget {
  const _StorageAction({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });
  final IconData icon;
  final String label, detail;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(ShioriShape.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ShioriSpace.item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Icon(
                        icon,
                        color: onTap == null
                            ? theme.disabledColor
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: ShioriSpace.item),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: onTap == null ? theme.disabledColor : null,
                ),
              ),
              const SizedBox(height: ShioriSpace.tight),
              Text(detail, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
