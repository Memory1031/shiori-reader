import '../content_identity.dart';
import 'identity.dart';
import 'value_model.dart';

enum NovelStatus { unknown, ongoing, completed, hiatus }

final class NovelSummary extends ValueModel {
  NovelSummary({
    required this.key,
    required String title,
    this.cover,
    Iterable<String> authors = const [],
  }) : title = nonBlank(ContentIdentity.normalizeText(title), 'title'),
       authors = List.unmodifiable(authors.map((a) => nonBlank(a, 'author'))) {
    if (cover != null && cover!.sourceId != key.sourceId) {
      throw ArgumentError('Cover belongs to another Source');
    }
  }
  final NovelKey key;
  final String title;
  final MediaRef? cover;
  final List<String> authors;
  @override
  List<Object?> get values => [key, title, cover, authors];
}

final class NovelDetail extends ValueModel {
  NovelDetail({
    required this.summary,
    String synopsis = '',
    Iterable<String> tags = const [],
    this.status = NovelStatus.unknown,
    DateTime? sourceUpdatedAt,
  }) : synopsis = ContentIdentity.normalizeText(synopsis),
       tags = List.unmodifiable(tags.map((t) => nonBlank(t, 'tag'))),
       sourceUpdatedAt = sourceUpdatedAt?.toUtc();
  final NovelSummary summary;
  final String synopsis;
  final List<String> tags;
  final NovelStatus status;
  final DateTime? sourceUpdatedAt;
  @override
  List<Object?> get values => [
    summary,
    synopsis,
    tags,
    status,
    sourceUpdatedAt,
  ];
}

final class Chapter extends ValueModel {
  Chapter({
    required this.key,
    required String title,
    required int ordinal,
    required String volumeGroupId,
  }) : title = nonBlank(ContentIdentity.normalizeText(title), 'title'),
       ordinal = nonNegative(ordinal, 'ordinal'),
       volumeGroupId = nonBlank(volumeGroupId, 'volumeGroupId');
  final ChapterKey key;
  final String title;
  final int ordinal;
  final String volumeGroupId;
  @override
  List<Object?> get values => [key, title, ordinal, volumeGroupId];
}

final class Volume extends ValueModel {
  Volume({
    required String groupId,
    String? title,
    this.isSynthetic = false,
    required Iterable<Chapter> chapters,
  }) : groupId = nonBlank(groupId, 'groupId'),
       title = title == null || title.trim().isEmpty
           ? null
           : ContentIdentity.normalizeText(title),
       chapters = List.unmodifiable(chapters) {
    if (this.chapters.any((c) => c.volumeGroupId != groupId)) {
      throw ArgumentError('Chapter/volume relationship mismatch');
    }
  }
  final String groupId;
  final String? title;
  final bool isSynthetic;
  final List<Chapter> chapters;
  @override
  List<Object?> get values => [groupId, title, isSynthetic, chapters];
}

final class Catalog extends ValueModel {
  Catalog({required this.novelKey, required Iterable<Volume> volumes})
    : volumes = List.unmodifiable(volumes) {
    final groups = <String>{};
    final keys = <ChapterKey>{};
    var ordinal = 0;
    for (final volume in this.volumes) {
      if (!groups.add(volume.groupId)) {
        throw ArgumentError('Duplicate volume ID');
      }
      for (final chapter in volume.chapters) {
        if (chapter.key.novelKey != novelKey ||
            !keys.add(chapter.key) ||
            chapter.ordinal != ordinal++) {
          throw ArgumentError('Invalid catalog identity, order or membership');
        }
      }
    }
  }
  final NovelKey novelKey;
  final List<Volume> volumes;
  // A lazy view over the sole owned immutable hierarchy, not a second list.
  Iterable<Chapter> get flatChapters => volumes.expand((v) => v.chapters);
  late final String revision = ContentIdentity.digest('catalog', [
    novelKey.identityFields,
    for (final volume in volumes)
      [
        volume.groupId,
        volume.title,
        volume.isSynthetic,
        [
          for (final chapter in volume.chapters)
            [chapter.key.identityFields, chapter.title, chapter.ordinal],
        ],
      ],
  ]);
  @override
  List<Object?> get values => [novelKey, volumes];
}
