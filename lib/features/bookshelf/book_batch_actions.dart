import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../local_books/local_reparse_controller.dart';
import '../local_books/local_reparse_flow.dart';
import 'book_batch_views.dart';
import 'book_selection_controller.dart';
import 'library_controller.dart';

/// Page-owned selection and selected-book operations. The shelf host may keep
/// this owner across responsive layout changes; Local Books owns its own.
class BookBatchActions extends ChangeNotifier with WidgetsBindingObserver {
  BookBatchActions(
    this.library, {
    LocalBookReparse? reparse,
    this.bindShelf = false,
  }) : reparse = reparse == null ? null : LocalReparseFlow(reparse) {
    selection.addListener(_changed);
    this.reparse?.addListener(_changed);
    if (bindShelf) {
      library.addListener(_shelfChanged);
      _shelfChanged();
    }
    WidgetsBinding.instance.addObserver(this);
  }
  final LibraryController library;
  final bool bindShelf;
  final selection = BookSelectionController();
  final LocalReparseFlow? reparse;
  CancellationSource? _request;
  CancellationSource? _ownerSession;
  final _routes = <ModalRoute<dynamic>>[];
  bool _disposed = false, _removing = false, _running = false;
  bool get busy => _removing || reparse?.busy == true;
  bool get canEnter => !busy && library.batchAvailable && selection.canEnter;
  int get eligible => reparse == null
      ? 0
      : selection.snapshot.where((b) => b.local && b.format != null).length;
  int index = 0;
  String activeTitle = '';
  List<BookBatchOutcome> _outcomes = const [];
  List<BookBatchOutcome> get outcomes => _outcomes;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _shelfChanged() {
    if (_disposed) return;
    selection.updateVisible(
      !library.shelfReady || library.shelfFailure != null
          ? null
          : library.sorted.map(
              (entry) => BookSelectionItem(
                entry.snapshot.key,
                entry.snapshot.title,
                format: library.localFormats[entry.snapshot.key],
              ),
            ),
    );
  }

  void enter([NovelKey? initial]) {
    if (canEnter) selection.enter(initial);
  }

