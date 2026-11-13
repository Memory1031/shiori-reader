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
    final app = [
      if (onAppearance case final open?)
        _entry(context, Icons.palette_outlined, strings.appAppearance, open),
      if (onUpdates case final open?)
        _entry(context, Icons.info_outline, strings.updateTitle, open),
    ];
    final storage = [
      if (onLocalBooks case final open?)
        _entry(
          context,
          Icons.folder_outlined,
          strings.localBooksTitle,
          open,
          description: strings.homeSettingsLocalBooksDescription,
        ),
      if (onOfflineContent case final open?)
        _entry(
          context,
          Icons.offline_pin_outlined,
          strings.cacheTitle,
          open,
          description: strings.homeSettingsOfflineDescription,
        ),
    ];
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
            if (app.isNotEmpty) _group(context, strings.homeSettingsApp, app),
            if (app.isNotEmpty && storage.isNotEmpty)
              const SizedBox(height: ShioriSpace.page),
            if (storage.isNotEmpty)
              _group(context, strings.homeSettingsStorage, storage),
          ],
        ),
      ),
    );
  }

  Widget _group(BuildContext context, String title, List<Widget> entries) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: ShioriSpace.item,
            bottom: ShioriSpace.small,
          ),
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
        ),
        Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(ShioriShape.card),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: ListTile.divideTiles(
              color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
              tiles: entries,
            ).toList(),
          ),
        ),
      ],
    );
  }

  Widget _entry(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    String? description,
  }) {
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
      subtitle: description == null ? null : Text(description),
      titleTextStyle: theme.textTheme.bodyLarge,
      subtitleTextStyle: theme.textTheme.bodySmall,
      trailing: Icon(Icons.chevron_right, size: ShioriSpace.page),
    );
  }
}
