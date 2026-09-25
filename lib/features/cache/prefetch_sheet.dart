import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/shiori_sheet.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'cache_screen.dart';

Future<void> showPrefetchSheet(
  BuildContext context, {
  required CacheManagement cache,
  required Catalog? catalog,
  required ChapterKey current,
}) => showShioriSheet<void>(
  context,
  size: ShioriSheetSize.tall,
  builder: (context) =>
      PrefetchPanel(cache: cache, catalog: catalog, current: current),
);

/// Cache management, as opened from prefetch settings.
Route<void> cacheManagementRoute(BuildContext context, CacheManagement cache) =>
    platformPageRoute<void>(
      context,
      settings: const RouteSettings(name: '/cache'),
      builder: (_) => CacheScreen(cache: cache),
    );

/// Prefetch settings and progress for the book being read, following the
/// engine's live state. Placement agnostic: a sheet on phones, a side panel
/// over the reader on desktop. Closing it leaves running downloads alone.
class PrefetchPanel extends StatefulWidget {
  const PrefetchPanel({
    super.key,
    required this.cache,
    required this.catalog,
    required this.current,
    this.onClose,
    this.onManage,
  });
  final CacheManagement cache;
  final Catalog? catalog;
  final ChapterKey current;

  /// Ends the header with a close control, for a side panel without a drag
  /// handle.
  final VoidCallback? onClose;

  /// Opens cache management in the host's stead, e.g. once a panel over the
  /// reader has closed. When null the panel pushes it above itself.
  final VoidCallback? onManage;
  @override
  State<PrefetchPanel> createState() => _PrefetchPanelState();
}

class _PrefetchPanelState extends State<PrefetchPanel> {
  bool _saving = false;
  Future<void> _save(Future<Result<void>> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _saving = false);
    if (result is Failure<void>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).prefetchSaveFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.cache.prefetch!;
    final l = AppLocalizations.of(context);
    return StreamBuilder<PrefetchState>(
      stream: engine.changes,
      initialData: engine.state,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        final status = switch (state.phase) {
          PrefetchPhase.running => l.prefetchRunning,
          PrefetchPhase.paused => l.prefetchPaused,
          PrefetchPhase.budget => l.prefetchBudget,
          PrefetchPhase.partial => l.prefetchPartial,
          PrefetchPhase.complete => l.prefetchComplete,
          PrefetchPhase.idle => l.prefetchIdle,
        };
        final title = Text(
          l.prefetchTitle,
          style: Theme.of(context).textTheme.titleLarge,
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            widget.onClose == null ? 0 : ShioriSpace.small,
            20,
            24,
          ),
          children: [
            if (widget.onClose case final close?)
              Row(
                children: [
                  Expanded(child: title),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              )
            else
              title,
            const SizedBox(height: ShioriSpace.medium),
            Text(status),
            const SizedBox(height: ShioriSpace.small),
            Text(
              l.prefetchExplanation,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.prefetchCurrent),
              value: state.currentEnabled,
              onChanged: _saving
                  ? null
                  : (value) => _save(
                      () => engine.configure(
                        current: value,
                        next: state.nextEnabled,
                      ),
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.prefetchNext),
              value: state.nextEnabled,
              onChanged: _saving
                  ? null
                  : (value) => _save(
                      () => engine.configure(
                        current: state.currentEnabled,
                        next: value,
                      ),
                    ),
            ),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: engine.pause,
                  child: Text(l.prefetchPause),
                ),
                TextButton(
                  onPressed: engine.resume,
                  child: Text(l.prefetchResume),
                ),
                TextButton(
                  onPressed:
                      widget.onManage ??
                      () => Navigator.of(
                        context,
                      ).push(cacheManagementRoute(context, widget.cache)),
                  child: Text(l.cacheTitle),
                ),
              ],
            ),
            const Divider(),
            Text(
              l.prefetchChoose,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.prefetchNoTarget),
              trailing: state.target == null ? const Icon(Icons.check) : null,
              onTap: _saving ? null : () => _save(() => engine.select(null)),
            ),
            for (final volume in widget.catalog?.volumes ?? <Volume>[]) ...[
              if (volume.title != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    volume.title!,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              for (final chapter in volume.chapters)
                if (chapter.key != widget.current)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(chapter.title),
                    trailing: state.target == chapter.key
                        ? const Icon(Icons.check)
                        : null,
                    onTap: _saving
                        ? null
                        : () => _save(() => engine.select(chapter.key)),
                  ),
            ],
          ],
        );
      },
    );
  }
}
