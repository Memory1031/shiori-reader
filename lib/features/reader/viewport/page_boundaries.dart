import 'page_layout.dart';

/// Layout-scoped cursor bookkeeping, independent of the bounded rendered-page
/// cache. Unknown predecessors may be found backwards, but known pages retain
/// the direction and exact anchor that originally produced their boundaries.
class PageBoundaries {
  PageBoundaries(this.layout);
  final PageLayout layout;
  final _starts = <(int, int), _Boundary>{};
  final _ends = <(int, int), _Boundary>{};

  static int compare(PageCursor a, PageCursor b) => a.unit == b.unit
      ? a.offset.compareTo(b.offset)
      : a.unit.compareTo(b.unit);

  /// Reuse a known forward anchor, never invent a page at the target character.
  PageCursor seekStart(PageCursor target) {
    var best = const PageCursor(0, 0);
    for (final boundary in _starts.values) {
      if (boundary.forward &&
          compare(boundary.start, target) <= 0 &&
          compare(boundary.start, best) > 0) {
        best = boundary.start;
      }
    }
    return best;
  }

  ReaderPage? forward(PageCursor start) {
    final known = _starts[(start.unit, start.offset)];
    if (known != null) return _rebuild(known);
    return _remember(layout.forward(start), true);
  }

  ReaderPage? backward(PageCursor end) {
    final known = _ends[(end.unit, end.offset)];
    if (known != null) return _rebuild(known);
    return _remember(layout.backward(end), false);
  }

  ReaderPage? _rebuild(_Boundary boundary) => boundary.forward
      ? layout.forward(boundary.start)
      : layout.backward(boundary.end);

  ReaderPage? _remember(ReaderPage? page, bool forward) {
    if (page == null) return null;
    final boundary = _Boundary(page.start, page.end, forward);
    _starts[(page.start.unit, page.start.offset)] = boundary;
    _ends[(page.end.unit, page.end.offset)] = boundary;
    return page;
  }
}

class _Boundary {
  const _Boundary(this.start, this.end, this.forward);
  final PageCursor start, end;
  final bool forward;
}
