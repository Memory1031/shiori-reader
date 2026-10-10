import 'package:flutter/foundation.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/models/models.dart';
import '../bookshelf/book_selection_controller.dart';

/// Metadata needed to reparse, without reading a book's content or manifest.
class LocalReparseTarget {
  const LocalReparseTarget(this.key, this.title, this.format);
  factory LocalReparseTarget.fromInfo(LocalBookInfo info) =>
      LocalReparseTarget(info.key, info.title, info.format);
  final NovelKey key;
  final String title;
  final LocalBookFormat format;
}

enum LocalReparsePhase { idle, running, cancelling, finished }

typedef ReparseEncodingChooser =
    Future<TxtEncoding?> Function(
      LocalReparseTarget book,
      TxtEncodingPreview preview,
    );

/// Owns one serial operation. Cancellation holds ownership until the service
/// unwinds; a committed success stays authoritative even after Stop.
class LocalReparseController extends ChangeNotifier {
  LocalReparseController(this.service);
  final LocalBookReparse service;
  CancellationSource? _request;
  bool _disposed = false;
  LocalReparsePhase phase = LocalReparsePhase.idle;
  bool batch = false;
  LocalReparseTarget? active;
  int index = 0, total = 0, succeeded = 0, approximate = 0;
  bool cleanupPending = false;
  final List<(String, AppFailure)> _failures = [];
  final List<BookBatchOutcome> _outcomes = [];
  List<BookBatchOutcome> get outcomes => List.unmodifiable(_outcomes);
  int get skipped =>
      _outcomes.where((r) => r.status == BookBatchStatus.missing).length;
  List<(String, AppFailure)> get failures => List.unmodifiable(_failures);
  int get failed => _failures.length;
  int get unprocessed => total - succeeded - failed - skipped;
  AppFailure? get failure =>
      batch || _failures.isEmpty ? null : _failures.first.$2;
  bool get busy =>
      phase == LocalReparsePhase.running ||
      phase == LocalReparsePhase.cancelling;
  bool get cancellationRequested => _request?.token.isCancelled ?? false;
  CancellationToken? get cancellation => _request?.token;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    if (!busy) return;
    _request!.cancel();
    phase = LocalReparsePhase.cancelling;
    _changed();
  }

  Future<void> run(
    Iterable<LocalReparseTarget> books, {
    required bool batch,
    required ReparseEncodingChooser chooseEncoding,
    TxtEncoding? encoding,
    bool? Function(NovelKey key)? exists,
  }) async {
    if (_disposed || busy) return;
    final targets = List<LocalReparseTarget>.of(books);
    if (targets.isEmpty) return;
    final request = _request = CancellationSource();
    this.batch = batch;
    phase = LocalReparsePhase.running;
    index = succeeded = approximate = 0;
    total = targets.length;
    cleanupPending = false;
    _failures.clear();
    _outcomes.clear();
    _outcomes.addAll(
      targets.map(
        (book) =>
            BookBatchOutcome(book.key, book.title, BookBatchStatus.unprocessed),
      ),
    );
    for (final book in targets) {
      if (request.token.isCancelled) break;
      active = book;
      index++;
      _changed();
      if (exists?.call(book.key) == false) {
        _outcomes[index - 1] = BookBatchOutcome(
          book.key,
          book.title,
          BookBatchStatus.missing,
        );
        continue;
      }
      final result = await _perform(
        book,
        request,
        chooseEncoding,
        batch ? null : encoding,
      );
      switch (result) {
        case Success(:final value):
          succeeded++;
          if (value.approximate) approximate++;
          cleanupPending |= value.cleanupPending;
          _outcomes[index - 1] = BookBatchOutcome(
            book.key,
            book.title,
            BookBatchStatus.succeeded,
            approximate: value.approximate,
            cleanupPending: value.cleanupPending,
          );
        case Failure(:final failure):
          if (request.token.isCancelled || failure.isCancellation) {
            request.cancel();
          } else if (failure.kind == FailureKind.notFound) {
            _outcomes[index - 1] = BookBatchOutcome(
              book.key,
              book.title,
              BookBatchStatus.missing,
            );
          } else {
            _failures.add((book.title, failure));
            _outcomes[index - 1] = BookBatchOutcome(
              book.key,
              book.title,
              BookBatchStatus.failed,
              failure: failure,
            );
            if (failure.kind == FailureKind.unsupported) request.cancel();
          }
      }
    }
    active = null;
    phase = LocalReparsePhase.finished;
    _changed();
  }

  Future<Result<LocalReparseResult>> _perform(
    LocalReparseTarget book,
    CancellationSource request,
    ReparseEncodingChooser chooser,
    TxtEncoding? encoding,
  ) async {
    try {
      return await service.reparseBook(
        book.key,
        encoding: encoding,
        cancellation: request.token,
        chooseEncoding: (preview) async {
          if (_disposed || request.token.isCancelled) {
            throw const LocalParseException(LocalParseProblem.encoding);
          }
          final choice = await chooser(book, preview);
          if (choice == null || _disposed || request.token.isCancelled) {
            request.cancel();
            throw const LocalParseException(LocalParseProblem.encoding);
          }
          return choice;
        },
      );
    } catch (_) {
      // Preserve the previous presentation-level exception mapping.
      return Failure(
        request.token.isCancelled
            ? AppFailure.cancelled(Operation.libraryWrite)
            : AppFailure(
                kind: FailureKind.database,
                operation: Operation.libraryWrite,
              ),
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _request?.cancel();
    super.dispose();
  }
}
