import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/page_boundaries.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

const style = TextStyle(
  inherit: false,
  fontFamily: 'Ahem',
  fontSize: 20,
  height: 1,
);
ChapterContent chapter(List<ContentBlock> blocks) => ChapterContent(
  key: ChapterKey(
    novelKey: NovelKey(sourceId: SourceId('local'), novelId: 'indent'),
    chapterId: '1',
  ),
  title: 'Indent',
  blocks: blocks,
);
double naturalWidth(String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

PageLayout layout(ChapterContent content, double width, {double height = 20}) =>
    PageLayout(
      index: ChunkIndex(content),
      width: width,
      height: height,
      style: style,
      scaler: TextScaler.noScaling,
      direction: TextDirection.ltr,
      paragraphSpacing: 0,
    );
void sourceSlices(PageLayout owner, ReaderPage page) {
  for (final fragment in page.fragments) {
    final chunk = owner.index.chunks[fragment.unit];
    final block =
        owner.index.content.blocks[chunk.blockIndex] as ParagraphBlock;
    final boundaries = <int>{0};
    var offset = 0;
    for (final cluster in block.text.characters) {
      offset += cluster.runes.length;
      boundaries.add(offset);
    }
    expect(boundaries, contains(chunk.start + fragment.start));
    expect(boundaries, contains(chunk.start + fragment.end));
    expect(
      fragment.text,
      String.fromCharCodes(
        block.text.runes
            .skip(chunk.start + fragment.start)
            .take(fragment.end - fragment.start),
      ),
    );
  }
}

void main() {
  for (final (name, text) in [
    ('punctuation', '「${'…' * 16}」'),
    ('combining', '「${'e\u0301' * 16}」'),
    ('emoji', '「👩‍👩‍👧‍👦${'…' * 16}」'),
  ]) {
    testWidgets('$name actually removes a prefix-only first row', (
      tester,
    ) async {
      final width = naturalWidth(text) + 40 - .05;
      final old = TextPainter(
        text: TextSpan(text: '\u2003\u2003$text', style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      expect(
        old.getLineBoundary(const TextPosition(offset: 0)).end,
        2,
        reason: 'This fixture must actually trigger the new branch',
      );
      old.dispose();
      final content = chapter([ParagraphBlock(text: text, leadingIndent: 2)]);
      final owner = layout(content, width);
      final boundaries = PageBoundaries(owner);
      final first = boundaries.forward(const PageCursor(0, 0));
      expect(first, isNotNull);
      sourceSlices(owner, first!);
      expect(first.fragments.first.flow, isNotNull);
      expect(
        first.fragments.first.flow!.lines.first.pieces.first.rect.left,
        40,
      );
      final rendered = first.fragments.first.text!;
      expect(rendered.trim(), isNotEmpty);
      expect(rendered, isNot(text));
      final second = boundaries.forward(first.end)!;
      sourceSlices(owner, second);
      expect('$rendered${second.fragments.map((f) => f.text).join()}', text);
      expect(second.fragments.last.text, isNot('」'));
      final warm = boundaries.backward(second.end)!;
      expect(PageBoundaries.compare(warm.start, second.start), 0);
      final coldOwner = layout(content, width);
      final cold = coldOwner.backward(second.end)!;
      sourceSlices(coldOwner, cold);
      expect(PageBoundaries.compare(cold.start, second.start), 0);
    });
  }

  testWidgets(
    'chapter start and ordinary cold reverse do not preflight a chapter',
    (tester) async {
      final content = chapter([
        for (var i = 0; i < 503; i++)
          ParagraphBlock(text: 'Ordinary $i', leadingIndent: 2),
      ]);
      final owner = layout(content, 400, height: 100);
      expect(owner.backward(const PageCursor(0, 0)), isNull);
      expect(owner.measuredChunks, 0);
      expect(owner.indentAttempts, 0);
      final end = PageCursor(owner.index.chunks.length, 0);
      final page = owner.backward(end)!;
      sourceSlices(owner, page);
      expect(owner.measuredChunks, lessThan(10));
      expect(owner.indentAttempts, 0);
      expect(owner.indentMeasurements, 0);
    },
  );

  testWidgets(
    'more than the flow capacity remains local on repeated cold-page reverse',
    (tester) async {
      final text = '「${'…' * 16}」';
      final content = chapter([
        for (var i = 0; i < 300; i++)
          ParagraphBlock(text: text, leadingIndent: 2),
      ]);
      final owner = layout(content, naturalWidth(text) + 40 - .05, height: 40);
      final boundaries = PageBoundaries(owner);
      var cursor = const PageCursor(0, 0);
      final pages = <ReaderPage>[];
      while (true) {
        final page = boundaries.forward(cursor);
        if (page == null) break;
        sourceSlices(owner, page);
        pages.add(page);
        cursor = page.end;
      }
      expect(owner.indentAttempts, 300);
      expect(owner.cachedIndentFlows, lessThanOrEqualTo(32));
      final before = owner.measuredChunks;
      sourceSlices(owner, owner.backward(cursor)!);
      expect(owner.measuredChunks - before, lessThan(4));
      // Deliberately revisit an evicted first flow, then the tail. Neither
      // operation walks decisions in source order or scans the other paragraphs.
      final attempts = owner.indentAttempts;
      final first = owner.forward(const PageCursor(0, 0))!;
      sourceSlices(owner, first);
      expect(owner.indentAttempts, attempts + 1);
      sourceSlices(owner, owner.backward(cursor)!);
      expect(owner.indentAttempts, attempts + 1);
      for (final expected in pages.reversed) {
        final rebuilt = boundaries.backward(expected.end)!;
        sourceSlices(owner, rebuilt);
        expect(PageBoundaries.compare(rebuilt.start, expected.start), 0);
      }
      expect(owner.cachedIndentFlows, lessThanOrEqualTo(32));
    },
  );

  testWidgets(
    'candidate exhaustion is remembered without repeated failed layout',
    (tester) async {
      final text = '「${'…' * 10}${'」' * 16}';
      final owner = layout(
        chapter([ParagraphBlock(text: text, leadingIndent: 2)]),
        naturalWidth(text) + 40 - .05,
        height: 200,
      );
      final first = owner.forward(const PageCursor(0, 0))!;
      expect(owner.indentAttempts, 1);
      expect(first.fragments.first.flow, isNull);
      final work = owner.indentMeasurements;
      for (var n = 0; n < 3; n++) {
        sourceSlices(owner, owner.forward(const PageCursor(0, 0))!);
        sourceSlices(owner, owner.backward(first.end)!);
      }
      expect(owner.indentAttempts, 1);
      expect(owner.indentMeasurements, work);
    },
  );

  testWidgets(
    'an indivisible grapheme wider than the inset uses the ordinary fallback',
    (tester) async {
      const text = '👩‍👩‍👧‍👦';
      final owner = layout(
        chapter([ParagraphBlock(text: text, leadingIndent: 2)]),
        naturalWidth(text) + 40 - .05,
        height: 200,
      );
      final page = owner.forward(const PageCursor(0, 0))!;
      sourceSlices(owner, page);
      expect(owner.indentAttempts, 1);
      expect(page.fragments.first.flow, isNull);
      expect(page.fragments.first.text, text);
    },
  );

  testWidgets('a line budget limits calculation as well as retained flow', (
    tester,
  ) async {
    final text = '「…」 ${'word ' * 200}';
    final owner = layout(
      chapter([ParagraphBlock(text: text, leadingIndent: 2)]),
      naturalWidth('「…」') + 40 - .05,
      height: 200,
    );
    final first = owner.forward(const PageCursor(0, 0))!;
    sourceSlices(owner, first);
    expect(owner.indentAttempts, 1);
    expect(first.fragments.first.flow, isNull);
    expect(owner.indentMeasurements, lessThanOrEqualTo(1 + 64 * 11));
    final work = owner.indentMeasurements;
    owner.forward(const PageCursor(0, 0));
    expect(owner.indentMeasurements, work);
    expect(owner.cachedIndentFlows, 0);
  });

  testWidgets('authored whitespace retains the ordinary path', (tester) async {
    final text = '「${'…' * 16}」';
    for (final source in [
      '\u2003\u2003$text',
      '$text\n\nTail',
      '$text\u00a0Tail',
      '$text\u202fTail',
      '$text\u2060Tail',
    ]) {
      final block = ParagraphBlock(text: source, leadingIndent: 2);
      final owner = layout(chapter([block]), 400, height: 400);
      final page = owner.forward(const PageCursor(0, 0))!;
      sourceSlices(owner, page);
      expect(page.fragments.map((f) => f.text).join(), block.text);
      expect(owner.indentAttempts, 0);
    }
  });

  testWidgets(
    'triggered long text crosses pages and chunks without changing source',
    (tester) async {
      final text = '「${'…' * 16}」 ${'longtext ' * 400}';
      final content = chapter([ParagraphBlock(text: text, leadingIndent: 2)]);
      final width = naturalWidth('「${'…' * 16}」') + 40 - .05;
      for (final columns in [1, 2]) {
        PageLayout create() => PageLayout(
          index: ChunkIndex(content),
          width: width,
          height: 40,
          columns: columns,
          style: style,
          scaler: TextScaler.noScaling,
          direction: TextDirection.ltr,
          paragraphSpacing: 0,
        );
        final owner = create();
        final bounds = PageBoundaries(owner);
        final textOut = StringBuffer();
        final pages = <ReaderPage>[];
        var cursor = const PageCursor(0, 0);
        while (true) {
          final page = bounds.forward(cursor);
          if (page == null) break;
          expect(PageBoundaries.compare(page.end, cursor), greaterThan(0));
          sourceSlices(owner, page);
          textOut.write(page.fragments.map((f) => f.text).join());
          pages.add(page);
          cursor = page.end;
        }
        expect(textOut.toString(), text);
        expect(owner.index.chunks.length, greaterThan(2));
        expect(pages.length, greaterThan(3));
        expect(owner.indentAttempts, 1);
        expect(pages.first.fragments.first.flow, isNotNull);
        for (final (number, expected) in pages.reversed.indexed) {
          final warm = bounds.backward(expected.end)!;
          sourceSlices(owner, warm);
          expect(PageBoundaries.compare(warm.start, expected.start), 0);
          if (number % 7 == 0 || number == pages.length - 1) {
            final coldOwner = create();
            final cold = coldOwner.backward(expected.end)!;
            sourceSlices(coldOwner, cold);
          }
        }
      }
    },
  );
}
