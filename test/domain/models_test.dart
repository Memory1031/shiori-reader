import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:shiori/domain/content_identity.dart';
import 'package:shiori/domain/models/models.dart';

final source = SourceId('fixture');
NovelKey novel([String id = '1', String sourceName = 'fixture']) =>
    NovelKey(sourceId: SourceId(sourceName), novelId: id);
ChapterKey key([String book = '1', String chapter = 'c']) =>
    ChapterKey(novelKey: novel(book), chapterId: chapter);
MediaRef media([String id = 'image']) =>
    MediaRef(sourceId: source, mediaId: id);
ChapterContent content(Iterable<ContentBlock> blocks) =>
    ChapterContent(key: key(), title: '合成章', blocks: blocks);
ReaderPosition position({
  double fraction = 0,
  double chapterFraction = 0,
  int index = 0,
  double? pixel,
  String? layout,
}) => ReaderPosition(
  contentRevision: 'revision',
  blockKey: 'block',
  blockIndex: index,
  blockFraction: fraction,
  chapterFraction: chapterFraction,
  pixelOffset: pixel,
  layoutKey: layout,
);

void main() {
  test(
    'same remote ID stays isolated by Source and novel, with value equality',
    () {
      expect(novel(), novel());
      expect(novel().hashCode, novel().hashCode);
      expect({novel(), novel(), novel('1', 'other')}, hasLength(2));
      expect(key(), isNot(key('other')));
      expect(
        MediaRef(sourceId: SourceId('other'), mediaId: 'image'),
        isNot(media()),
      );
      expect(NovelKey(sourceId: source, novelId: ' id ').novelId, ' id ');
      expect(() => novel(' '), throwsArgumentError);
      expect(() => SourceId(''), throwsArgumentError);
    },
  );

  test('identity tuple encoding avoids concatenation collisions', () {
    final a = NovelKey(sourceId: SourceId('a'), novelId: 'b:c');
    final b = NovelKey(sourceId: SourceId('a:b'), novelId: 'c');
    expect(
      ContentIdentity.digest('key', a.identityFields),
      isNot(ContentIdentity.digest('key', b.identityFields)),
    );
    expect(
      () => ContentIdentity.digest('bad', [
        {'unstable': 1},
      ]),
      throwsArgumentError,
    );
    expect(
      () => ContentIdentity.digest('bad', [double.nan]),
      throwsArgumentError,
    );
  });

  test('metadata is immutable, unknown stays unknown and times are UTC', () {
    final authors = ['合成作者'];
    final tags = ['合成标签'];
    final summary = NovelSummary(key: novel(), title: '书', authors: authors);
    final detail = NovelDetail(
      summary: summary,
      tags: tags,
      sourceUpdatedAt: DateTime(2026, 9, 7),
    );
    authors.clear();
    tags.clear();
    expect(summary.authors, ['合成作者']);
    expect(detail.tags, ['合成标签']);
    expect(() => summary.authors.add('x'), throwsUnsupportedError);
    expect(() => detail.tags.clear(), throwsUnsupportedError);
    expect(detail.status, NovelStatus.unknown);
    expect(detail.sourceUpdatedAt!.isUtc, true);
    expect(NovelDetail(summary: summary).sourceUpdatedAt, isNull);
    expect(NovelSummary(key: novel(), title: '书').authors, isEmpty);
    expect(
      () => NovelSummary(
        key: novel(),
        title: '书',
        cover: MediaRef(sourceId: SourceId('other'), mediaId: 'image'),
      ),
      throwsArgumentError,
    );
  });

  test(
    'catalog preserves specials, duplicate labels and synthetic unnamed groups',
    () {
      final chapters = [
        Chapter(
          key: key('1', '99'),
          title: '1',
          ordinal: 0,
          volumeGroupId: 'special',
        ),
        Chapter(
          key: key('1', '2'),
          title: '1',
          ordinal: 1,
          volumeGroupId: 'special',
        ),
      ];
      final volumes = [
        Volume(groupId: 'special', isSynthetic: true, chapters: chapters),
        Volume(
          groupId: 'after',
          title: '番外',
          chapters: [
            Chapter(
              key: key('1', 'extra'),
              title: '全卷',
              ordinal: 2,
              volumeGroupId: 'after',
            ),
          ],
        ),
      ];
      final catalog = Catalog(novelKey: novel(), volumes: volumes);
      chapters.clear();
      volumes.clear();
      expect(catalog.flatChapters.map((c) => c.key.chapterId), [
        '99',
        '2',
        'extra',
      ]);
      expect(catalog.volumes.first.title, isNull);
      expect(catalog.volumes.first.isSynthetic, true);
      expect(() => catalog.volumes.clear(), throwsUnsupportedError);
      expect(
        () => catalog.volumes.first.chapters.clear(),
        throwsUnsupportedError,
      );
      expect(Catalog(novelKey: novel(), volumes: catalog.volumes), catalog);
      expect(
        Catalog(novelKey: novel(), volumes: catalog.volumes).revision,
        catalog.revision,
      );
      expect(Catalog(novelKey: novel(), volumes: []).flatChapters, isEmpty);
    },
  );

  test(
    'catalog rejects duplicate IDs, cross-book membership and invalid ordinals',
    () {
      final chapter = Chapter(
        key: key(),
        title: 'c',
        ordinal: 0,
        volumeGroupId: 'v',
      );
      expect(
        () => Volume(groupId: 'wrong', chapters: [chapter]),
        throwsArgumentError,
      );
      for (final chapters in [
        [chapter, chapter],
        [
          Chapter(
            key: key('other'),
            title: 'c',
            ordinal: 0,
            volumeGroupId: 'v',
          ),
        ],
        [Chapter(key: key(), title: 'c', ordinal: 1, volumeGroupId: 'v')],
      ]) {
        expect(
          () => Catalog(
            novelKey: novel(),
            volumes: [Volume(groupId: 'v', chapters: chapters)],
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => Catalog(
          novelKey: novel(),
          volumes: [
            Volume(groupId: 'v', chapters: []),
            Volume(groupId: 'v', chapters: []),
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test('catalog revision changes when source order changes', () {
    Catalog ordered(List<String> ids) => Catalog(
      novelKey: novel(),
      volumes: [
        Volume(
          groupId: 'v',
          chapters: [
            for (var i = 0; i < ids.length; i++)
              Chapter(
                key: key('1', ids[i]),
                title: '番外',
                ordinal: i,
                volumeGroupId: 'v',
              ),
          ],
        ),
      ],
    );
    expect(ordered(['a', 'b']).revision, isNot(ordered(['b', 'a']).revision));
  });

  test('Unicode and semantic whitespace survive line ending normalization', () {
    const text = '　中文，かな😀\r\n\r下一行 e\u0301　';
    final paragraph = ParagraphBlock(text: text);
    expect(paragraph.text, '　中文，かな😀\n\n下一行 e\u0301　');
    expect(paragraph.text.runes.contains(0x1f600), true);
    expect(
      ParagraphBlock(text: 'e\u0301').blockKey,
      isNot(ParagraphBlock(text: 'é').blockKey),
    );
    expect(
      () => ParagraphBlock(text: String.fromCharCode(0xd800)),
      throwsArgumentError,
    );
    expect(() => novel(String.fromCharCode(0xdc00)), throwsArgumentError);
    expect(
      ParagraphBlock(text: 'a\r\nb').blockKey,
      ParagraphBlock(text: 'a\nb').blockKey,
    );
  });

  test(
    'repeat occurrence is chapter-local and unrelated insertions preserve keys',
    () {
      final p = ParagraphBlock(text: '重复');
      final first = content([p, p]);
      final edited = content([ParagraphBlock(text: '新增'), p, p]);
      expect(first.blocks.map((b) => b.occurrence), [0, 1]);
      expect(first.blocks[0].blockKey, isNot(first.blocks[1].blockKey));
      expect(edited.blocks[1].blockKey, first.blocks[0].blockKey);
      expect(edited.blocks[2].blockKey, first.blocks[1].blockKey);
      expect(first.contentRevision, isNot(edited.contentRevision));
      expect(content([p]).blocks.single.occurrence, 0);
      expect(p.occurrence, 0);
    },
  );

  test(
    'body validity allows text-only and image-only, not blank/chrome-only',
    () {
      expect(content([ParagraphBlock(text: '正文')]).blocks, hasLength(1));
      expect(content([ImageBlock(media: media())]).blocks, hasLength(1));
      for (final blocks in <List<ContentBlock>>[
        [],
        [ParagraphBlock(text: '\n　 ')],
        [HeadingBlock(text: '标题'), DividerBlock()],
      ]) {
        expect(() => content(blocks), throwsArgumentError);
      }
      expect(
        () => content([
          ImageBlock(
            media: MediaRef(sourceId: SourceId('other'), mediaId: 'i'),
          ),
        ]),
        throwsArgumentError,
      );
    },
  );

  test(
    'image identity includes source/media/caption but excludes learned dimensions',
    () {
      final unknown = ImageBlock(media: media(), caption: '合成图');
      final known = ImageBlock(
        media: media(),
        caption: '合成图',
        width: 2048,
        height: 829,
      );
      expect(known, isNot(unknown));
      expect(known.blockKey, unknown.blockKey);
      expect(
        content([known]).contentRevision,
        content([unknown]).contentRevision,
      );
      expect(
        content([ImageBlock(media: media('other'))]).contentRevision,
        isNot(content([unknown]).contentRevision),
      );
      expect(() => ImageBlock(media: media(), width: 0), throwsArgumentError);
      expect(() => HeadingBlock(text: '标题', level: 7), throwsArgumentError);
      expect(
        () => ParagraphBlock(text: '正文', leadingIndent: -1),
        throwsArgumentError,
      );
    },
  );

  test(
    'all block variants roundtrip with validated keys and immutable content',
    () {
      final input = <ContentBlock>[
        HeadingBlock(text: '标题'),
        ParagraphBlock(text: '正文'),
        ParagraphBlock(text: ''),
        ImageBlock(media: media()),
        DividerBlock(),
      ];
      final chapter = content(input);
      input.clear();
      expect(chapter.blocks, hasLength(5));
      expect(() => chapter.blocks.clear(), throwsUnsupportedError);
      final json =
          jsonDecode(jsonEncode(chapter.toJson())) as Map<String, dynamic>;
      expect(ChapterContent.fromJson(json), chapter);
      json['contentRevision'] = 'bad';
      expect(() => ChapterContent.fromJson(json), throwsFormatException);
      json['normalizationVersion'] = 999;
      expect(() => ChapterContent.fromJson(json), throwsFormatException);
      final corrupt = chapter.toJson();
      ((corrupt['blocks'] as List).first as Map)['type'] = 'unknown';
      expect(() => ChapterContent.fromJson(corrupt), throwsFormatException);
    },
  );

  test(
    'long paragraph remains one block through serialization and renderer changes',
    () {
      final text = List.filled(20000, '测😀').join();
      final chapter = content([ParagraphBlock(text: text)]);
      final before = jsonEncode(chapter.toJson());
      for (final chunkSize in [128, 1024, 4096]) {
        final runes = text.runes.toList();
        final chunks = <String>[];
        for (var i = 0; i < runes.length; i += chunkSize) {
          chunks.add(String.fromCharCodes(runes.skip(i).take(chunkSize)));
        }
        expect(chunks.join(), text);
        expect(chapter.blocks, hasLength(1));
        expect(jsonEncode(chapter.toJson()), before);
        expect(ReaderSettings().copyWith(fontSize: 32).fontSize, 32);
      }
      final restored = ChapterContent.fromJson(
        jsonDecode(before) as Map<String, dynamic>,
      );
      expect(
        (restored.blocks.single as ParagraphBlock).text.runes.length,
        40000,
      );
      expect(restored.contentRevision, chapter.contentRevision);
      expect(restored.blocks.single.blockKey, chapter.blocks.single.blockKey);
      expect(before, isNot(contains('chunk')));
    },
  );

  test(
    'positions reject invalid fractions, indices and unpaired pixel hints',
    () {
      for (final bad in [
        -0.1,
        1.1,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(() => position(fraction: bad), throwsArgumentError);
        expect(() => position(chapterFraction: bad), throwsArgumentError);
      }
      expect(() => position(index: -1), throwsArgumentError);
      expect(() => position(pixel: 0), throwsArgumentError);
      expect(() => position(layout: 'portrait'), throwsArgumentError);
      expect(
        () => position(pixel: double.nan, layout: 'portrait'),
        throwsArgumentError,
      );
      expect(position(fraction: 1, chapterFraction: 1).blockFraction, 1);
      expect(position(pixel: 0, layout: 'portrait').pixelOffset, 0);
      expect(
        ReaderPosition.fractionFor(
          blockIndex: 1,
          blockFraction: 0.5,
          blockCount: 3,
        ),
        0.5,
      );
      expect(
        ReaderPosition.fractionFor(
          blockIndex: 0,
          blockFraction: 0,
          blockCount: 0,
        ),
        0,
      );
      expect(
        () => ReaderPosition.fractionFor(
          blockIndex: 3,
          blockFraction: 0,
          blockCount: 3,
        ),
        throwsArgumentError,
      );
    },
  );

  test('settings validate bounds and reject unknown persistence versions', () {
    final settings = ReaderSettings();
    expect(settings.fontSize, 20);
    expect(settings.themeMode, ReaderThemeMode.system);
    expect(ReaderSettings.fromJson(settings.toJson()), settings);
    for (final bad in [13.0, 33.0, double.nan, double.infinity]) {
      expect(() => settings.copyWith(fontSize: bad), throwsArgumentError);
    }
    expect(() => ReaderSettings(lineHeight: 0), throwsArgumentError);
    expect(() => ReaderSettings(horizontalPadding: 49), throwsArgumentError);
    expect(() => ReaderSettings(paragraphSpacing: -1), throwsArgumentError);
    expect(
      () => ReaderSettings.fromJson({...settings.toJson(), 'schemaVersion': 2}),
      throwsFormatException,
    );
  });

  test(
    'progress keeps a separate snapshot and validates chapter ownership',
    () {
      final snapshot = NovelSummary(
        key: novel(),
        title: '最近阅读',
        cover: media(),
      );
      final time = DateTime(2026, 9, 7, 1, 2, 3, 4, 567);
      final progress = ReadingProgress(
        snapshot: snapshot,
        chapterKey: key(),
        chapterOrdinalSnapshot: 0,
        catalogRevision: 'catalog',
        position: position(),
        completed: true,
        lastReadAt: time,
      );
      expect(progress.novelKey, snapshot.key);
      expect(progress.lastReadAt.isUtc, true);
      expect(progress.lastReadAt.microsecond, 0);
      expect(progress.snapshot.cover, media());
      expect(
        BookshelfEntry(snapshot: snapshot, addedAt: time).addedAt,
        time.toUtc(),
      );
      expect(
        () => ReadingProgress(
          snapshot: snapshot,
          chapterKey: key('other'),
          chapterOrdinalSnapshot: 0,
          catalogRevision: 'catalog',
          position: position(),
          completed: false,
          lastReadAt: time,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'domain source has no Flutter, SQL, HTML, transport or renderer imports',
    () {
      for (final file in Directory(
        'lib/domain',
      ).listSync(recursive: true).whereType<File>()) {
        final text = file.readAsStringSync();
        final imports = RegExp(
          r'''(?:import|export)\s+['"]([^'"]+)['"]''',
        ).allMatches(text).map((m) => m[1]!);
        for (final uri in imports) {
          if (!uri.contains(':')) {
            expect(
              file.absolute.uri
                  .resolve(uri)
                  .toString()
                  .startsWith(Directory('lib/domain').absolute.uri.toString()),
              true,
              reason: '${file.path} crosses the Domain boundary through $uri',
            );
          }
          expect(
            uri.startsWith('package:') && uri != 'package:crypto/crypto.dart',
            false,
            reason: '${file.path} imports $uri',
          );
          expect(
            uri.startsWith('dart:') &&
                !{
                  'dart:convert',
                  'dart:async',
                  'dart:typed_data',
                }.contains(uri),
            false,
          );
        }
        expect(
          RegExp(
            r'class\s+(RenderChunk|LayoutChunk|Author|Tag)\b',
          ).hasMatch(text),
          false,
        );
      }
    },
  );
}
