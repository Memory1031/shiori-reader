/// Closed data-layer reasons only: never accept paths, titles, URLs or errors.
enum EpubDiagnosticCode {
  missingImage,
  unsupportedImage,
  noUsableImage,
  missingNavigation,
  unusableNavigation,
  syntheticNavigation,
  missingNavigationTarget,
  missingFragment,
  spineFallback,
}

final class EpubDiagnostics {
  EpubDiagnostics._(Iterable<EpubDiagnosticCode> codes, this.truncated)
    : codes = List.unmodifiable(codes);
  final List<EpubDiagnosticCode> codes;
  final bool truncated;
}

/// Per-parse ownership; snapshots are immutable and never stored with the book.
final class EpubDiagnosticCollector {
  static const capacity = 100;
  final _codes = <EpubDiagnosticCode>[];
  bool _truncated = false;
  void add(EpubDiagnosticCode code) {
    if (_codes.length < capacity) {
      _codes.add(code);
    } else {
      _truncated = true;
    }
  }

  EpubDiagnostics snapshot() => EpubDiagnostics._(_codes, _truncated);
}

/// Optional decoder observer owned by its caller. Retains only the latest
/// successful decode report; no file identity or contents accompany it.
final class EpubDiagnosticSlot {
  EpubDiagnostics? _latest;
  EpubDiagnostics? get latest => _latest;
  void clear() => _latest = null;
  void record(EpubDiagnostics report) => _latest = report;
}
