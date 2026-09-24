import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../shared/widgets/shiori_sheet.dart';
import '../../app/theme/shiori_theme.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/contracts/app_updates.dart';
import '../../domain/models/release_identity.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/shiori_logo.dart';
import 'update_controller.dart';
import 'release_notes_preview.dart';

class UpdateScreen extends StatelessWidget {
  const UpdateScreen({
    super.key,
    required this.controller,
    required this.openPage,
  });
  final UpdateController controller;
  final Future<bool> Function(Uri) openPage;

  String get _version {
    final current = controller.installed;
    return current.release?.tag ??
        (current.version == '—' ? '—' : 'v${current.version}');
  }

  Future<void> _openPage(BuildContext context, Uri page) async {
    if (await openPage(page) || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: page.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).updateLinkCopied)),
      );
    }
  }

  Future<void> _chooseChannel(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final value = await showShioriSheet<UpdateChannel>(
      context,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.updateChooseChannel,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final channel in UpdateChannel.values)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          selected: controller.preferences.channel == channel,
                          selectedTileColor: Colors.transparent,
                          leading: Icon(
                            controller.preferences.channel == channel
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          title: Text(
                            channel == UpdateChannel.stable
                                ? l.updateStable
                                : l.updateBeta,
                          ),
                          subtitle: Text(
                            channel == UpdateChannel.stable
                                ? l.updateStableHint
                                : l.updateBetaHint,
                          ),
                          onTap: () => Navigator.pop(context, channel),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        l.updateChannelHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (value != null && context.mounted && !controller.busy) {
      await controller.setChannel(value);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final c = controller;
      final target = c.candidate;
      final theme = Theme.of(context);
      final muted = theme.colorScheme.onSurfaceVariant;
      final date = c.preferences.lastChecked;
      final locale = Localizations.localeOf(context).toLanguageTag();
      return Scaffold(
        appBar: AppBar(title: Text(l.updateTitle)),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(
                      children: [
                        const SizedBox(
                          width: 160,
                          height: 43,
                          child: FittedBox(child: ShioriLogo()),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          l.shelfTagline,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _version,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 32),
                  _SectionTitle(l.updateSection),
                  if (!c.enabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                      child: Text(
                        switch (c.installed.availability) {
                          UpdateAvailability.development => l.updateDevelopment,
                          UpdateAvailability.unsupported => l.updateUnsupported,
                          _ => l.updateInvalidIdentity,
                        },
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                    )
                  else ...[
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      title: Text(l.updateAutomatic),
                      subtitle: Text(l.updateAutomaticHint),
                      value: c.preferences.automatic,
                      onChanged: c.busy || !c.initialized
                          ? null
                          : c.setAutomatic,
                    ),
                    ListTile(
                      key: const ValueKey('update-channel'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      title: Text(l.updateChannel),
                      subtitle: Text(
                        c.preferences.channel == UpdateChannel.stable
                            ? l.updateStableHint
                            : l.updateBetaHint,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.preferences.channel == UpdateChannel.stable
                                ? l.updateStable
                                : l.updateBeta,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: muted,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, size: 18, color: muted),
                        ],
                      ),
                      onTap: c.busy || !c.initialized
                          ? null
                          : () => _chooseChannel(context),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final checked = Text(
                            date == null
                                ? l.updateNeverChecked
                                : l.updateLastChecked(
                                    DateFormat.yMd(
                                      locale,
                                    ).add_Hm().format(date.toLocal()),
                                  ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          );
                          final actions = Wrap(
                            alignment: WrapAlignment.end,
                            children: [
                              TextButton(
                                key: const ValueKey('update-check'),
                                onPressed: c.busy
                                    ? null
                                    : () => c.initialized
                                          ? c.check()
                                          : c.initialize(),
                                child: Text(l.updateCheck),
                              ),
                              if (c.busy &&
                                  !c.installing &&
                                  !c.preparingInstall)
                                TextButton(
                                  onPressed: c.cancel,
                                  child: Text(l.updateCancel),
                                ),
                            ],
                          );
                          if (constraints.maxWidth < 400 &&
                              MediaQuery.textScalerOf(context).scale(14) > 18) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                checked,
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: actions,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: checked),
                              const SizedBox(width: 8),
                              actions,
                            ],
                          );
                        },
                      ),
                    ),
                    if (c.phase == UpdatePhase.checking ||
                        c.phase == UpdatePhase.loading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(l.updateChecking, style: theme.textTheme.bodySmall),
                    ],
                    if (c.issue case final issue?)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                        child: Text(switch (issue.problem) {
                          UpdateProblem.network => l.updateNetworkError,
                          UpdateProblem.rateLimited => l.updateRateLimited(
                            issue.retryAt == null
                                ? '—'
                                : DateFormat.yMd(
                                    locale,
                                  ).add_Hm().format(issue.retryAt!.toLocal()),
                          ),
                          UpdateProblem.incomplete => l.updateIncomplete,
                          UpdateProblem.verification =>
                            l.updateVerificationError,
                          UpdateProblem.storage => l.updateStorageError,
                          UpdateProblem.packageInvalid =>
                            l.updatePackageInvalid,
                          UpdateProblem.cancelled => l.updateCancelled,
                          UpdateProblem.installation =>
                            ShioriCapabilities.of(context).updateRestartsApp
                                ? l.updateInstallFailedWindows
                                : l.updateInstallFailed,
                          UpdateProblem.busy => l.updateInstallBusy,
                          UpdateProblem.instances => l.updateInstallInstances,
                          UpdateProblem.location => l.updateInstallLocation,
                          UpdateProblem.workspaceConflict =>
                            l.updateWorkspaceConflict,
                        }, style: TextStyle(color: theme.colorScheme.error)),
                      )
                    else if (target == null && date != null && !c.busy)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Text(
                          l.updateNoUpdate,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ),
                    if (target != null) ...[
                      const SizedBox(height: 24),
                      _candidate(context, target),
                    ],
                  ],
                  const Divider(height: 40),
                  _SectionTitle(l.updateProject),
                  _ProjectAction(
                    title: 'GitHub',
                    icon: Icons.north_east,
                    onTap: () => _openPage(
                      context,
                      Uri.parse('https://github.com/Memory1031/shiori-reader'),
                    ),
                  ),
                  _ProjectAction(
                    title: l.updateLicenses,
                    icon: Icons.chevron_right,
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Shiori',
                      applicationVersion: _version,
                      applicationIcon: const Padding(
                        padding: EdgeInsets.all(16),
                        child: ShioriLogo(),
                      ),
                    ),
                  ),
                  _ProjectAction(
                    title: l.updateCopyVersion,
                    icon: Icons.copy_outlined,
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: [
                            'Shiori ${c.installed.version}',
                            if (c.installed.release case final release?)
                              'Release: ${release.tag}',
                            'Build: ${c.installed.build}',
                            'Platform: ${defaultTargetPlatform.name}',
                          ].join('\n'),
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.updateVersionCopied)),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _candidate(BuildContext context, UpdateCandidate target) {
    final l = AppLocalizations.of(context);
    final c = controller;
    final theme = Theme.of(context);
    // Windows replaces files after the app exits, then starts it again.
    final windows = ShioriCapabilities.of(context).updateRestartsApp;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ShioriShape.sheet),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.updateNewVersion,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(target.release.tag, style: theme.textTheme.titleLarge),
                  Text(
                    '${(target.bytes / 1048576).toStringAsFixed(1)} MB',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (target.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              ReleaseNotesPreview(
                notes: target.notes,
                key: const ValueKey('update-notes'),
              ),
            ],
            const SizedBox(height: 20),
            if (c.phase == UpdatePhase.downloading) ...[
              LinearProgressIndicator(
                value: (c.received / target.bytes).clamp(0, 1),
              ),
              const SizedBox(height: 8),
              Text(l.updateProgress((c.received * 100 / target.bytes).floor())),
            ] else if (c.installing)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      windows ? l.updateRestarting : l.updateInstalling,
                    ),
                  ),
                ],
              )
            else if (c.phase == UpdatePhase.downloaded) ...[
              Text(
                !c.canInstall
                    ? l.updateDownloaded
                    : windows
                    ? l.updateInstallHintWindows
                    : l.updateInstallHint,
                style: theme.textTheme.bodySmall,
              ),
              if (c.canInstall) ...[
                const SizedBox(height: 12),
                if (c.installState ==
                    UpdateInstallState.permissionRequired) ...[
                  Text(
                    l.updateInstallPermission,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: c.busy ? null : c.openInstallSettings,
                    child: Text(l.updateInstallSettings),
                  ),
                ] else ...[
                  if (c.installState == UpdateInstallState.cancelled) ...[
                    Text(l.updateInstallCancelled),
                    const SizedBox(height: 12),
                  ],
                  if (c.installState == UpdateInstallState.failed) ...[
                    Text(
                      windows
                          ? l.updateInstallFailedWindows
                          : l.updateInstallFailed,
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton.icon(
                    key: const ValueKey('update-install'),
                    onPressed: c.busy ? null : c.install,
                    icon: Icon(
                      windows ? Icons.restart_alt : Icons.system_update,
                    ),
                    label: Text(
                      windows ? l.updateRestartInstall : l.updateInstall,
                    ),
                  ),
                ],
              ],
            ] else
              FilledButton.icon(
                key: const ValueKey('update-download'),
                onPressed: c.busy ? null : c.download,
                icon: const Icon(Icons.download_outlined),
                label: Text(l.updateDownload),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _openPage(context, target.page),
              child: Text(l.updateReleasePage),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectAction extends StatelessWidget {
  const _ProjectAction({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(ShioriShape.control)),
    );
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            highlightColor: colors.onSurface.withValues(alpha: .06),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: shape,
            hoverColor: colors.onSurface.withValues(alpha: .04),
            focusColor: colors.onSurface.withValues(alpha: .08),
            title: Text(title),
            trailing: Icon(icon, size: 18, color: colors.onSurfaceVariant),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
