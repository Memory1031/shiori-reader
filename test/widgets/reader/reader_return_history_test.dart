import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_return_history.dart';

final book = NovelKey(sourceId: SourceId('local'), novelId: 'returns');
final scope = Object();
ReaderReturnPoint point(int n, {Object? surface}) => ReaderReturnPoint(
  ChapterKey(novelKey: book, chapterId: '$n'),
  ReaderPosition(
    contentRevision: 'revision',
    blockKey: 'block',
    blockIndex: 0,
    blockFraction: 0,
    chapterFraction: 0,
  ),
  scope: surface ?? scope,
);
ReaderReturnKind kind(String s) => switch (s) {
  'L' => ReaderReturnKind.link,
  'S' => ReaderReturnKind.search,
  _ => ReaderReturnKind.bookmark,
};
void main() {
  test('ordinary reading invalidates old tickets without ending the chain', () {
    final h = ReaderReturnHistory();
    h.forward(kind('K'), point(0), point(1), h.version);
    final entry = h.top!, ticket = h.version;
    h.invalidateTickets();
    expect(h.top, same(entry));
    expect(h.consume(entry, ticket), isFalse);
    h.closeScope(Object(), point(0), null);
    expect(h.top, same(entry));
    expect(h.consume(entry, h.version), isTrue);
  });
  test('mixed kinds share one global eight-layer bound', () {
    final h = ReaderReturnHistory();
    for (var i = 0; i < 12; i++) {
      h.forward(
        ReaderReturnKind.values[i % 3],
        point(i),
        point(i + 1),
        h.version,
      );
    }
    expect(h.entries.length, 8);
    expect(h.entries.first.origin.chapter.chapterId, '4');
  });

  for (final (path, targets) in [
    ('LL', [1, 0]),
    ('SS', [0]),
    ('KK', [0]),
    ('LS', [1, 0]),
    ('SL', [1, 0]),
    ('LK', [1, 0]),
    ('KL', [1, 0]),
    ('SK', [1, 0]),
    ('KS', [1, 0]),
    ('LSS', [1, 0]),
    ('SLS', [2, 1, 0]),
    ('KLK', [2, 1, 0]),
  ]) {
    test('$path returns latest lookup first without forward history', () {
      final h = ReaderReturnHistory();
      for (var i = 0; i < path.length; i++) {
        h.forward(kind(path[i]), point(i), point(i + 1), h.version);
      }
      for (final expected in targets) {
        final entry = h.top!;
        expect(entry.origin.chapter.chapterId, '$expected');
        expect(h.consume(entry, h.version), isTrue);
      }
      expect(h.top, isNull);
    });
  }
  test(
    'ordinary reading preserves the real origin; only the top can merge',
    () {
      final h = ReaderReturnHistory();
      h.forward(kind('K'), point(0), point(1), h.version);
      // Reading from B to B-prime has no navigation commit.
      h.forward(kind('L'), point(2), point(3), h.version);
      expect(h.top!.origin.chapter.chapterId, '2');
      h.consume(h.top!, h.version);
      h.forward(kind('K'), point(2), point(4), h.version);
      expect(h.entries.length, 1);
      expect(h.top!.origin.chapter.chapterId, '0');
    },
  );
  test(
    'no movement preserves history; an explicit return still consumes once',
    () {
      final h = ReaderReturnHistory();
      h.forward(kind('S'), point(0), point(1), h.version);
      final entry = h.top!;
      h.forward(kind('K'), point(1), point(1), h.version);
      h.explicit(point(1), point(1), h.version);
      expect(h.top, same(entry));
      expect(h.consume(entry, h.version), isTrue);
      h.forward(kind('L'), point(0), point(1), h.version);
      h.explicit(point(1), point(2), h.version);
      expect(h.top, isNull);
    },
  );
  test('one eight-layer bound, stale tickets and exact top identity', () {
    final h = ReaderReturnHistory();
    for (var i = 0; i < 10; i++) {
      h.forward(kind('L'), point(i), point(i + 1), h.version);
    }
    expect(h.entries.length, 8);
    expect(h.entries.first.origin.chapter.chapterId, '2');
    final old = h.top!, ticket = h.version;
    h.forward(kind('S'), point(10), point(11), h.version);
    expect(h.consume(old, ticket), isFalse);
    expect(h.consume(old, h.version), isFalse);
    expect(h.forward(kind('K'), point(11), point(12), ticket), isFalse);
    expect(h.top!.kind, kind('S'));
  });
  test(
    'closing an auxiliary scope keeps earlier main history; retirement changes nothing',
    () {
      final h = ReaderReturnHistory(), child = Object();
      h.forward(kind('L'), point(0), point(1), h.version);
      h.forward(kind('L'), point(1), point(2, surface: child), h.version);
      h.forward(
        kind('L'),
        point(2, surface: child),
        point(3, surface: child),
        h.version,
      );
      h.closeScope(child, point(1), h.entries[1]);
      expect(h.entries.length, 1);
      expect(h.top!.origin.chapter.chapterId, '0');
    },
  );
}
