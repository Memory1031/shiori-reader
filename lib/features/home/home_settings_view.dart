import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Mobile settings entries reuse the existing management pages and callbacks.
class HomeSettingsView extends StatelessWidget {
  const HomeSettingsView({
    super.key,
    this.onAppearance,
    this.onLocalBooks,
    this.onOfflineContent,
    this.onUpdates,
    this.enabled = true,
  });

  final VoidCallback? onAppearance, onLocalBooks, onOfflineContent, onUpdates;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ShioriLayout.list),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ShioriSpace.page,
            ShioriSpace.medium,
            ShioriSpace.page,
            ShioriSpace.page,
          ),
          children: [
            if (onAppearance != null)
              _group(context, strings.homeSettingsAppearance, [
                _entry(
                  context,
                  Icons.palette_outlined,
                  strings.appAppearance,
                  strings.homeSettingsAppearanceDescription,
                  onAppearance!,
                ),
              ]),
            if (onLocalBooks != null || onOfflineContent != null)
              _group(context, strings.homeSettingsStorage, [
                if (onLocalBooks != null)
                  _entry(
                    context,
                    Icons.folder_outlined,
                    strings.localBooksTitle,
                    strings.homeSettingsLocalBooksDescription,
                    onLocalBooks!,
                  ),
                if (onOfflineContent != null)
                  _entry(
                    context,
                    Icons.offline_pin_outlined,
                    strings.cacheTitle,
                    strings.homeSettingsOfflineDescription,
                    onOfflineContent!,
                  ),
              ]),
            if (onUpdates != null)
              _group(context, strings.homeSettingsAbout, [
                _entry(
                  context,
                  Icons.info_outline,
                  strings.updateTitle,
                  strings.homeSettingsAboutDescription,
                  onUpdates!,
                ),
              ]),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ShioriSpace.item),
              child: Text(
                strings.appTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(BuildContext context, String title, List<Widget> entries) =>
      Padding(
        padding: const EdgeInsets.only(bottom: ShioriSpace.item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: ShioriSpace.item,
                bottom: ShioriSpace.small,
              ),
              child: Text(title, style: Theme.of(context).textTheme.bodySmall),
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(ShioriShape.card),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: .5,
                        indent: ShioriSpace.item * 3 + ShioriSpace.small,
                        endIndent: ShioriSpace.item,
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: .45),
                      ),
                    entries[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _entry(
    BuildContext context,
    IconData icon,
    String label,
    String description,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: ShioriSpace.item,
        vertical: ShioriSpace.tight,
      ),
      minLeadingWidth: ShioriSpace.item + ShioriSpace.small,
      horizontalTitleGap: ShioriSpace.item,
      leading: Icon(
        icon,
        color: enabled ? theme.colorScheme.primary : theme.disabledColor,
        size: ShioriSpace.item + ShioriSpace.small,
      ),
      title: Text(label),
      subtitle: Text(description),
      titleTextStyle: theme.textTheme.bodyMedium,
      subtitleTextStyle: theme.textTheme.bodySmall,
      trailing: Icon(Icons.chevron_right, size: ShioriSpace.page),
    );
  }
}
