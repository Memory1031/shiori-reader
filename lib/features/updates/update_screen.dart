import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../shared/widgets/shiori_panel.dart';
import '../../app/theme/shiori_theme.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/contracts/app_updates.dart';
import '../../domain/models/release_identity.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/shiori_logo.dart';
import '../../shared/widgets/desktop_content_frame.dart';
import '../../shared/widgets/shiori_feedback.dart';
import 'update_controller.dart';
import 'release_notes_preview.dart';

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({
    super.key,
    required this.controller,
    required this.openPage,
  });
  final UpdateController controller;
  final Future<bool> Function(Uri) openPage;

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  // The page owns only pointer scrolling; the injected update owner survives it.
  final _scroll = ScrollController();
  UpdateController get controller => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String get _version {
    final current = controller.installed;
    return current.release?.tag ??
        (current.version == '—' ? '—' : 'v${current.version}');
  }

  Future<void> _openPage(BuildContext context, Uri page) async {
    if (await widget.openPage(page) || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: page.toString()));
    if (context.mounted) {
      ShioriFeedback.show(
        context,
        message: AppLocalizations.of(context).updateLinkCopied,
        kind: ShioriFeedbackKind.success,
      );
    }
  }

  Future<void> _copyVersion(BuildContext context) async {
    final c = controller, l = AppLocalizations.of(context);
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
      ShioriFeedback.show(
        context,
        message: l.updateVersionCopied,
        kind: ShioriFeedbackKind.success,
      );
    }
  }

  Future<void> _chooseChannel(BuildContext context) async {
    final l = AppLocalizations.of(context);
    Widget options(BuildContext context) => Column(
      mainAxisSize: MainAxisSize.min,
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
              channel == UpdateChannel.stable ? l.updateStable : l.updateBeta,
            ),
            subtitle: Text(
              channel == UpdateChannel.stable
                  ? l.updateStableHint
                  : l.updateBetaHint,
            ),
            onTap: () => Navigator.pop(context, channel),
          ),
        const SizedBox(height: ShioriSpace.medium),
        Text(l.updateChannelHint, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    final value = await showShioriPanel<UpdateChannel>(
      context,
      dialogBuilder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: ShioriLayout.panel),
        scrollable: true,
        title: Text(l.updateChooseChannel),
        content: SizedBox(width: ShioriLayout.panel, child: options(context)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          ShioriSpace.page,
          0,
          ShioriSpace.page,
          ShioriSpace.page,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.updateChooseChannel,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: ShioriSpace.item),
            Flexible(child: SingleChildScrollView(child: options(context))),
          ],
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
      final desktop = DesktopLayoutScope.useDesktopPage(context);
      final pointerFirst = ShioriCapabilities.of(context).pointerFirst;
      final content = LayoutBuilder(
        builder: (context, constraints) {
          final inset = desktop
              ? desktopContentGeometry(
                  availableWidth: constraints.maxWidth,
                  gutter: ShioriLayout.gutter(
                    DesktopLayoutScope.widthOf(context),
                  ),
                  maxWidth: 640,
                ).inset
              : 24.0;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: desktop ? double.infinity : 640,
              ),
              child: ListView(
                // Touch keeps the route primary, including iOS scroll-to-top.
                // Pointer ownership must not switch at the desktop breakpoint.
                controller: pointerFirst ? _scroll : null,
                padding: EdgeInsets.fromLTRB(inset, 8, inset, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: ShioriSpace.item,
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(ShioriShape.card),
                          child: Image.asset(
                            'assets/branding/shiori-chibi-logo-v1.png',
                            width: 72,
                            height: 72,
                            cacheWidth:
                                (72 * MediaQuery.devicePixelRatioOf(context))
                                    .ceil(),
                            excludeFromSemantics: true,
                          ),
                        ),
                        const SizedBox(width: ShioriSpace.item),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const ShioriLogo(),
                              const SizedBox(height: ShioriSpace.tight),
                              Text(
                                l.updateAboutDescription,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: ShioriSpace.section),
                  _SectionTitle(l.updateInstalledVersion),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: ShioriSpace.small,
                    children: [
                      Wrap(
                        spacing: ShioriSpace.small,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(_version, style: theme.textTheme.titleLarge),
                          IconButton(
                            tooltip: l.updateCopyVersion,
                            onPressed: () => _copyVersion(context),
                            icon: Icon(
                              Icons.copy_outlined,
                              size: 16,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                      if (c.enabled)
                        Wrap(
                          children: [
                            TextButton(
                              key: const ValueKey('update-check'),
                              style: TextButton.styleFrom(
                                backgroundColor: summarySurfaceColor(
                                  theme.colorScheme,
                                ),
                              ),
                              onPressed: c.busy
                                  ? null
                                  : () => c.initialized
                                        ? c.check()
                                        : c.initialize(),
                              child: Text(l.updateCheck),
                            ),
                            if (c.busy && !c.installing && !c.preparingInstall)
                              TextButton(
                                onPressed: c.cancel,
                                child: Text(l.updateCancel),
                              ),
                          ],
                        ),
                    ],
                  ),
                  if (c.enabled) ...[
                    Text(
                      date == null
                          ? l.updateNeverChecked
                          : l.updateLastChecked(
                              DateFormat.yMd(
                                locale,
                              ).add_Hm().format(date.toLocal()),
                            ),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (c.phase == UpdatePhase.checking ||
                        c.phase == UpdatePhase.loading) ...[
                      const SizedBox(height: ShioriSpace.medium),
                      const LinearProgressIndicator(),
                      const SizedBox(height: ShioriSpace.small),
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
                                ? Theme.of(context).platform ==
                                          TargetPlatform.macOS
                                      ? l.updateInstallFailedMacOS
                                      : l.updateInstallFailedWindows
                                : l.updateInstallFailed,
                          UpdateProblem.busy => l.updateInstallBusy,
                          UpdateProblem.instances => l.updateInstallInstances,
                          UpdateProblem.location =>
                            Theme.of(context).platform == TargetPlatform.macOS
                                ? l.updateInstallLocationMacOS
                                : l.updateInstallLocation,
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
                  if (!c.enabled)
                    Text(
                      switch (c.installed.availability) {
                        UpdateAvailability.development => l.updateDevelopment,
                        UpdateAvailability.unsupported =>
                          c.installed.installation.distribution ==
                                  DistributionChannel.testFlight
                              ? l.updateTestFlightHint
                              : l.updateUnsupported,
                        _ => l.updateInvalidIdentity,
                      },
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  if (c.enabled) ...[
                    const SizedBox(height: ShioriSpace.section),
                    _SectionTitle(l.updatePreferencesTitle),
                    Material(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(ShioriShape.card),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            activeTrackColor: theme.colorScheme.primary,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            title: Text(l.updateAutomatic),
                            subtitle: Text(
                              c.capabilities.canDownload
                                  ? l.updateAutomaticHint
                                  : l.updateCheckOnlyAutomaticHint,
                            ),
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
                                const SizedBox(width: ShioriSpace.tight),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: muted,
                                ),
                              ],
                            ),
                            onTap: c.busy || !c.initialized
                                ? null
                                : () => _chooseChannel(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: ShioriSpace.section),
                  _SectionTitle(l.updateProject),
                  _ProjectAction(
                    title: 'GitHub',
                    leadingIcon: Icons.star_outline_rounded,
                    subtitle: l.updateStarHint,
                    icon: Icons.north_east,
                    onTap: () => _openPage(
                      context,
                      Uri.parse('https://github.com/Memory1031/shiori-reader'),
                    ),
                  ),
                  _ProjectAction(
                    title: l.updateLicenses,
                    leadingIcon: Icons.description_outlined,
                    icon: Icons.chevron_right,
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Shiori',
                      applicationVersion: _version,
                      applicationIcon: const Padding(
                        padding: EdgeInsets.all(ShioriSpace.item),
                        child: ShioriLogo(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return Scaffold(
        appBar: desktop ? null : AppBar(title: Text(l.updateTitle)),
        body: SafeArea(
          child: Column(
            children: [
              if (desktop)
                DesktopPageChrome(
                  child: DesktopPageToolbar(
                    title: l.updateTitle,
                    leading:
                        ModalRoute.of(context)?.impliesAppBarDismissal == true
                        ? const BackButton()
                        : null,
                  ),
                )
              else
                const SizedBox.shrink(),
              Expanded(child: content),
            ],
          ),
        ),
      );
    },
  );

  Widget _candidate(BuildContext context, UpdateCandidate target) {
    final l = AppLocalizations.of(context);
    final c = controller;
    final theme = Theme.of(context);
    // Desktop updates replace the app after exit, then start it again.
    final windows = ShioriCapabilities.of(context).updateRestartsApp;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ShioriShape.sheet),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ShioriSpace.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.updateNewVersion,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: ShioriSpace.small),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(target.release.tag, style: theme.textTheme.titleLarge),
                  if (c.capabilities.canDownload)
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
              const SizedBox(height: ShioriSpace.item),
              ReleaseNotesPreview(
                notes: target.notes,
                key: ValueKey(target.release),
              ),
            ],
            const SizedBox(height: ShioriSpace.page),
            if (!c.capabilities.canDownload) ...[
              Text(l.updateManualInstallHint, style: theme.textTheme.bodySmall),
              const SizedBox(height: ShioriSpace.medium),
              FilledButton.icon(
                key: const ValueKey('update-release-page'),
                onPressed: () => _openPage(context, target.page),
                icon: const Icon(Icons.open_in_new),
                label: Text(l.updateOpenReleasePage),
              ),
            ] else ...[
              if (c.phase == UpdatePhase.downloading ||
                  c.phase == UpdatePhase.verifying) ...[
                LinearProgressIndicator(
                  value: c.phase == UpdatePhase.verifying
                      ? null
                      : (c.received / target.bytes).clamp(0, 1),
                  semanticsLabel: c.phase == UpdatePhase.verifying
                      ? l.updateVerifying
                      : null,
                ),
                const SizedBox(height: ShioriSpace.small),
                Stack(
                  children: [
                    Visibility(
                      visible: c.phase == UpdatePhase.downloading,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Text(
                        l.updateProgress(
                          (c.received * 100 / target.bytes).floor(),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: c.phase == UpdatePhase.verifying,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Text(l.updateVerifying),
                    ),
                  ],
                ),
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
                    const SizedBox(width: ShioriSpace.medium),
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
                  const SizedBox(height: ShioriSpace.medium),
                  if (c.installState ==
                      UpdateInstallState.permissionRequired) ...[
                    Text(
                      l.updateInstallPermission,
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else ...[
                    if (c.installState == UpdateInstallState.cancelled) ...[
                      Text(l.updateInstallCancelled),
                      const SizedBox(height: ShioriSpace.medium),
                    ],
                    if (c.installState == UpdateInstallState.failed) ...[
                      Text(
                        windows
                            ? Theme.of(context).platform == TargetPlatform.macOS
                                  ? l.updateInstallFailedMacOS
                                  : l.updateInstallFailedWindows
                            : l.updateInstallFailed,
                      ),
                      const SizedBox(height: ShioriSpace.medium),
                    ],
                  ],
                ],
              ],
              if (c.phase == UpdatePhase.downloading ||
                  c.phase == UpdatePhase.verifying ||
                  c.installing ||
                  c.phase == UpdatePhase.downloaded)
                const SizedBox(height: ShioriSpace.small),
              Wrap(
                spacing: ShioriSpace.small,
                runSpacing: ShioriSpace.small,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (c.phase != UpdatePhase.downloading &&
                      c.phase != UpdatePhase.verifying &&
                      !c.installing)
                    if (c.phase == UpdatePhase.downloaded) ...[
                      if (c.canInstall)
                        if (c.installState ==
                            UpdateInstallState.permissionRequired)
                          FilledButton(
                            onPressed: c.busy ? null : c.openInstallSettings,
                            child: Text(l.updateInstallSettings),
                          )
                        else
                          FilledButton.icon(
                            key: const ValueKey('update-install'),
                            onPressed: c.busy ? null : c.install,
                            icon: Icon(
                              windows ? Icons.restart_alt : Icons.system_update,
                            ),
                            label: Text(
                              windows
                                  ? l.updateRestartInstall
                                  : l.updateInstall,
                            ),
                          ),
                    ] else
                      FilledButton.icon(
                        key: const ValueKey('update-download'),
                        onPressed: c.busy ? null : c.download,
                        icon: const Icon(Icons.download_outlined),
                        label: Text(l.updateDownload),
                      ),
                  TextButton(
                    onPressed: () => _openPage(context, target.page),
                    child: Text(l.updateOpenReleasePage),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProjectAction extends StatelessWidget {
  const _ProjectAction({
    required this.title,
    required this.leadingIcon,
    this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData leadingIcon, icon;
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
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: ShioriSpace.medium,
          ),
          shape: shape,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: summarySurfaceColor(colors),
            foregroundColor: colors.primary,
            child: Icon(leadingIcon, size: 20),
          ),
          title: Text(title),
          subtitle: subtitle == null
              ? null
              : Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          trailing: Icon(icon, size: 18, color: colors.onSurfaceVariant),
          onTap: onTap,
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
