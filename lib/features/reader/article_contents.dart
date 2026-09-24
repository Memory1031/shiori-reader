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
