import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/reparse_position.dart';
import 'reparse_position_test.dart' as fixture;

void main() {
  final local = fixture.book([
    List.generate(10, (i) => ParagraphBlock(text: 'a$i')),
    List.generate(100, (i) => ParagraphBlock(text: 'b$i')),
    List.generate(40, (i) => ParagraphBlock(text: 'c$i')),
  ]);
  test('local block weights, main order and layout-independent snapshots', () {
    final m = local.progressMetrics;
    final keys = local.chapters.map((c) => c.key).toList();
    expect(m.at(keys[0], 0)!.fraction, 0);
    expect(m.at(keys[0], 1)!.fraction, closeTo(10 / 150, 1e-9));
    expect(m.at(keys[1], .5)!.fraction, .4);
    expect(m.at(keys[2], 1)!.fraction, 1);
    final reordered = LocalBookContent(
      detail: local.detail,
      catalog: local.catalog,
      chapters: local.chapters,
      readingOrder: [keys[2], keys[1]],
      auxiliaryChapters: [local.chapters[0]],
    );
    expect(reordered.progressMetrics.at(keys[0], 1), isNull);
    expect(reordered.progressMetrics.at(keys[1], .5)!.fraction, 90 / 140);
    expect(reordered.progressMetrics.order, [keys[2], keys[1]]);
  });
  test(
    'images have a single block weight and no presentation double count',
    () {
      final image = ImageBlock(
        media: MediaRef(sourceId: fixture.key.sourceId, mediaId: 'picture'),
      );
      final b = fixture.book([
        [image],
        [ParagraphBlock(text: 'Text')],
      ]);
      expect(b.progressMetrics.at(b.chapters.first.key, 1)!.fraction, .5);
    },
  );
  test('online equal chapter approximation changes when catalog grows', () {
    final m = BookProgressMetrics.online(local.catalog);
    final keys = local.chapters.map((c) => c.key).toList();
    expect(m.at(keys[0], 0)!.fraction, 0);
    expect(m.at(keys[0], .5)!.fraction, 1 / 6);
    expect(m.at(keys[1], .5)!.fraction, .5);
    expect(m.at(keys[2], .5)!.fraction, 5 / 6);
    expect(m.at(keys[2], 1)!.fraction, 1);
    final grown = fixture.book([
      ...local.chapters.map((c) => c.blocks),
      [ParagraphBlock(text: 'New')],
    ]);
    expect(
      BookProgressMetrics.online(grown.catalog).at(keys.last, 1)!.fraction,
      .75,
    );
  });
  test(
    'unknown or invalid totals are safe and snapshot ranges are validated',
    () {
      final key = local.chapters.first.key;
      final empty = BookProgressMetrics(
        revision: 'empty',
        order: [],
        weights: [],
      );
      expect(empty.at(key, .5), isNull);
      expect(
        () => BookProgressMetrics(revision: 'bad', order: [key], weights: [0]),
        throwsArgumentError,
      );
      expect(
        () => BookProgressSnapshot(fraction: double.nan, chapterCount: 1),
        throwsArgumentError,
      );
      expect(
        () => BookProgressSnapshot(
          fraction: .4,
          chapterCount: 1,
          terminal: BookTerminalState.finished,
        ),
        throwsArgumentError,
      );
      final snapshot = BookProgressSnapshot(
        fraction: 1,
        chapterCount: 3,
        terminal: BookTerminalState.caughtUp,
      );
      expect(BookProgressSnapshot.fromJson(snapshot.toJson()), snapshot);
    },
  );
  test('reparse recalculates weight from the migrated position', () {
    final saved = fixture.progress(local, chapter: 1, index: 49, fraction: 1);
    final next = fixture.book([
      List.generate(60, (i) => ParagraphBlock(text: 'new$i')),
      local.chapters[1].blocks,
      local.chapters[2].blocks,
    ]);
    final migrated = migrateLocalPosition(local, next, saved);
    expect(migrated.approximate, isFalse);
    expect(migrated.progress!.bookProgress!.fraction, .55);
    expect(migrated.progress!.position.chapterFraction, .5);
  });
  test('only reliable completed titles imply finished', () {
    for (final status in NovelStatus.values) {
      expect(
        bookEndState(local: true, status: status),
        BookTerminalState.finished,
      );
    }
    expect(
      bookEndState(local: false, status: NovelStatus.completed),
      BookTerminalState.finished,
    );
    expect(
      bookEndState(local: false, status: NovelStatus.ongoing),
      BookTerminalState.caughtUp,
    );
    expect(
      bookEndState(local: false, status: NovelStatus.hiatus),
      BookTerminalState.currentEnd,
    );
    expect(
      bookEndState(local: false, status: NovelStatus.unknown),
      BookTerminalState.currentEnd,
    );
  });
}
