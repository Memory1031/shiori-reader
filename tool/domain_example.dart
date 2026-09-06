import 'dart:convert';
import 'dart:io';

import 'package:shiori/domain/models/models.dart';

/// Runnable with the Dart VM, without Flutter, SQL, HTML, or a live Source.
void main() {
  final source = SourceId('example');
  final novel = NovelKey(sourceId: source, novelId: 'book:1');
  final key = ChapterKey(novelKey: novel, chapterId: 'extra');
  final content = ChapterContent(
    key: key,
    title: '合成章',
    blocks: [
      ParagraphBlock(text: '中文，かな😀\r\n下一行', leadingIndent: 2),
      ParagraphBlock(text: '中文，かな😀\n下一行', leadingIndent: 2),
      ImageBlock(
        media: MediaRef(sourceId: source, mediaId: 'illustration:1'),
      ),
    ],
  );
  final catalog = Catalog(
    novelKey: novel,
    volumes: [
      Volume(
        groupId: 'synthetic-main',
        isSynthetic: true,
        chapters: [
          Chapter(
            key: key,
            title: '番外',
            ordinal: 0,
            volumeGroupId: 'synthetic-main',
          ),
        ],
      ),
    ],
  );
  final position = ReaderPosition(
    contentRevision: content.contentRevision,
    blockKey: content.blocks.first.blockKey,
    blockIndex: 0,
    blockFraction: 0,
    chapterFraction: ReaderPosition.fractionFor(
      blockIndex: 0,
      blockFraction: 0,
      blockCount: content.blocks.length,
    ),
  );
  final progress = ReadingProgress(
    snapshot: NovelSummary(key: novel, title: '合成小说'),
    chapterKey: key,
    chapterOrdinalSnapshot: 0,
    catalogRevision: catalog.revision,
    position: position,
    completed: false,
    lastReadAt: DateTime.utc(2026, 9, 7),
  );
  stdout.encoding = utf8;
  stdout.writeln(
    jsonEncode({
      'content': content.toJson(),
      'catalogRevision': catalog.revision,
      'progressNovelId': progress.novelKey.novelId,
    }),
  );
}
