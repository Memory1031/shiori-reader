import 'package:flutter/foundation.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';

/// A lightweight visible-book snapshot; never loads a manifest for selection.
class BookSelectionItem {
  const BookSelectionItem(this.key, this.title, {this.format});
  final NovelKey key;
  final String title;
  final LocalBookFormat? format;
  bool get local => key.sourceId == LocalBookIdentity.sourceId;
}

enum BookBatchStatus { succeeded, failed, unprocessed, missing, inapplicable }

class BookBatchOutcome {
  const BookBatchOutcome(
    this.key,
    this.title,
    this.status, {
    this.failure,
    this.approximate = false,
    this.cleanupPending = false,
  });
  final NovelKey key;
  final String title;
  final BookBatchStatus status;
  final AppFailure? failure;
  final bool approximate, cleanupPending;
}

/// One page's selection. Watch failures preserve the last reliable snapshot.
class BookSelectionController extends ChangeNotifier {
  bool active = false, reliable = false;
  bool _disposed = false;
  List<BookSelectionItem> _visible = const [];
  final Set<NovelKey> _selected = {};
  Set<NovelKey> get selected => Set.unmodifiable(_selected);
  List<BookSelectionItem> get visible => _visible;
  List<BookSelectionItem> get snapshot =>
      _visible.where((book) => _selected.contains(book.key)).toList();
  bool get canEnter => reliable && _visible.isNotEmpty;
  bool get allSelected =>
      _visible.isNotEmpty && _visible.every((b) => _selected.contains(b.key));
  bool? exists(NovelKey key) =>
      reliable ? _visible.any((book) => book.key == key) : null;

  void updateVisible(Iterable<BookSelectionItem>? books) {
    reliable = books != null;
    if (books != null) {
      _visible = List.unmodifiable(books);
      _selected.retainAll(_visible.map((book) => book.key));
    }
    _changed();
  }

  void enter([NovelKey? initial]) {
    if (!canEnter || _disposed) return;
    active = true;
    _selected.clear();
    if (initial != null && exists(initial) == true) _selected.add(initial);
    _changed();
  }

  void toggle(NovelKey key) {
    if (!active || !_visible.any((book) => book.key == key)) return;
    if (!_selected.remove(key)) _selected.add(key);
    _changed();
  }

  void toggleAll() {
    if (!active || !reliable) return;
    if (allSelected) {
      _selected.removeAll(_visible.map((book) => book.key));
    } else {
      _selected.addAll(_visible.map((book) => book.key));
    }
    _changed();
  }

  void accept(Iterable<BookBatchOutcome> outcomes) {
    _selected.removeAll(
      outcomes
          .where(
            (r) =>
                r.status == BookBatchStatus.succeeded ||
                r.status == BookBatchStatus.missing,
          )
          .map((r) => r.key),
    );
    if (_selected.isEmpty) active = false;
    _changed();
  }

  void exit() {
    if (!active && _selected.isEmpty) return;
    active = false;
    _selected.clear();
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
