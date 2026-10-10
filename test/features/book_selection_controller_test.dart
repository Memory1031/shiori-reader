import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/book_selection_controller.dart';

final books = List.generate(
  30,
  (i) => BookSelectionItem(
    NovelKey(sourceId: SourceId('fixture'), novelId: '$i'),
    'Same title',
  ),
);

void main() {
  test('keys survive sorting; all is a snapshot, failures do not erase it', () {
    final c = BookSelectionController();
    c.enter();
    expect(c.active, isFalse);
    c.updateVisible(books);
    c.enter();
    expect(c.selected, isEmpty);
    c.toggle(books[1].key);
    c.toggle(books[0].key);
    c.updateVisible(books.reversed);
    expect(c.selected, {books[0].key, books[1].key});
    c.toggleAll();
    expect(c.selected, hasLength(30));
    c.updateVisible(null);
    expect(c.selected, hasLength(30));
    expect(c.exists(books[0].key), isNull);
    c.updateVisible([
      ...books,
      BookSelectionItem(
        NovelKey(sourceId: SourceId('fixture'), novelId: 'new'),
        'New',
      ),
    ]);
    expect(c.selected, hasLength(30));
    expect(c.allSelected, isFalse);
    c.updateVisible(books.skip(1));
    expect(c.selected, hasLength(29));
    expect(c.selected, isNot(contains(books[0].key)));
    c.dispose();
  });
  test(
    'filter and keyed outcomes preserve same-title failed and stopped items',
    () {
      final c = BookSelectionController()
        ..updateVisible(books)
        ..enter()
        ..toggleAll();
      c.updateVisible(books.take(4));
      expect(c.selected, hasLength(4));
      c.accept([
        BookBatchOutcome(books[0].key, 'Same title', BookBatchStatus.succeeded),
        BookBatchOutcome(books[1].key, 'Same title', BookBatchStatus.failed),
        BookBatchOutcome(
          books[2].key,
          'Same title',
          BookBatchStatus.unprocessed,
        ),
        BookBatchOutcome(
          books[3].key,
          'Same title',
          BookBatchStatus.inapplicable,
        ),
      ]);
      expect(c.snapshot.map((b) => b.key), [
        books[1].key,
        books[2].key,
        books[3].key,
      ]);
      c.toggleAll();
      c.toggleAll();
      expect(c.selected, isEmpty);
      expect(c.active, isTrue);
      c.exit();
      expect(c.active, isFalse);
      c.dispose();
    },
  );
}
