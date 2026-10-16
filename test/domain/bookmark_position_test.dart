import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/bookmark_position.dart';
import 'package:shiori/domain/models/models.dart';
import 'reparse_position_test.dart' as f;

UserBookmark mark(ChapterContent c, int index, {double fraction = .5}) {
  final p = ReaderPosition(
    contentRevision: c.contentRevision,
    blockKey: c.blocks[index].blockKey,
    blockIndex: index,
    blockFraction: fraction,
    chapterFraction: ReaderPosition.fractionFor(
      blockIndex: index,
      blockFraction: fraction,
      blockCount: c.blocks.length,
    ),
  );
  return UserBookmark(
    id: '${c.key.chapterId}:$index',
    chapter: c.key,
    anchor: BookmarkPositionIndex([c]).capture(c.key, p)!,
    chapterTitle: c.title,
    createdAt: DateTime.utc(2026),
  );
}

void main() {
  test('exact anchors ignore pixel hints and round trip bounded context', () {
    final c = f
        .book([
          [f.p('A sufficiently long stable semantic paragraph.')],
        ])
        .chapters
        .single;
    final b = mark(c, 0);
    final a = BookmarkAnchor.fromJson(
      jsonDecode(jsonEncode(b.anchor.toJson())) as Map<String, dynamic>,
    );
    final r = BookmarkPositionIndex([c]).resolve(c.key, a);
    expect(r.location, BookmarkLocation.exact);
    expect(r.anchor!.position, b.anchor.position);
    expect(r.anchor!.quote.runes.length, lessThanOrEqualTo(64));
    expect(r.anchor!.position.pixelOffset, isNull);
    final image = ChapterContent(
      key: c.key,
      title: 'Image',
      blocks: [
        ImageBlock(
          media: MediaRef(sourceId: c.key.novelKey.sourceId, mediaId: 'image'),
        ),
      ],
    );
    final end = ReaderPosition(
      contentRevision: image.contentRevision,
      blockKey: image.blocks.first.blockKey,
      blockIndex: 0,
      blockFraction: 1,
      chapterFraction: 1,
    );
    expect(
      BookmarkPositionIndex([image]).capture(image.key, end)!.position,
      end,
    );
  });
  test('revision change cannot trust occurrence after duplicate insertion', () {
    final old = f.book([
      [
        f.p('same paragraph with sufficiently long repeated contents'),
        f.p('same paragraph with sufficiently long repeated contents'),
      ],
    ]);
    final next = f.book([
      [
        f.p('same paragraph with sufficiently long repeated contents'),
        ...old.chapters.single.blocks,
      ],
    ]);
    final b = mark(old.chapters.single, 1);
    expect(
      BookmarkPositionIndex(next.chapters)
          .resolve(
            b.chapter,
            b.anchor,
            old: BookmarkPositionIndex(old.chapters),
          )
          .located,
      isFalse,
    );
  });
  test(
    'unique exact context migrates split, merge, move and chapter reorder',
    () {
      const text = '天地玄黄宇宙洪荒日月盈昃辰宿列张寒来暑往秋收冬藏闰余成岁律吕调阳云腾致雨露结为霜金生丽水玉出昆冈';
      final old = f.book([
        [f.p(text)],
        [f.p('Other chapter')],
      ]);
      final b = mark(old.chapters.first, 0);
      for (final next in [
        f.book([
          [f.p(text.substring(0, 20)), f.p(text.substring(20))],
          [f.p('Other chapter')],
        ]),
        f.book([
          [f.p('prefix$text')],
          [f.p('Other chapter')],
        ]),
        f.book(
          [
            [f.p('Other chapter')],
            [f.p(text)],
          ],
          ids: ['1', '0'],
        ),
        f.book(
          [
            [f.p(text)],
          ],
          ids: ['moved'],
        ),
      ]) {
        final migrated = migrateBookmarks(old.chapters, next.chapters, [
          b,
        ]).single;
        expect(migrated.location, BookmarkLocation.migrated);
        expect(migrated.anchor.quote, contains(text.substring(20, 30)));
        expect(migrated.id, b.id);
      }
    },
  );
  test(
    'missing, ambiguous and short changed targets retain their original anchor',
    () {
      final old = f.book([
            [f.p('short')],
          ]),
          b = mark(
            f
                .book([
                  [f.p('short')],
                ])
                .chapters
                .single,
            0,
          );
      for (final next in [
        f.book([
          [f.p('different')],
        ]),
        f.book([
          [f.p('short'), f.p('short')],
        ]),
        f.book(
          [
            [f.p('deleted')],
          ],
          ids: ['new'],
        ),
      ]) {
        final migrated = migrateBookmarks(old.chapters, next.chapters, [
          b,
        ]).single;
        expect(migrated.located, isFalse);
        expect(migrated.anchor, same(b.anchor));
      }
    },
  );
  for (final count in [20, 100]) {
    test(
      'batch $count positions shares snapshots and measures actual matching',
      () {
        final before = f.book([
          for (var chapter = 0; chapter < 8; chapter++)
            [
              for (var i = 0; i < 1000; i++)
                f.p(
                  'Chapter $chapter paragraph $i unique context. ${'Some stable prose. ' * 8}',
                ),
            ],
        ]);
        final after = f.book([
          for (final c in before.chapters)
            [f.p('Inserted opening paragraph.'), ...c.blocks],
        ]);
        final indexes = {
          for (final c in before.chapters) c.key: BookmarkPositionIndex([c]),
        };
        final bookmarks = <UserBookmark>[];
        for (var n = 0; n < count; n++) {
          final c = before.chapters[n % 8], i = 100 + (n * 7) % 800;
          final p = f
              .progress(before, chapter: n % 8, index: i, fraction: .08)
              .position;
          bookmarks.add(
            UserBookmark(
              id: '$n',
              chapter: c.key,
              anchor: indexes[c.key]!.capture(c.key, p)!,
              chapterTitle: c.title,
              createdAt: DateTime.utc(2026),
            ),
          );
        }
        final watch = Stopwatch()..start();
        final result = migrateBookmarks(
          before.chapters,
          after.chapters,
          bookmarks,
        );
        watch.stop();
        expect(
          result.every((b) => b.location == BookmarkLocation.migrated),
          isTrue,
        );
        expect(result.map((b) => b.id), bookmarks.map((b) => b.id));
        // No text or snapshot content enters performance output.
        // ignore: avoid_print
        print(
          'BOOKMARK_BATCH ${jsonEncode({'positions': count, 'chapters': 8, 'blocks': 8000, 'codePoints': before.chapters.expand((c) => c.blocks).fold<int>(0, (n, b) => n + (b as ParagraphBlock).text.runes.length), 'migrationUs': watch.elapsedMicroseconds})}',
        );
      },
    );
  }
}
