import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';
import 'local_reparse_controller.dart';
import '../bookshelf/book_selection_controller.dart';
import '../bookshelf/book_batch_views.dart';

enum LocalReparseIntent { single, selected, all }

/// Page-owned interaction session shared by Local Books and Shelf. The lock
/// includes confirmation and result UI, not just the underlying operation.
class LocalReparseFlow extends ChangeNotifier {
  LocalReparseFlow(LocalBookReparse service)
    : controller = LocalReparseController(service) {
    controller.addListener(_changed);
  }
  final LocalReparseController controller;
  final _routes = <ModalRoute<dynamic>>[];
  bool _disposed = false, _busy = false, _modal = false;
  bool get busy => _busy;

  /// Presentation is fixed for the session; resizing must not orphan Stop.
  bool get modal => _modal;
  CancellationSource? _session;

  /// Retires confirmation and encoding routes; committed work still settles.
  void cancelSession() {
    _session?.cancel();
    controller.cancel();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<T?> _dialog<T>(
    BuildContext context,
    WidgetBuilder builder, {
    bool dismissible = true,
    bool panel = false,
    CancellationToken? cancellation,
  }) async {
    if (_disposed || !context.mounted || cancellation?.isCancelled == true) {
      return null;
    }
    final ModalRoute<T> route = panel
        ? bookBatchRoute<T>(context, builder, dismissible: dismissible)
        : DialogRoute<T>(
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

  Future<List<BookBatchOutcome>?> start(
    BuildContext context,
    Iterable<LocalReparseTarget> books, {
    bool batch = false,
    bool desktop = false,
    LocalReparseIntent? intent,
    int excluded = 0,
    bool? Function(NovelKey key)? exists,
    List<BookSelectionItem> excludedBooks = const [],
  }) async {
    if (_disposed || _busy) return null;
    final selected = intent == LocalReparseIntent.selected;
    batch = selected || intent == LocalReparseIntent.all || batch;
    final targets = List<LocalReparseTarget>.of(books);
    if (targets.isEmpty) return null;
    final session = _session = CancellationSource();
    _busy = true;
    _modal = desktop || selected;
    _changed();
    final l = AppLocalizations.of(context);
    TxtEncoding? encoding;
    try {
      final confirmed = await _dialog<bool>(
        context,
        (dialog) => selected
            ? BookBatchPanel(
                title: l.bookReparseSelected(targets.length),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.bookReparseSelectedConfirm(targets.length, excluded),
                    ),
                    BookBatchPreview(
                      books: targets
                          .map(
                            (b) => BookSelectionItem(
                              b.key,
                              b.title,
                              format: b.format,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
                actions: [
                  BookBatchAction(
                    l.importCancel,
                    () => Navigator.pop(dialog, false),
                  ),
                  BookBatchAction(
                    l.bookReparseSelected(targets.length),
                    () => Navigator.pop(dialog, true),
                    primary: true,
                  ),
                ],
              )
            : StatefulBuilder(
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
                      if (!batch &&
                          targets.single.format == LocalBookFormat.txt)
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
        panel: selected,
        cancellation: session.token,
      );
      if (confirmed != true ||
          _disposed ||
          !context.mounted ||
          session.token.isCancelled) {
        return null;
      }
      unawaited(session.token.whenCancelled.then((_) => controller.cancel()));
      final operation = Future<void>.microtask(
        () => session.token.isCancelled
            ? Future.value()
            : controller.run(
                targets,
                batch: batch,
                encoding: encoding,
                exists: exists,
                chooseEncoding: (book, preview) => _dialog<TxtEncoding>(
                  context,
                  (dialog) {
                    final choices = Column(
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
                    );
                    return selected
                        ? BookBatchPanel(
                            title: book.title,
                            content: choices,
                            actions: [
                              BookBatchAction(
                                l.importCancel,
                                () => Navigator.pop(dialog),
                              ),
                            ],
                          )
                        : AlertDialog(
                            title: Text(book.title),
                            content: SizedBox(
                              width: 420,
                              child: SingleChildScrollView(child: choices),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialog),
                                child: Text(l.importCancel),
                              ),
                            ],
                          );
                  },
                  panel: selected,
                  cancellation: controller.cancellation,
                ),
              ),
      );
      if (_modal) {
        // Defer service entry to a microtask below the operation route, so an
        // immediate encoding request is always above its owning dialog.
        await _dialog<void>(
          context,
          (dialog) => _OperationDialog(
            controller: controller,
            selected: selected,
            excludedBooks: excludedBooks,
          ),
          dismissible: false,
          panel: selected,
          cancellation: session.token,
        );
        // A route replacement may close the dialog while the service unwinds.
        controller.cancel();
      }
      await operation;
      if (_disposed || !context.mounted || session.token.isCancelled) {
        return null;
      }
      if (_modal) return controller.outcomes;
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
      return controller.outcomes;
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
    _session?.cancel();

    final routes = List<ModalRoute<dynamic>>.of(_routes.reversed);
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
  const _OperationDialog({
    required this.controller,
    this.selected = false,
    this.excludedBooks = const [],
  });
  final LocalReparseController controller;
  final bool selected;
  final List<BookSelectionItem> excludedBooks;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, l = AppLocalizations.of(context);
      final label = c.busy
          ? (c.batch ? l.localReparseStop : l.importCancel)
          : l.importDone;
      final VoidCallback? action = c.busy
          ? (c.cancellationRequested ? null : c.cancel)
          : () => Navigator.pop(context);
      return PopScope(
        canPop: !c.busy,
        child: Shortcuts(
          shortcuts: {
            if (c.busy)
              const SingleActivator(LogicalKeyboardKey.escape):
                  const DoNothingAndStopPropagationIntent(),
          },
          child: selected
              ? BookBatchPanel(
                  title: c.busy
                      ? l.bookReparseSelected(c.total)
                      : l.bookBatchResults,
                  content: c.busy
                      ? BookBatchProgressView(
                          title: c.active?.title ?? '',
                          index: c.index,
                          total: c.total,
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            BookBatchResultView(
                              outcomes: [
                                ...c.outcomes,
                                for (final b in excludedBooks)
                                  BookBatchOutcome(
                                    b.key,
                                    b.title,
                                    BookBatchStatus.inapplicable,
                                  ),
                              ],
                            ),
                            if (c.approximate > 0)
                              BookBatchNote(
                                l.localReparseAllApproximate(c.approximate),
                              ),
                            if (c.cleanupPending)
                              BookBatchNote(l.bookReparseCleanupPending),
                          ],
                        ),
                  actions: [BookBatchAction(label, action)],
                )
              : AlertDialog(
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
                  actions: [TextButton(onPressed: action, child: Text(label))],
                ),
        ),
      );
    },
  );
}
