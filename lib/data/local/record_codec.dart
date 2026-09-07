import 'dart:convert';
import '../../domain/models/models.dart';

/// SQL schema and payload codec versions are independent.
class RecordCodec {
  static String encode(String kind, Map<String, Object?> payload) =>
      jsonEncode({'version': 1, 'kind': kind, 'payload': payload});
  static Map<String, dynamic> decode(String kind, String text) {
    final map = jsonDecode(text) as Map<String, dynamic>;
    if (map['version'] != 1 || map['kind'] != kind) {
      throw const FormatException('Unsupported record');
    }
    return map['payload'] as Map<String, dynamic>;
  }

  static Map<String, Object?> summaryJson(NovelSummary value) => {
    'key': value.key.toJson(),
    'title': value.title,
    'authors': value.authors,
    'cover': value.cover?.toJson(),
  };
  static NovelSummary summaryFrom(Map<String, dynamic> map) => NovelSummary(
    key: NovelKey.fromJson(map['key'] as Map<String, dynamic>),
    title: map['title'] as String,
    authors: (map['authors'] as List).cast<String>(),
    cover: map['cover'] == null
        ? null
        : MediaRef.fromJson(map['cover'] as Map<String, dynamic>),
  );
  static String summary(NovelSummary value) =>
      encode('summary', summaryJson(value));
  static NovelSummary readSummary(String value) =>
      summaryFrom(decode('summary', value));
  static String detail(NovelDetail value) => encode('detail', {
    'summary': summaryJson(value.summary),
    'synopsis': value.synopsis,
    'tags': value.tags,
    'status': value.status.name,
    'sourceUpdatedAt': value.sourceUpdatedAt?.toIso8601String(),
  });
  static NovelDetail readDetail(String value) {
    final map = decode('detail', value);
    return NovelDetail(
      summary: summaryFrom(map['summary'] as Map<String, dynamic>),
      synopsis: map['synopsis'] as String,
      tags: (map['tags'] as List).cast<String>(),
      status: NovelStatus.values.byName(map['status'] as String),
      sourceUpdatedAt: map['sourceUpdatedAt'] == null
          ? null
          : DateTime.parse(map['sourceUpdatedAt'] as String),
    );
  }

  static String catalog(Catalog value) => encode('catalog', {
    'key': value.novelKey.toJson(),
    'revision': value.revision,
    'volumes': [
      for (final volume in value.volumes)
        {
          'id': volume.groupId,
          'title': volume.title,
          'synthetic': volume.isSynthetic,
          'chapters': [
            for (final chapter in volume.chapters)
              {
                'key': chapter.key.toJson(),
                'title': chapter.title,
                'ordinal': chapter.ordinal,
              },
          ],
        },
    ],
  });
  static Catalog readCatalog(String value) {
    final map = decode('catalog', value);
    final result = Catalog(
      novelKey: NovelKey.fromJson(map['key'] as Map<String, dynamic>),
      volumes: [
        for (final volume in map['volumes'] as List)
          Volume(
            groupId: volume['id'] as String,
            title: volume['title'] as String?,
            isSynthetic: volume['synthetic'] as bool,
            chapters: [
              for (final chapter in volume['chapters'] as List)
                Chapter(
                  key: ChapterKey.fromJson(
                    chapter['key'] as Map<String, dynamic>,
                  ),
                  title: chapter['title'] as String,
                  ordinal: chapter['ordinal'] as int,
                  volumeGroupId: volume['id'] as String,
                ),
            ],
          ),
      ],
    );
    if (result.revision != map['revision']) {
      throw const FormatException('Catalog revision mismatch');
    }
    return result;
  }

  static String chapter(ChapterContent value) =>
      encode('chapter', value.toJson());
  static ChapterContent readChapter(String value) =>
      ChapterContent.fromJson(decode('chapter', value));
}
