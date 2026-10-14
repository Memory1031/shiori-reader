import 'article_heading.dart';
import '../../domain/models/models.dart';

/// Navigation projection only: never rewrite source text, block keys or offsets.
List<({String title, ReaderPosition position})> articleContents(
  ChapterContent content,
) {
  final result = <({String title, ReaderPosition position})>[];
  for (var i = 0; i < content.blocks.length; i++) {
    final block = content.blocks[i];
    final text = switch (block) {
      HeadingBlock(:final text) => text.trim(),
      ParagraphBlock(:final text) => text.trim(),
      _ => '',
    };
    if (text.isEmpty) continue;
    final recognised = block is HeadingBlock || isArticleHeading(text);
    if (!recognised) continue;
    result.add((
      title: text,
      position: ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: block.blockKey,
        blockIndex: i,
        blockFraction: 0,
        chapterFraction: ReaderPosition.fractionFor(
          blockIndex: i,
          blockFraction: 0,
          blockCount: content.blocks.length,
        ),
      ),
    ));
  }
  return result;
}

/// Match the last heading at or before a confirmed anchor in this content.
int? currentArticleSection(
  ChapterContent content,
  List<({String title, ReaderPosition position})> entries,
  ReaderPosition? position,
) {
  if (position == null ||
      position.contentRevision != content.contentRevision ||
      position.blockIndex < 0 ||
      position.blockIndex >= content.blocks.length ||
      content.blocks[position.blockIndex].blockKey != position.blockKey) {
    return null;
  }
  var low = 0, high = entries.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (entries[middle].position.blockIndex <= position.blockIndex) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low == 0 ? null : low - 1;
}