  void leave() {
    _request?.cancel();
    _ownerSession?.cancel();
    reparse?.cancelSession();
    selection.exit();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      leave();
    }
  }

  Future<T?> _dialog<T>(
    BuildContext context,
    WidgetBuilder builder, {
    bool confirmation = false,
    bool retireOnCancel = false,
  }) async {
    if (_disposed ||
        !context.mounted ||
        _request?.token.isCancelled == true && confirmation) {
      return null;
    }
    final route = bookBatchRoute<T>(
      context,
      builder,
      dismissible: confirmation,
    );
    _routes.add(route);
    var settled = false;
    if (confirmation || retireOnCancel) {
      final token = confirmation ? _request!.token : _ownerSession!.token;
      unawaited(
        token.whenCancelled.then((_) {
          if (!settled && route.isActive) route.navigator?.removeRoute(route);
        }),
      );
    }
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      settled = true;
      _routes.remove(route);
    }
  }

  Future<void> reparseSelected(BuildContext context) async {
    if (busy || eligible == 0 || !selection.active) return;
    final snapshot = selection.snapshot;
    final targets = snapshot
        .where((b) => b.local && b.format != null)
        .map((b) => LocalReparseTarget(b.key, b.title, b.format!))
        .toList();
    final request = _request = CancellationSource();
    _ownerSession = CancellationSource();
    final lease = library.acquireBatch(request);
    if (lease == null) return;
    unawaited(
      request.token.whenCancelled.then((_) => reparse?.cancelSession()),
    );
    try {
      final result = await reparse!.start(
        context,
        targets,
        intent: LocalReparseIntent.selected,
        excluded: snapshot.length - targets.length,
        exists: selection.exists,
        excludedBooks: snapshot
            .where((b) => !b.local || b.format == null)
            .toList(),
      );
      if (!_disposed && result != null) {
        _outcomes = List.unmodifiable([
          ...result,
          for (final item in snapshot.where(
            (b) => !b.local || b.format == null,
          ))
            BookBatchOutcome(
              item.key,
              item.title,
              BookBatchStatus.inapplicable,
            ),
        ]);
        selection.accept(_outcomes);
      }
    } finally {
      lease.release();
      _changed();
    }
  }

  Future<void> removeSelected(BuildContext context) async {
    if (busy || !selection.active || selection.selected.isEmpty) return;
    final snapshot = List<BookSelectionItem>.unmodifiable(selection.snapshot);
    final request = _request = CancellationSource();
    _ownerSession = CancellationSource();
    final lease = library.acquireBatch(request);
    if (lease == null) return;
    _removing = true;
    _changed();
    final l = AppLocalizations.of(context);
    final local = snapshot.where((b) => b.local).length;
    final online = snapshot.length - local;
    final title = local == 0
        ? l.bookBatchOnlineTitle
        : online == 0
        ? l.bookBatchLocalTitle
        : l.bookBatchRemoveTitle;
    try {
      final confirmed = await _dialog<bool>(
        context,
        (dialog) => BookBatchPanel(
          title: title,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.bookBatchRemoveConfirm(snapshot.length)),
              BookBatchRemovalNotice(local: local, online: online),
              BookBatchPreview(books: snapshot),
            ],
          ),
          actions: [
            BookBatchAction(l.importCancel, () => Navigator.pop(dialog, false)),
            BookBatchAction(
              online == 0 ? l.bookDeleteSelected : l.bookRemoveSelected,
              () => Navigator.pop(dialog, true),
              primary: true,
              destructive: true,
            ),
          ],
        ),
        confirmation: true,
      );
      if (confirmed != true ||
          _disposed ||
          !context.mounted ||
          request.token.isCancelled) {
        return;
      }
      _running = true;
      index = 0;
      _outcomes = snapshot
          .map(
            (b) =>
                BookBatchOutcome(b.key, b.title, BookBatchStatus.unprocessed),
          )
          .toList();
      final operation = Future<void>.microtask(() async {
        for (var i = 0; i < snapshot.length; i++) {
          if (request.token.isCancelled || _disposed) break;
          final book = snapshot[i];
          index = i + 1;
          activeTitle = book.title;
          _changed();
          if (selection.exists(book.key) == false) {
            _outcomes[i] = BookBatchOutcome(
              book.key,
              book.title,
              BookBatchStatus.missing,
            );
            continue;
          }
          Result<LocalBookDeletion> result;
          try {
            result = await library.removeInBatch(
              book.key,
              lease,
              cancellation: request.token,
            );
          } catch (_) {
            result = Failure(
              AppFailure(
                kind: FailureKind.database,
                operation: Operation.libraryWrite,
              ),
            );
          }
          switch (result) {
            case Success(:final value):
              _outcomes[i] = BookBatchOutcome(
                book.key,
                book.title,
                BookBatchStatus.succeeded,
                cleanupPending: value.cleanupPending,
              );
            case Failure(:final failure):
              if (request.token.isCancelled || failure.isCancellation) {
                request.cancel();
              } else if (failure.kind == FailureKind.notFound) {
                _outcomes[i] = BookBatchOutcome(
                  book.key,
                  book.title,
                  BookBatchStatus.missing,
                );
              } else {
                _outcomes[i] = BookBatchOutcome(
                  book.key,
                  book.title,
                  BookBatchStatus.failed,
                  failure: failure,
                );
                if (library.isClosed ||
                    failure.kind == FailureKind.unsupported) {
                  request.cancel();
                }
              }
          }
        }
        _running = false;
        _changed();
      });
      await _dialog<void>(
        context,
        (dialog) => ListenableBuilder(
          listenable: this,
          builder: (context, _) => PopScope(
            canPop: !_running,
            child: Shortcuts(
              shortcuts: {
                if (_running)
                  const SingleActivator(LogicalKeyboardKey.escape):
                      const DoNothingAndStopPropagationIntent(),
              },
              child: BookBatchPanel(
                title: _running ? title : l.bookBatchResults,
                content: _running
                    ? BookBatchProgressView(
                        title: activeTitle,
                        index: index,
                        total: snapshot.length,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          BookBatchResultView(outcomes: _outcomes),
                          if (_outcomes.any((r) => r.cleanupPending))
                            BookBatchNote(l.localCleanupPending),
                        ],
                      ),
                actions: [
                  BookBatchAction(
                    _running ? l.localReparseStop : l.importDone,
                    _running
                        ? (request.token.isCancelled
                              ? null
                              : () {
                                  request.cancel();
                                  _changed();
                                })
                        : () => Navigator.pop(dialog),
                  ),
                ],
              ),
            ),
          ),
        ),
        retireOnCancel: true,
      );
      request.cancel();
      await operation;
      if (!_disposed) selection.accept(_outcomes);
    } finally {
      _removing = false;
      lease.release();
      _changed();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (bindShelf && !library.isClosed) library.removeListener(_shelfChanged);
    _request?.cancel();
    _ownerSession?.cancel();
    selection.removeListener(_changed);
    selection.dispose();
    reparse?.removeListener(_changed);
    reparse?.dispose();
    final routes = List.of(_routes.reversed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in routes) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
    super.dispose();
  }
}
