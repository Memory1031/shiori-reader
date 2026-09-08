import '../../../domain/contracts/local_book_decoder.dart';
import '../../../domain/contracts/local_books.dart';
import '../../../domain/models/models.dart';
import 'txt_decoder.dart';

String filenameTitle(String filename) {
  final name = filename.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  final title = (dot > 0 ? name.substring(0, dot) : name).trim();
  return title.isEmpty ? 'Untitled' : title;
}

final _heading = RegExp(
  r'^(?:第[零〇一二三四五六七八九十百千万萬两兩壹贰貳叁參肆伍陆陸柒捌玖拾佰仟0-9０-９点之上下中外附番\.\-]+[章节節回卷部集话話](?:\s.*|[：:、].*|[^\s]{0,30})|(?:chapter|part|volume)\s+[0-9ivxlcdm]+(?:\s.*|[.:\-].*)?|序章|楔子|序言|后记|後記|终章|終章|尾声|尾聲|prologue|epilogue)$',
  caseSensitive: false,
);

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
  var chapterTitle = title, chapterStart = 0, offset = 0, start = 0, count = 0;
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

  void line(String original) {
    if (++count > 100000) {
      throw const LocalParseException(LocalParseProblem.tooLarge);
    }
    final trimmed = original.trim();
    final isHeading = trimmed.length <= 100 && _heading.hasMatch(trimmed);
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

  for (final end in RegExp(r'\r\n|\r|\n').allMatches(text)) {
    line(text.substring(start, end.end));
    start = end.end;
  }
  if (start < text.length) line(text.substring(start));
  flush();
  return LocalBookContent(
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
