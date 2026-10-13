import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import 'package:flutter/services.dart';
import '../../domain/contracts/import_source.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'import_controller.dart';
import '../../shared/widgets/shiori_task_progress_bar.dart';

String _problemText(AppLocalizations l, ImportProblem p) => switch (p) {
  ImportProblem.encoding => l.importEncodingInvalid,
  ImportProblem.drm => l.importDrm,
  ImportProblem.fixedLayout => l.importFixedLayout,
  ImportProblem.parseLimit => l.importParseLimit,
  ImportProblem.parseStructureLimit => l.importParseStructureLimit,
  ImportProblem.parseTimeout => l.importParseTimeout,
  ImportProblem.tooLarge => l.importTooLarge,
  ImportProblem.batchLimit => l.importBatchLimit,
  ImportProblem.inboxFull => l.importInboxFull,
  ImportProblem.publicationUncertain => l.importPublicationUncertain,
  ImportProblem.multiple => l.importMultiple,
  ImportProblem.busy => l.importBusy,
  ImportProblem.unsupported => l.importUnsupported,
  ImportProblem.invalidContent => l.importInvalid,
  ImportProblem.parserUnavailable => l.importParserUnavailable,
  ImportProblem.storage => l.importStorage,
  ImportProblem.cancelled => l.importCancelled,
  ImportProblem.unreadable => l.importUnreadable,
};

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

/// Root overlay preserves the Navigator and the currently open reading route.
class ImportOverlay extends StatefulWidget {
  const ImportOverlay({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.child,
    this.onRead,
  });
  final ImportController controller;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final ValueChanged<NovelKey>? onRead;
  @override
  State<ImportOverlay> createState() => _ImportOverlayState();
}

class _ImportOverlayState extends State<ImportOverlay>
    with WidgetsBindingObserver {
  _ImportRoute? _route;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(ImportOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final navigator = widget.navigatorKey.currentState;
      final c = widget.controller;
      if (_route != null &&
          (!c.interactionOpen ||
              c.maintenanceBlocked ||
              _route!.imports != c ||
              _route!.navigator != navigator)) {
        final old = _route!;
        _route = null;
        if (old.isActive && old.navigator?.mounted == true) {
          old.navigator!.removeRoute(old);
        }
      }
      if (c.interactionOpen && !c.maintenanceBlocked && navigator != null) {
        if (_route == null) {
          final route = _route = _ImportRoute(
            imports: c,
            onRead: widget.onRead,
            barrierLabel: MaterialLocalizations.of(
              context,
            ).modalBarrierDismissLabel,
          );
          unawaited(
            navigator.push(route).whenComplete(() {
              if (mounted && identical(_route, route)) {
                _route = null;
                c.dismiss();
              }
            }),
          );
        } else {
          _route!.changedInternalState();
        }
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    final route = _route;
    _route = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route?.navigator?.mounted == true && route!.isActive) {
        route.navigator!.removeRoute(route);
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _changed();
    return widget.child;
  }
}

class _ImportRoute extends PopupRoute<void> {
  _ImportRoute({required this.imports, required this.barrierLabel, this.onRead})
    : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);
  final ImportController imports;
  final ValueChanged<NovelKey>? onRead;
  final panelKey = GlobalKey<_ImportPanelState>();
  @override
  final String barrierLabel;
  @override
  bool get barrierDismissible => !imports.busy;
  @override
  Color get barrierColor => Colors.black26;
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  RoutePopDisposition get popDisposition =>
      imports.busy || panelKey.currentState?._discardIds != null
      ? RoutePopDisposition.doNotPop
      : super.popDisposition;
  @override
  Widget buildModalBarrier() => ModalBarrier(
    key: const ValueKey('import-dismiss-barrier'),
    color: barrierColor,
    dismissible: barrierDismissible,
    onDismiss: () => panelKey.currentState?._dismiss(),
    semanticsLabel: barrierLabel,
  );
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _ImportPanel(key: panelKey, controller: imports, onRead: onRead);
}

class _ImportPanel extends StatefulWidget {
  const _ImportPanel({super.key, required this.controller, this.onRead});
  final ImportController controller;
  final ValueChanged<NovelKey>? onRead;
  @override
  State<_ImportPanel> createState() => _ImportPanelState();
}

class _ImportPanelState extends State<_ImportPanel> {
  Set<String>? _discardIds;
  bool _discardRemaining = false, _stopping = false;
  final _discardFocus = FocusNode();

