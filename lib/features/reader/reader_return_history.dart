import '../../domain/models/models.dart';

enum ReaderReturnKind { link, search, bookmark }

/// Layout-free semantic position; scope identifies an ephemeral Reader surface.
class ReaderReturnPoint {
  const ReaderReturnPoint(this.chapter, this.position, {required this.scope});
  final ChapterKey chapter;
  final ReaderPosition position;
  final Object scope;
  bool sameLocation(ReaderReturnPoint other) =>
      chapter == other.chapter && position == other.position;
}

final class ReaderReturnEntry {
  ReaderReturnEntry(this.kind, this.origin);
  final ReaderReturnKind kind;
  final ReaderReturnPoint origin;
}

/// One book session's confirmed history. Tickets reject late navigation commits.
final class ReaderReturnHistory {
  final _entries = <ReaderReturnEntry>[];
  int _version = 0;
  int get version => _version;
  ReaderReturnEntry? get top => _entries.lastOrNull;
  List<ReaderReturnEntry> get entries => List.unmodifiable(_entries);

  bool forward(
    ReaderReturnKind kind,
    ReaderReturnPoint origin,
    ReaderReturnPoint destination,
    int ticket,
  ) {
    if (ticket != _version || origin.sameLocation(destination)) return false;
    if (kind != ReaderReturnKind.link && top?.kind == kind) {
      _version++;
      return true;
    }
    _entries.add(ReaderReturnEntry(kind, origin));
    if (_entries.length > 8) _entries.removeAt(0);
    _version++;
    return true;
  }

  bool consume(ReaderReturnEntry entry, int ticket) {
    if (ticket != _version || !identical(top, entry)) return false;
    _entries.removeLast();
    _version++;
    return true;
  }

  void explicit(
    ReaderReturnPoint origin,
    ReaderReturnPoint destination,
    int ticket,
  ) {
    if (ticket == _version && !origin.sameLocation(destination)) clear();
  }

  void invalidateTickets() => _version++;

  void clear() {
    _entries.clear();
    _version++;
  }

  /// System-closing a document discards only its internal/consumed route layers.
  void closeScope(
    Object scope,
    ReaderReturnPoint? parent,
    ReaderReturnEntry? boundary,
  ) {
    final count = _entries.length;
    _entries.removeWhere((e) => identical(e.origin.scope, scope));
    if (boundary != null &&
        identical(top, boundary) &&
        parent != null &&
        top?.origin.sameLocation(parent) == true &&
        identical(top!.origin.scope, parent.scope)) {
      _entries.removeLast();
    }
    if (_entries.length != count) _version++;
  }
}
