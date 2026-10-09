import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/local_chapter_progress.dart';
import 'package:shiori/domain/models/models.dart';
import 'reparse_position_test.dart' as fixture;

void main() {
  final book = fixture.book([
    List.generate(4, (i) => ParagraphBlock(text: 'A$i')),
    [
      ImageBlock(
        media: MediaRef(sourceId: fixture.key.sourceId, mediaId: 'I'),
      ),
    ],
    List.generate(8, (i) => ParagraphBlock(text: 'B$i')),
    List.generate(2, (i) => ParagraphBlock(text: 'C$i')),
  ]);
  final keys = book.chapters.map((c) => c.key).toList();
  LocalNavigationEntry nav(
    int chapter,
    String title, {
    int? block,
    List<LocalNavigationEntry> children = const [],
  }) => LocalNavigationEntry(
    title: title,
    chapterKey: keys[chapter],
    blockKey: block == null
        ? null
        : book.chapters[chapter].blocks[block].blockKey,
    children: children,
  );
  LocalChapterProgressIndex index(
    List<LocalNavigationEntry> entries, {
    BookProgressMetrics? metrics,
  }) => LocalChapterProgressIndex.build(
    metrics: metrics ?? book.progressMetrics,
    chapters: book.chapters,
    navigation: entries,
  )!;
  ReaderPosition anchor(int chapter, int block, {double fraction = 0}) =>
      fixture
          .progress(book, chapter: chapter, index: block, fraction: fraction)
          .position;

  test(
    'unequal body/image weights agree with book progress in both directions',
    () {
      final ix = index([nav(0, 'First'), nav(3, 'Second')]);
      final first = ix.sections.first;
      expect((first.start, first.end), (0, 13));
      expect(first.fraction(ix.coordinate(keys[0], 1)!), 4 / 13);
      expect(first.fraction(ix.coordinate(keys[1], 0)!), 4 / 13);
      expect(first.fraction(ix.coordinate(keys[1], 1)!), 5 / 13);
      expect(first.fraction(ix.coordinate(keys[2], 0)!), 5 / 13);
      for (final f in [0.0, 4 / 13, 4.5 / 13, 5 / 13, .8, 1.0]) {
        final target = ix.target(first, f);
        final physical = target.position.chapterFraction;
        final p = ix.coordinate(target.chapter, physical)!;
        expect(first.fraction(p), closeTo(f, 1e-12));
        expect(
          ix.bookFractionAt(first, f),
          closeTo(
            book.progressMetrics.at(target.chapter, physical)!.fraction,
            1e-12,
          ),
        );
      }
      expect(ix.target(first, 0).chapter, keys[0]);
      final end = ix.target(first, 1);
      expect(end.chapter, keys[2]);
      expect((end.position.blockIndex, end.position.blockFraction), (7, 1));
      expect(ix.sectionAt(keys[2], end.position), same(first));
      expect(ix.adjacent(first, 1), same(ix.sections.last));
      final bookEnd = ix.target(ix.sections.last, 1);
      expect(bookEnd.chapter, keys[3]);
      expect(
        (bookEnd.position.blockIndex, bookEnd.position.blockFraction),
        (1, 1),
      );
      expect(
        book.progressMetrics.at(bookEnd.chapter, 1)!.terminal,
        BookTerminalState.reading,
      );
    },
  );

  test('internal block targets, deepest same-position label and stable ties', () {
    final child = nav(0, 'Child', children: [nav(0, 'Deepest')]);
    final ix = index([
      nav(0, 'Volume', children: [child]),
      nav(0, 'Duplicate'),
      nav(0, 'Same title', block: 2),
      nav(2, 'Same title', block: 3),
    ]);
    expect(ix.sections.map((s) => (s.title, s.start, s.end)), [
      ('Deepest', 0, 2),
      ('Same title', 2, 8),
      ('Same title', 8, 15),
    ]);
    final section = ix.sectionAt(keys[0], anchor(0, 2))!;
    expect(section, same(ix.sections[1]));
    expect(ix.target(section, 0).position.blockIndex, 2);
    expect(ix.target(section, 1).position.blockIndex, 2);
    expect(ix.target(section, 1).chapter, keys[2]);
    // Display can reach a later boundary; anchor still owns the preceding section.
    expect(
      ix.sectionAt(keys[0], anchor(0, 1, fraction: 1)),
      same(ix.sections[0]),
    );
    expect(ix.sections[0].fraction(ix.coordinate(keys[0], 1)!), 1);
    final tie = index([nav(0, 'First'), nav(0, 'Later')]);
    expect(tie.sections.single.title, 'First');
    final blank = index([
      nav(0, '', children: [nav(0, 'Valid')]),
    ]);
    expect(blank.sections.single.reliable, isTrue);
  });

  test(
    'reading order wins over TOC order and preserves occurrence identities',
    () {
      final metrics = BookProgressMetrics(
        revision: 'r',
        order: [keys[2], keys[0], keys[1], keys[3]],
        weights: [8, 4, 1, 2],
      );
      final ix = index([
        nav(3, 'Last'),
        nav(0, 'A'),
        nav(2, 'B'),
      ], metrics: metrics);
      expect(ix.sections.map((s) => (s.title, s.start)), [
        ('B', 0),
        ('A', 8),
        ('Last', 13),
      ]);
      final occurrence = LocalBookIdentity.epubOccurrence(
        fixture.key,
        'same.xhtml',
        1,
      );
      final original = LocalBookIdentity.epubOccurrence(
        fixture.key,
        'same.xhtml',
        0,
      );
      final copies = [
        for (final key in [original, occurrence])
          ChapterContent(
            key: key,
            title: 'Repeat',
            blocks: [ParagraphBlock(text: 'Same source')],
          ),
      ];
      final repeats = LocalChapterProgressIndex.build(
        metrics: BookProgressMetrics(
          revision: 'r',
          order: [original, occurrence],
          weights: [1, 1],
        ),
        chapters: copies,
        navigation: [
          for (final key in [original, occurrence])
            LocalNavigationEntry(title: 'Repeat', chapterKey: key),
        ],
      )!;
      expect(repeats.sections, hasLength(2));
      expect(repeats.target(repeats.sections.last, 0).chapter, occurrence);
    },
  );

  test(
    'unassigned prefix, auxiliary targets and unknown boundaries fall back locally',
    () {
      final aux = LocalNavigationEntry(
        title: 'Aux',
        chapterKey: LocalBookIdentity.chapter(fixture.key, 'aux'),
      );
      final ix = index([aux, nav(1, 'Starts at image'), nav(3, 'Last')]);
      expect(ix.sectionAt(keys[0], anchor(0, 3)), isNull);
      expect(ix.sections.map((s) => s.start), [4, 13]);
      expect(index([]).sections, isEmpty);
      expect(index([aux]).sections, isEmpty);
      final missing = LocalNavigationEntry(
        title: 'Missing block',
        chapterKey: keys[2],
        blockKey: 'absent',
      );
      final broken = index([nav(0, 'First'), missing, nav(3, 'Last')]);
      expect(broken.sectionAt(keys[0], anchor(0, 0)), isNull);
      expect(broken.sectionAt(keys[3], anchor(3, 0))!.title, 'Last');
      expect(broken.adjacent(broken.sections.last, -1), isNull);
      expect(
        () => broken.target(broken.sections.first, .5),
        throwsArgumentError,
      );
      expect(
        LocalChapterProgressIndex.build(
          metrics: book.progressMetrics,
          chapters: book.chapters.take(3),
          navigation: [],
        ),
        isNull,
      );
      expect(
        LocalChapterProgressIndex.build(
          metrics: BookProgressMetrics(
            revision: 'r',
            order: keys,
            weights: [1, 1, 1, 1],
          ),
          chapters: book.chapters,
          navigation: [],
        ),
        isNull,
      );
      expect(
        ix.sectionAt(keys[1], anchor(0, 0)),
        isNull,
        reason: 'revision/block identity mismatch',
      );
    },
  );
}