  void _keepFiles() {
    setState(() => _discardIds = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _discardFocus.context != null &&
          _discardFocus.canRequestFocus) {
        _discardFocus.requestFocus();
      }
    });
  }

  void _dismiss() {
    if (_discardIds != null) {
      _keepFiles();
    } else {
      widget.controller.dismiss();
    }
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    try {
      await widget.controller.cancel();
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  Widget _stopButton(ImportController c, AppLocalizations l) => TextButton(
    onPressed: _stopping ? null : _stop,
    child: Text(
      c.phase == ImportPhase.receiving ? l.importStopReceiving : l.importStop,
    ),
  );

  Widget _discardButton(ImportController c, AppLocalizations l) {
    final remaining =
        c.items.length > 1 &&
        c.items.any((item) => item.phase != ImportItemPhase.ready);
    return TextButton(
      focusNode: _discardFocus,
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
      onPressed: () => setState(() {
        _discardIds = c.items.map((item) => item.candidate.id).toSet();
        _discardRemaining = remaining;
      }),
      child: Text(remaining ? l.importDiscardRemaining : l.importDiscardFiles),
    );
  }

  Widget _discardConfirmation(ImportController c, AppLocalizations l) {
    final title = _discardRemaining
        ? l.importDiscardRemainingTitle
        : l.importDiscardTitle;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: title,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: ShioriSpace.medium),
            Text(l.importDiscardMessage),
            const SizedBox(height: ShioriSpace.item),
            Wrap(
              spacing: ShioriSpace.medium,
              runSpacing: ShioriSpace.small,
              children: [
                TextButton(
                  autofocus: true,
                  onPressed: _keepFiles,
                  child: Text(l.importKeepFiles),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  onPressed: c.busy || _stopping
                      ? null
                      : () {
                          final ids = _discardIds!;
                          setState(() => _discardIds = null);
                          unawaited(c.discard(receiptIds: ids));
                        },
                  child: Text(l.importDiscardFiles),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _discardFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final l = AppLocalizations.of(context);
      return PopScope<void>(
        canPop: !c.busy && _discardIds == null,
        onPopInvokedWithResult: (_, _) => _dismiss(),
        child: FocusScope(
          key: ValueKey(_discardIds != null),
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event.logicalKey != LogicalKeyboardKey.escape) {
              return KeyEventResult.ignored;
            }
            if (event is KeyDownEvent) _dismiss();
            return KeyEventResult.handled;
          },
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(ShioriSpace.medium),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: ShioriLayout.panel,
                    maxHeight: MediaQuery.sizeOf(context).height * .7,
                  ),
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(ShioriShape.sheet),
                    color: Theme.of(context).colorScheme.surface,
                    surfaceTintColor: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.all(ShioriSpace.page),
                      child: c.discarding
                          ? ShioriTaskProgressBar(semanticsLabel: l.loading)
                          : _discardIds != null
                          ? _discardConfirmation(c, l)
                          : c.panelOpen
                          ? _panel(context, c, l)
                          : _banner(context, c, l),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _banner(
    BuildContext context,
    ImportController c,
    AppLocalizations l,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        c.items.isEmpty
            ? l.importIncoming
            : l.importPendingCount(
                c.items
                    .where((item) => item.phase != ImportItemPhase.succeeded)
                    .length,
              ),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (c.batchProblem case final problem?) ...[
        const SizedBox(height: ShioriSpace.small),
        Text(_problemText(l, problem), key: const ValueKey('import-error')),
      ],
      const SizedBox(height: ShioriSpace.medium),
      Wrap(
        spacing: 12,
        children: [
          FilledButton(onPressed: c.open, child: Text(l.importReview)),
          if (!c.busy)
            TextButton(onPressed: c.dismiss, child: Text(l.importLater)),
          if (c.busy)
            _stopButton(c, l)
          else if (c.items.isNotEmpty)
            _discardButton(c, l),
        ],
      ),
    ],
  );

  Widget _panel(BuildContext context, ImportController c, AppLocalizations l) {
    if (c.choosingEncoding) return _encodingPanel(context, c, l);
    if (c.phase == ImportPhase.receiving) return _receivingPanel(c, l);
    if (c.items.isEmpty) return _emptyPanel(context, c, l);
    if (c.items.length == 1) return _singlePanel(context, c, l);
    return _batchPanel(context, c, l);
  }

  Widget _receivingPanel(ImportController c, AppLocalizations l) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(l.importReceiving),
      const SizedBox(height: ShioriSpace.small),
      ShioriTaskProgressBar(semanticsLabel: l.importReceiving),
      const SizedBox(height: ShioriSpace.item),
      Align(alignment: Alignment.centerLeft, child: _stopButton(c, l)),
    ],
  );

  Widget _emptyPanel(
    BuildContext context,
    ImportController c,
    AppLocalizations l,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(l.importTitle, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: ShioriSpace.medium),
      if (c.problem case final problem?)
        Text(_problemText(l, problem), key: const ValueKey('import-error'))
      else if (!c.busy)
        Text(l.importHint),
      if (!c.busy) const SizedBox(height: ShioriSpace.item),
      if (!c.busy)
        Wrap(
          spacing: ShioriSpace.medium,
          runSpacing: ShioriSpace.small,
          children: [
            FilledButton(onPressed: c.pick, child: Text(l.importChoose)),
            TextButton(onPressed: c.dismiss, child: Text(l.importLater)),
          ],
        ),
    ],
  );

  /// Single staged file keeps the original compact flow: name, format notes,
  /// manual encoding override, retry and read-now.
  Widget _singlePanel(
    BuildContext context,
    ImportController c,
    AppLocalizations l,
  ) {
    final item = c.items.single;
    final done = item.phase == ImportItemPhase.succeeded;
    final name = item.candidate.name;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.importTitle, style: Theme.of(context).textTheme.titleLarge),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ShioriSpace.medium),
            child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: ShioriSpace.medium),
          if (c.phase == ImportPhase.importing) ...[
            Text(_workLabel(c, l)),
            const SizedBox(height: ShioriSpace.small),
            ShioriTaskProgressBar(
              value: _progressValue(c, item),
              semanticsLabel: _workLabel(c, l),
            ),
          ] else if (done)
            Text(l.importSuccess)
          else if (c.problem case final problem?)
            Text(_problemText(l, problem), key: const ValueKey('import-error'))
          else
            Text(l.importHint),
          if (!c.busy && !done && name.toLowerCase().endsWith('.txt'))
            DropdownButton<TxtEncoding?>(
              isExpanded: true,
              value: c.encoding,
              hint: Text(l.importEncodingAuto),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(l.importEncodingAuto),
                ),
                for (final e in TxtEncoding.values)
                  DropdownMenuItem(value: e, child: Text(_encodingName(e))),
              ],
              onChanged: c.setEncoding,
            ),
          if (!c.busy && !done && name.toLowerCase().endsWith('.epub'))
            Text(l.importEpubSupport),
          const SizedBox(height: ShioriSpace.item),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (!c.busy && !done)
                FilledButton(
                  onPressed: c.submit,
                  child: Text(
                    item.phase == ImportItemPhase.failed
                        ? l.importRetry
                        : l.importStart,
                  ),
                ),
              if (done && !c.busy && widget.onRead != null)
                FilledButton(
                  onPressed: () =>
                      widget.onRead!(item.result!.content.detail.summary.key),
                  child: Text(l.localReadNow),
                ),
              if (done && !c.busy)
                FilledButton(onPressed: c.finish, child: Text(l.importDone))
              else if (c.busy)
                _stopButton(c, l)
              else ...[
                TextButton(onPressed: c.dismiss, child: Text(l.importLater)),
                _discardButton(c, l),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Whole-batch panel: fixed header and actions, independently scrolling
  /// per-file list. Never depends on the single-file focus view.
  Widget _batchPanel(
    BuildContext context,
    ImportController c,
    AppLocalizations l,
  ) {
    final succeeded = c.succeededCount;
    final failed = c.failedCount;
    final total = c.items.length;
    final pending = total - succeeded - failed;
    final importing = c.phase == ImportPhase.importing;
    final current = c.importingItem;
    final allDone = succeeded == total;
    final fatalReason =
        c.batchProblem == ImportProblem.storage ||
            c.batchProblem == ImportProblem.parserUnavailable
        ? c.batchProblem
        : null;
    final ran = succeeded > 0 || failed > 0;

    final String title;
    final String? counts;
    if (importing) {
      // A committed item has no active parser while its receipt is being
      // acknowledged. Keep the panel busy until that asynchronous work ends.
      title = current == null
          ? l.importBookProcessing
          : l.importBatchProgress(c.items.indexOf(current) + 1, total);
      counts = null;
    } else if (allDone) {
      title = l.importBatchDone(total);
      counts = null;
    } else if (c.phase == ImportPhase.failed && ran) {
      title = fatalReason != null
          ? l.importBatchStopped
          : l.importBatchFinished;
      counts = pending > 0
          ? '${l.importBatchSummary(succeeded, failed)} · ${l.importBatchRemaining(pending)}'
          : l.importBatchSummary(succeeded, failed);
    } else if (ran) {
      // Stopped earlier by the user; the run resumes with the same receipts.
      title = l.importBatchDone(succeeded);
      counts = pending > 0 ? l.importBatchRemaining(pending) : null;
    } else {
      title = l.importBatchReady(total);
      counts = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (current != null) ...[
          const SizedBox(height: ShioriSpace.tight),
          Text(
            current.candidate.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (counts != null) ...[
          const SizedBox(height: ShioriSpace.tight),
          Text(
            counts,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (c.batchProblem case final problem?) ...[
          const SizedBox(height: ShioriSpace.tight),
          Text(
            _problemText(l, problem),
            key: const ValueKey('import-error'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: ShioriSpace.small),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: total,
            itemBuilder: (context, index) =>
                _ImportItemTile(item: c.items[index], l: l),
          ),
        ),
        if (importing) ...[
          const SizedBox(height: ShioriSpace.small),
          if (current != null) ...[
            Text(_workLabel(c, l)),
            const SizedBox(height: ShioriSpace.small),
          ],
          ShioriTaskProgressBar(
            value: current == null ? null : _progressValue(c, current),
            semanticsLabel: _workLabel(c, l),
          ),
        ],
        const SizedBox(height: ShioriSpace.item),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (importing)
              _stopButton(c, l)
            else if (allDone)
              FilledButton(onPressed: c.finish, child: Text(l.importDone))
            else ...[
              // Initial batches offer one confirmation; after a run, resume
              // covers any remaining receipts, else retry the failures only.
              FilledButton(
                onPressed: c.submit,
                child: Text(
                  !ran
                      ? l.importImportAll
                      : pending > 0
                      ? l.importResume
                      : l.importRetryFailed,
                ),
              ),
              TextButton(onPressed: c.dismiss, child: Text(l.importLater)),
              _discardButton(c, l),
            ],
          ],
        ),
      ],
    );
  }

  /// Encoding confirmation names the TXT being imported so the choice is
  /// visibly scoped to that file, never presented as a batch-wide setting.
  Widget _encodingPanel(
    BuildContext context,
    ImportController c,
    AppLocalizations l,
  ) {
    final current = c.importingItem;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.importTitle, style: Theme.of(context).textTheme.titleLarge),
          if (current != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ShioriSpace.medium),
              child: Text(
                current.candidate.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: ShioriSpace.medium),
          Text(l.importEncodingHint),
          for (final entry in c.encodingPreview!.samples.entries) ...[
            const SizedBox(height: ShioriSpace.medium),
            Text(entry.value),
            OutlinedButton(
              onPressed: () => c.confirmEncoding(entry.key),
              child: Text(_encodingName(entry.key)),
            ),
          ],
          const SizedBox(height: ShioriSpace.item),
          Align(alignment: Alignment.centerLeft, child: _stopButton(c, l)),
        ],
      ),
    );
  }

  String _workLabel(ImportController c, AppLocalizations l) =>
      c.workStage == ImportWorkStage.reading
      ? l.importFileReading
      : l.importBookProcessing;

  double? _progressValue(ImportController c, ImportItemState item) {
    if (c.workStage != ImportWorkStage.reading) return null;
    final size = item.candidate.size;
    if (size <= 0) return null;
    return (c.copiedBytes / size).clamp(0.0, 1.0);
  }

  String _encodingName(TxtEncoding e) => switch (e) {
    TxtEncoding.utf8 => 'UTF-8',
    TxtEncoding.utf16le => 'UTF-16 LE',
    TxtEncoding.utf16be => 'UTF-16 BE',
    TxtEncoding.gb18030 => 'GB18030 / GBK',
  };
}

/// One staged file: icon + readable status (never color-only), ellipsized
/// name, per-item error and a formatted size. No paths or receipt ids.
class _ImportItemTile extends StatelessWidget {
  const _ImportItemTile({required this.item, required this.l});
  final ImportItemState item;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = switch (item.phase) {
      ImportItemPhase.succeeded => (Icons.check_circle, l.importItemImported),
      ImportItemPhase.importing => (null, l.importItemImporting),
      ImportItemPhase.failed => (
        Icons.error_outline,
        _problemText(l, item.problem ?? ImportProblem.unreadable),
      ),
      ImportItemPhase.ready => (Icons.radio_button_unchecked, l.importWaiting),
    };
    final color = switch (item.phase) {
      ImportItemPhase.succeeded => scheme.primary,
      ImportItemPhase.failed => scheme.error,
      _ => scheme.onSurfaceVariant,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: status.$1 == null
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Icon(status.$1, size: 18, color: color),
          ),
          const SizedBox(width: ShioriSpace.small),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.candidate.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  status.$2,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (item.candidate.size > 0) ...[
            const SizedBox(width: ShioriSpace.small),
            Text(
              _formatSize(item.candidate.size),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
