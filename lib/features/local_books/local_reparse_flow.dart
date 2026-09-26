import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';
import 'local_reparse_controller.dart';

/// Page-owned interaction session shared by Local Books and Shelf. The lock
/// includes confirmation and result UI, not just the underlying operation.
class LocalReparseFlow extends ChangeNotifier {
  LocalReparseFlow(LocalBookReparse service)
    : controller = LocalReparseController(service) {
    controller.addListener(_changed);
  }
  final LocalReparseController controller;
  final _routes = <DialogRoute<dynamic>>[];
  bool _disposed = false, _busy = false, _modal = false;
  bool get busy => _busy;

  /// Presentation is fixed for the session; resizing must not orphan Stop.
  bool get modal => _modal;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<T?> _dialog<T>(
    BuildContext context,
    WidgetBuilder builder, {
    bool dismissible = true,
    CancellationToken? cancellation,
  }) async {
    if (_disposed || !context.mounted || cancellation?.isCancelled == true) {
      return null;
    }
    final route = DialogRoute<T>(
      context: context,
      builder: builder,
      barrierDismissible: dismissible,
    );
    _routes.add(route);
    var settled = false;
    unawaited(
      cancellation?.whenCancelled.then((_) {
        if (!settled && route.isActive) route.navigator?.removeRoute(route);
      }),
    );
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      settled = true;
      _routes.remove(route);
    }
  }

  Future<void> start(
    BuildContext context,
    Iterable<LocalReparseTarget> books, {
    bool batch = false,
    bool desktop = false,
  }) async {
    if (_disposed || _busy) return;
    final targets = List<LocalReparseTarget>.of(books);
    if (targets.isEmpty) return;
    _busy = true;
    _modal = desktop;
    _changed();
    final l = AppLocalizations.of(context);
    TxtEncoding? encoding;
    try {
      final confirmed = await _dialog<bool>(
        context,
        (dialog) => StatefulBuilder(
          builder: (context, change) => AlertDialog(
            title: Text(batch ? l.localReparseAll : l.localReparse),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  batch
                      ? l.localReparseAllConfirm(targets.length)
                      : l.localReparseConfirm,
                ),
                if (!batch && targets.single.format == LocalBookFormat.txt)
                  DropdownButton<TxtEncoding>(
                    isExpanded: true,
                    value: encoding,
                    hint: Text(l.importEncodingAuto),
                    items: [
                      for (final e in TxtEncoding.values)
                        DropdownMenuItem(
                          value: e,
                          child: Text(e.name.toUpperCase()),
                        ),
                    ],
                    onChanged: (e) => change(() => encoding = e),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(l.importCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(batch ? l.localReparseAll : l.localReparse),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || _disposed || !context.mounted) return;
      final operation = Future<void>.microtask(
        () => controller.run(
          targets,
          batch: batch,
          encoding: encoding,
          chooseEncoding: (book, preview) => _dialog<TxtEncoding>(
            context,
            (dialog) => AlertDialog(
              title: Text(book.title),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.importEncodingHint),
                      for (final entry in preview.samples.entries)
                        ListTile(
                          title: Text(entry.key.name.toUpperCase()),
                          subtitle: Text(entry.value),
                          onTap: () => Navigator.pop(dialog, entry.key),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: Text(l.importCancel),
                ),
              ],
            ),
            cancellation: controller.cancellation,
          ),
        ),
      );
      if (desktop) {
        // Defer service entry to a microtask below the operation route, so an
        // immediate encoding request is always above its owning dialog.
        await _dialog<void>(
          context,
          (dialog) => _OperationDialog(controller: controller),
          dismissible: false,
        );
        // A route replacement may close the dialog while the service unwinds.
        controller.cancel();
      }
      await operation;
      if (_disposed || !context.mounted || desktop) return;
      if (batch) {
        await _dialog<void>(
          context,
          (dialog) => AlertDialog(
            title: Text(l.localReparseAll),
            scrollable: true,
            content: LocalReparseResultView(controller: controller),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(l.importDone),
              ),
            ],
          ),
        );
      } else if (controller.succeeded > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reparseSuccessMessage(l, controller))),
        );
      }
    } finally {
      _busy = false;
      _changed();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.removeListener(_changed);
    controller.dispose();

    final routes = List<DialogRoute<dynamic>>.of(_routes.reversed);
    // The owner may be disposed while a Navigator is finalizing replacement.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in routes) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
    super.dispose();
  }
}

String reparseSuccessMessage(AppLocalizations l, LocalReparseController c) =>
    '${c.approximate > 0 ? l.localReparseApproximate : l.localReparseDone}${c.cleanupPending ? '\n${l.localCleanupPending}' : ''}';

class LocalReparseResultView extends StatelessWidget {
  const LocalReparseResultView({super.key, required this.controller});
  final LocalReparseController controller;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), c = controller;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.batch)
          Text(l.localReparseAllSummary(c.succeeded, c.failed, c.unprocessed))
        else if (c.succeeded > 0)
          Text(reparseSuccessMessage(l, c)),
        if (!c.batch && c.succeeded == 0 && c.failed == 0)
          Text(l.updateCancelled),
        if (c.batch && c.approximate > 0)
          Text(l.localReparseAllApproximate(c.approximate)),
        if (c.batch && c.cleanupPending) Text(l.localCleanupPending),
        for (final (title, failure) in c.failures)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('$title\n${failureMessage(l, failure)}'),
          ),
      ],
    );
  }
}

class _OperationDialog extends StatelessWidget {
  const _OperationDialog({required this.controller});
  final LocalReparseController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, l = AppLocalizations.of(context);
      return PopScope(
        canPop: !c.busy,
        child: Shortcuts(
          shortcuts: {
            if (c.busy)
              const SingleActivator(LogicalKeyboardKey.escape):
                  const DoNothingAndStopPropagationIntent(),
          },
          child: AlertDialog(
            title: Text(c.batch ? l.localReparseAll : l.localReparse),
            scrollable: true,
            content: c.busy
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.localReparseAllProgress(
                          c.index,
                          c.total,
                          c.active?.title ?? '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  )
                : LocalReparseResultView(controller: c),
            actions: [
              TextButton(
                onPressed: c.busy
                    ? (c.cancellationRequested ? null : c.cancel)
                    : () => Navigator.pop(context),
                child: Text(
                  c.busy
                      ? (c.batch ? l.localReparseStop : l.importCancel)
                      : l.importDone,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
