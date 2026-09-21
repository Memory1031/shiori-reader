import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/contracts/app_updates.dart';
import '../../domain/models/release_identity.dart';
import '../../l10n/generated/app_localizations.dart';
import 'update_controller.dart';

class UpdateScreen extends StatelessWidget {
  const UpdateScreen({
    super.key,
    required this.controller,
    required this.openPage,
  });
  final UpdateController controller;
  final Future<bool> Function(Uri) openPage;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final c = controller;
      final target = c.candidate;
      final current = c.installed;
      final date = c.preferences.lastChecked;
      final locale = Localizations.localeOf(context).toLanguageTag();
      return Scaffold(
        appBar: AppBar(title: Text(l.updateTitle)),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Shiori',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.updateInstalled(current.release?.tag ?? current.version),
                  ),
                  const SizedBox(height: 24),
                  if (!c.enabled)
                    Text(switch (current.availability) {
                      UpdateAvailability.development => l.updateDevelopment,
                      UpdateAvailability.unsupported => l.updateUnsupported,
                      _ => l.updateInvalidIdentity,
                    })
                  else ...[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.updateAutomatic),
                      subtitle: Text(l.updateAutomaticHint),
                      value: c.preferences.automatic,
                      onChanged: c.busy || !c.initialized
                          ? null
                          : c.setAutomatic,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<UpdateChannel>(
                      isExpanded: true,
                      key: ValueKey(c.preferences.channel),
                      initialValue: c.preferences.channel,
                      decoration: InputDecoration(labelText: l.updateChannel),
                      items: [
                        DropdownMenuItem(
                          value: UpdateChannel.stable,
                          child: Text(l.updateStable),
                        ),
                        DropdownMenuItem(
                          value: UpdateChannel.beta,
                          child: Text(
                            l.updateBeta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: c.busy || !c.initialized
                          ? null
                          : (value) {
                              if (value != null) c.setChannel(value);
                            },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.updateChannelHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      date == null
                          ? l.updateNeverChecked
                          : l.updateLastChecked(
                              DateFormat.yMd(
                                locale,
                              ).add_Hm().format(date.toLocal()),
                            ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('update-check'),
                          onPressed: c.busy
                              ? null
                              : () =>
                                    c.initialized ? c.check() : c.initialize(),
                          icon: const Icon(Icons.refresh),
                          label: Text(l.updateCheck),
                        ),
                        if (c.busy && !c.installing && !c.preparingInstall)
                          TextButton(
                            onPressed: c.cancel,
                            child: Text(l.updateCancel),
                          ),
                      ],
                    ),
                    if (c.phase == UpdatePhase.checking ||
                        c.phase == UpdatePhase.loading) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(l.updateChecking),
                    ],
                    if (c.issue case final issue?) ...[
                      const SizedBox(height: 20),
                      Text(
                        switch (issue.problem) {
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
                          UpdateProblem.installation => l.updateInstallFailed,
                          UpdateProblem.busy => l.updateInstallBusy,
                        },
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ] else if (target == null && date != null && !c.busy)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(l.updateNoUpdate),
                      ),
                    if (target != null) ...[
                      const SizedBox(height: 28),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                target.release.tag,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l.updateSize(
                                  (target.bytes / 1048576).toStringAsFixed(1),
                                ),
                              ),
                              if (target.notes.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                SelectableText(target.notes),
                              ],
                              const SizedBox(height: 20),
                              if (c.phase == UpdatePhase.downloading) ...[
                                LinearProgressIndicator(
                                  value: (c.received / target.bytes).clamp(
                                    0,
                                    1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l.updateProgress(
                                    (c.received * 100 / target.bytes).floor(),
                                  ),
                                ),
                              ] else if (c.phase == UpdatePhase.downloaded) ...[
                                Text(
                                  c.canInstall
                                      ? l.updateInstallHint
                                      : l.updateDownloaded,
                                ),
                                if (c.canInstall) ...[
                                  const SizedBox(height: 12),
                                  if (c.installState ==
                                      UpdateInstallState
                                          .permissionRequired) ...[
                                    Text(l.updateInstallPermission),
                                    TextButton(
                                      onPressed: c.busy
                                          ? null
                                          : c.openInstallSettings,
                                      child: Text(l.updateInstallSettings),
                                    ),
                                  ] else ...[
                                    if (c.installState ==
                                        UpdateInstallState.cancelled)
                                      Text(l.updateInstallCancelled),
                                    if (c.installState ==
                                        UpdateInstallState.failed)
                                      Text(l.updateInstallFailed),
                                    if (c.installing) Text(l.updateInstalling),
                                    FilledButton.icon(
                                      key: const ValueKey('update-install'),
                                      onPressed: c.busy ? null : c.install,
                                      icon: const Icon(Icons.system_update),
                                      label: Text(l.updateInstall),
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
                              TextButton.icon(
                                onPressed: () async {
                                  if (await openPage(target.page) ||
                                      !context.mounted) {
                                    return;
                                  }
                                  await Clipboard.setData(
                                    ClipboardData(text: target.page.toString()),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(l.updateLinkCopied),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.open_in_new),
                                label: Text(l.updateReleasePage),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
