import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/reparse_position.dart';
import 'reparse_position_test.dart' as f;

void main() {
  test('synthetic parser changes classify and preserve checked anchors', () {
    final single = f.book([
      [f.p('unique semantic anchor')],
    ]);
    final indent = f.book([
      [f.p('unique semantic anchor', indent: 2)],
    ]);
    final rubyOld = f.book([
      [f.p('明神（Akegami）来到这里。')],
    ]);
    final rubyNew = f.book([
      [
        ParagraphBlock(
          text: '明神来到这里。',
          inlineRuby: [InlineRuby(start: 0, length: 2, annotation: 'Akegami')],
        ),
      ],
    ]);
    final repeat = f.book([
      [f.p('same'), f.p('same')],
    ]);
    final repeated = f.book([
      [f.p('same'), f.p('same'), f.p('same')],
    ]);
    final long = 'a sufficiently long unique paragraph for a split or merge';
    final unsplit = f.book([
      [f.p(long)],
    ]);
    final split = f.book([
      [f.p(long.substring(0, 20)), f.p(long.substring(20))],
    ]);
    final image = ImageBlock(
      media: MediaRef(sourceId: f.key.sourceId, mediaId: 'image'),
    );
    final imageOld = f.book([
      [image, f.p('after')],
    ]);
    final imageNew = f.book([
      [f.p('before'), image, f.p('after')],
    ]);
    final chapters = f.book([
      [f.p('unique semantic anchor')],
      [f.p('second')],
    ]);
    final reordered = f.book(
      [
        [f.p('second')],
        [f.p('unique semantic anchor')],
      ],
      ids: ['1', '0'],
    );
    final changedIds = f.book(
      [
        [f.p('unique semantic anchor')],
      ],
      ids: ['new-boundary'],
    );
    final removed = f.book(
      [
        [f.p('lost chapter')],
      ],
      ids: ['removed'],
    );
    final cases =
        <(String, LocalBookContent, LocalBookContent, ReadingProgress?, bool)>[
          ('epub', single, indent, f.progress(single), false),
          ('epub', rubyOld, rubyNew, f.progress(rubyOld, fraction: 0), false),
          (
            'epub',
            rubyOld,
            rubyNew,
            f.progress(rubyOld, fraction: 5 / 16),
            true,
          ),
          ('epub', repeat, repeated, f.progress(repeat), true),
          ('epub', imageOld, imageNew, f.progress(imageOld), false),
          ('epub', chapters, reordered, f.progress(chapters), false),
          ('epub', single, changedIds, f.progress(single), false),
          ('epub', removed, single, f.progress(removed), true),
          ('txt', single, indent, f.progress(single), false),
          ('txt', single, changedIds, f.progress(single), false),
          ('txt', unsplit, split, f.progress(unsplit), true),
          ('txt', split, unsplit, f.progress(split, index: 1), true),
          ('txt', repeat, repeated, f.progress(repeat), true),
          ('epub', single, indent, null, false),
          ('txt', unsplit, split, null, false),
        ];
    final counts = <String, List<int>>{
      'epub': [0, 0, 0],
      'txt': [0, 0, 0],
    };
    for (final (format, old, next, saved, approximate) in cases) {
      final result = migrateLocalPosition(old, next, saved);
      expect(result.approximate, approximate);
      if (saved == null) {
        expect(result.progress, isNull);
        counts[format]![2]++;
        continue;
      }
      counts[format]![result.approximate ? 1 : 0]++;
      expect(result.progress!.lastReadAt, saved.lastReadAt);
      if (!result.approximate) {
        final before = old.chapters
            .firstWhere((c) => c.key == saved.chapterKey)
            .blocks[saved.position.blockIndex];
        final after = next.chapters
            .firstWhere((c) => c.key == result.progress!.chapterKey)
            .blocks[result.progress!.position.blockIndex];
        if (before is ImageBlock) {
          expect((after as ImageBlock).media, before.media);
        } else if (before.inlineRuby.isEmpty && after.inlineRuby.isEmpty) {
          expect(
            (after as ParagraphBlock).text,
            (before as ParagraphBlock).text,
          );
          expect(
            result.progress!.position.blockFraction,
            saved.position.blockFraction,
          );
        } else {
          expect(result.progress!.position.blockFraction, 0);
          expect((after as ParagraphBlock).text, startsWith('明神'));
        }
      }
    }
    // Synthetic pairs only: no archived version-labelled corpus is available.
    // ignore: avoid_print
    print(
      'Migration survey: $counts (exact, approximate, no-history); failures=0; synthetic changes, no measured version range',
    );
  });
}
