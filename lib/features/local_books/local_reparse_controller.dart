import 'package:flutter/foundation.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/models/models.dart';

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
  List<(String, AppFailure)> get failures => List.unmodifiable(_failures);
  int get failed => _failures.length;
  int get unprocessed => total - succeeded - failed;
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
    for (final book in targets) {
      if (request.token.isCancelled) break;
      active = book;
      index++;
      _changed();
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
        case Failure(:final failure):
          if (request.token.isCancelled || failure.isCancellation) {
            request.cancel();
          } else {
            _failures.add((book.title, failure));
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
