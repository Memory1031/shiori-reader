import 'dart:async';

/// Staged OS input. IDs are opaque; paths and temporary URI grants stay in data.
final class ImportCandidate {
  const ImportCandidate({
    required this.id,
    required this.name,
    required this.size,
    this.error,
  });
  final String id;
  final String name;
  final int size;
  final ImportProblem? error;
}

enum ImportProblem {
  unreadable,
  tooLarge,
  batchLimit,
  unsupported,
  multiple,
  busy,
  invalidContent,
  parserUnavailable,
  encoding,
  drm,
  fixedLayout,
  parseLimit,
  storage,
  cancelled,
}

final class ImportSourceException implements Exception {
  const ImportSourceException(this.problem);
  final ImportProblem problem;
}

final class ImportSourceEvent {
  const ImportSourceEvent({
    this.copiedBytes,
    this.problem,
    this.completed = false,
  });
  final ImportProblem? problem;
  final bool completed;
  final int? copiedBytes;
}

/// Native copies are durable before pending() exposes them. pending returns
/// the ordered receipts still awaiting confirmation; a single staged file is a
/// batch of one. acknowledge is idempotent and must only remove the named
/// receipt, never a newer arrival or another pending receipt.
abstract interface class ImportSource {
  Stream<ImportSourceEvent> get changes;
  Future<void> pick();
  Future<List<ImportCandidate>> pending();
  Stream<List<int>> read(ImportCandidate candidate);
  Future<void> acknowledge(String id);
  Future<void> cancelCopy();
  Future<void> close();
}
