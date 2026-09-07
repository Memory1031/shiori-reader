import 'package:characters/characters.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import 'package:test/test.dart';

void main() {
  test(
    'transient chunks preserve graphemes, original text and semantic offsets',
    () {
      final text = List.filled(30, '汉字e\u0301👩‍👩‍👧‍👦😀かな。').join();
      final chapter = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.typography),
        title: 'Unicode fixture',
        blocks: [ParagraphBlock(text: text)],
      );
      final original = chapter.toJson();
      final index = ChunkIndex(chapter, maxCodePoints: 32);
      expect(index.chunks.map((c) => c.text).join(), text);
      final boundaries = <int>{0};
      var offset = 0;
      for (final grapheme in text.characters) {
        offset += grapheme.runes.length;
        boundaries.add(offset);
      }
      for (final chunk in index.chunks) {
        expect(boundaries, contains(chunk.start));
        expect(boundaries, contains(chunk.end));
        expect(chunk.end - chunk.start, chunk.text!.runes.length);
        expect(chunk.blockKey, chapter.blocks.single.blockKey);
      }
      expect(chapter.toJson(), original);
    },
  );

  test('rechunking resolves the same full-paragraph code-point anchor', () {
    final chapter = const FixtureData().content(
      FixtureScenario.extremeParagraph,
    );
    final a = ChunkIndex(chapter, maxCodePoints: 800);
    final b = ChunkIndex(chapter, maxCodePoints: 256);
    final position = a.position(0, .753);
    for (final index in [a, b]) {
      final resolved = index.resolve(position);
      final chunk = index.chunks[resolved.chunk];
      expect(chunk.start, lessThanOrEqualTo(75300));
      expect(chunk.end, greaterThan(75300));
      expect(index.position(resolved.chunk, resolved.fraction), position);
    }
    expect(a.chunks.length, isNot(b.chunks.length));
  });

  test(
    'changed content matches stable keys then diagnoses coarse fallback',
    () {
      final chapter = const FixtureData().content(FixtureScenario.shortChapter);
      final old = ChunkIndex(chapter).position(3, .5);
      final revised = const FixtureData().content(
        FixtureScenario.shortChapter,
        revision: 1,
      );
      final next = ChunkIndex(revised);
      final matched = next.resolve(old);
      expect(matched.usedFallback, isFalse);
      expect(next.chunks[matched.chunk].blockIndex, 4);
      final missing = ReaderPosition(
        contentRevision: old.contentRevision,
        blockKey: 'missing',
        blockIndex: old.blockIndex,
        blockFraction: old.blockFraction,
        chapterFraction: old.chapterFraction,
      );
      expect(next.resolve(missing).usedFallback, isTrue);
      expect(next.resolve(null).chunk, 0);
      expect(() => ChunkIndex(chapter, maxCodePoints: 0), throwsArgumentError);
    },
  );
}
