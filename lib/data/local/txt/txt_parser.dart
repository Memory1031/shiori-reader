import '../../../domain/contracts/local_book_decoder.dart';
import '../../../domain/contracts/local_books.dart';
import '../../../domain/models/models.dart';
import 'txt_decoder.dart';
import 'txt_headings.dart';

String filenameTitle(String filename) {
  final name = filename.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  final title = (dot > 0 ? name.substring(0, dot) : name).trim();
  return title.isEmpty ? 'Untitled' : title;
}

LocalBookContent parseTxt(
  List<int> bytes,
  NovelKey book,
  String filename,
  TxtEncoding encoding,
) {
  final text = decodeTxt(bytes, encoding);
  if (text.trim().isEmpty) {
    throw const LocalParseException(LocalParseProblem.invalid);
  }
  final title = filenameTitle(filename);
  final chapters = <ChapterContent>[];
  var blocks = <ContentBlock>[];
  var chapterTitle = title, chapterStart = 0, offset = 0;
  final lines = txtLines(
    text,
    () => throw const LocalParseException(LocalParseProblem.tooLarge),
  );
  final headings = txtHeadingLines(text, lines);
  void flush() {
    if (blocks.isEmpty) return;
    // Preserve an all-heading/whitespace section without inventing body text.
    if (!blocks.any((b) => b is ParagraphBlock && b.text.trim().isNotEmpty)) {
      blocks = [
        for (final b in blocks)
          b is HeadingBlock ? ParagraphBlock(text: b.text) : b,
      ];
    }
    if (!blocks.any((b) => b is ParagraphBlock && b.text.trim().isNotEmpty)) {
      return;
    }
    chapters.add(
      ChapterContent(
        key: LocalBookIdentity.chapter(book, 'txt:$chapterStart'),
        title: chapterTitle,
        blocks: blocks,
      ),
    );
    if (chapters.length > 10000) {
      throw const LocalParseException(LocalParseProblem.tooLarge);
    }
    blocks = [];
  }

  void line(String original, bool isHeading) {
    final trimmed = original.trim();

    if (isHeading) {
      // Whitespace preceding the first heading remains with that first chapter.
      if (blocks.any(
        (b) =>
            b is HeadingBlock ||
            b is ParagraphBlock && b.text.trim().isNotEmpty,
      )) {
        flush();
        chapterStart = offset;
      }
      chapterTitle = trimmed;
    }
    blocks.add(
      isHeading ? HeadingBlock(text: original) : ParagraphBlock(text: original),
    );
    offset += original.runes.length;
  }

  for (var i = 0; i < lines.length; i++) {
    line(text.substring(lines[i].start, lines[i].end), headings.contains(i));
  }
  flush();
  return LocalBookContent(
    txtEncoding: encoding,
    detail: NovelDetail(
      summary: NovelSummary(key: book, title: title),
    ),
    catalog: Catalog(
      novelKey: book,
      volumes: [
        Volume(
          groupId: 'txt',
          isSynthetic: true,
          chapters: [
            for (var i = 0; i < chapters.length; i++)
              Chapter(
                key: chapters[i].key,
                title: chapters[i].title,
                ordinal: i,
                volumeGroupId: 'txt',
              ),
          ],
        ),
      ],
    ),
    chapters: chapters,
  );
}
