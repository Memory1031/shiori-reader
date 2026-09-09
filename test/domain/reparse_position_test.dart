import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/reparse_position.dart';

final key = LocalBookIdentity.book('a' * 64);
LocalBookContent book(List<List<ContentBlock>> blocks, {List<String>? ids}) {
  final chapters = [
    for (var i = 0; i < blocks.length; i++)
      ChapterContent(
        key: LocalBookIdentity.chapter(key, ids?[i] ?? '$i'),
        title: 'Chapter $i',
        blocks: blocks[i],
      ),
  ];
  return LocalBookContent(
    detail: NovelDetail(
      summary: NovelSummary(key: key, title: 'Book'),
    ),
    chapters: chapters,
    catalog: Catalog(
      novelKey: key,
      volumes: [
        Volume(
          groupId: 'v',
          chapters: [
            for (var i = 0; i < chapters.length; i++)
              Chapter(
                key: chapters[i].key,
                title: chapters[i].title,
                ordinal: i,
                volumeGroupId: 'v',
              ),
          ],
        ),
      ],
    ),
  );
}

ReadingProgress progress(
  LocalBookContent b, {
  int chapter = 0,
  int index = 0,
  double fraction = .5,
}) {
  final c = b.chapters[chapter];
  return ReadingProgress(
    snapshot: b.detail.summary,
    chapterKey: c.key,
    chapterOrdinalSnapshot: chapter,
    catalogRevision: b.catalog.revision,
    position: ReaderPosition(
      contentRevision: c.contentRevision,
      blockKey: c.blocks[index].blockKey,
      blockIndex: index,
      blockFraction: fraction,
      chapterFraction: ReaderPosition.fractionFor(
        blockIndex: index,
        blockFraction: fraction,
        blockCount: c.blocks.length,
      ),
      pixelOffset: 30,
      layoutKey: 'old',
    ),
    completed: true,
    lastReadAt: DateTime.utc(2025),
  );
}

ParagraphBlock p(String s, {int indent = 0}) =>
    ParagraphBlock(text: s, leadingIndent: indent);
void main() {
  test('no history is not created; unchanged position loses layout hints', () {
    final b = book([
      [p('abc')],
    ]);
    expect(migrateLocalPosition(b, b, null).progress, isNull);
    final r = migrateLocalPosition(b, b, progress(b));
    expect(r.approximate, isFalse);
    expect(r.progress!.position.pixelOffset, isNull);
    expect(r.progress!.lastReadAt, DateTime.utc(2025));
  });
  test('indent changes retain unique semantic position', () {
    final a = book([
          [p('abc')],
        ]),
        b = book([
          [p('abc', indent: 2)],
        ]);
    final r = migrateLocalPosition(a, b, progress(a));
    expect(r.approximate, isFalse);
    expect(r.progress!.position.blockFraction, .5);
  });
  test('split supplementary text maps Unicode offset', () {
    final s = '天地𠮷😀玄黄宇宙洪荒日月盈昃辰宿列张';
    final a = book([
          [p(s)],
        ]),
        b = book([
          [
            p(String.fromCharCodes(s.runes.take(8))),
            p(String.fromCharCodes(s.runes.skip(8))),
          ],
        ]);
    final r = migrateLocalPosition(a, b, progress(a, fraction: .75));
    expect(r.approximate, isTrue);
    expect(r.progress!.position.blockIndex, 1);
    expect(r.progress!.completed, isFalse);
  });
  test('merge paragraphs maps local context', () {
    final a = book([
      [p('Before '), p('a sufficiently long paragraph to locate uniquely')],
    ]);
    final b = book([
      [p('Before a sufficiently long paragraph to locate uniquely')],
    ]);
    final r = migrateLocalPosition(a, b, progress(a, index: 1));
    expect(r.progress!.position.blockIndex, 0);
    expect(r.approximate, isTrue);
  });
  test('ambiguous repeated text degrades instead of trusting occurrence', () {
    final a = book([
          [p('same'), p('same')],
        ]),
        b = book([
          [p('same'), p('same'), p('same')],
        ]);
    expect(migrateLocalPosition(a, b, progress(a)).approximate, isTrue);
  });
  test(
    'removed chapter uses nearest readable start without clearing history',
    () {
      final a = book([
            [p('lost')],
            [p('other')],
          ]),
          b = book(
            [
              [p('new')],
            ],
            ids: ['new'],
          );
      final r = migrateLocalPosition(a, b, progress(a, chapter: 1));
      expect(r.approximate, isTrue);
      expect(r.progress!.position.blockFraction, 0);
    },
  );
  test('image identity survives inserted paragraph', () {
    final image = ImageBlock(
      media: MediaRef(sourceId: key.sourceId, mediaId: 'image'),
    );
    final a = book([
          [image, p('after')],
        ]),
        b = book([
          [p('before'), image, p('after')],
        ]);
    final r = migrateLocalPosition(a, b, progress(a));
    expect(r.approximate, isFalse);
    expect(r.progress!.position.blockIndex, 1);
  });
  test('mismatched old revision must not invent exact recovery', () {
    final a = book([
          [p('old')],
        ]),
        b = book([
          [p('changed')],
        ]),
        different = book([
          [p('different')],
        ]);
    expect(migrateLocalPosition(a, b, progress(different)).approximate, isTrue);
  });
}
