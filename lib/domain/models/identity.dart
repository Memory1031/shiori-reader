import 'value_model.dart';

final class SourceId extends ValueModel {
  SourceId(String value) : value = nonBlank(value, 'sourceId');
  final String value;
  @override
  List<Object?> get values => [value];
}

final class NovelKey extends ValueModel {
  NovelKey({required this.sourceId, required String novelId})
    : novelId = nonBlank(novelId, 'novelId');
  final SourceId sourceId;
  final String novelId;
  List<Object?> get identityFields => [sourceId.value, novelId];
  Map<String, Object?> toJson() => {
    'sourceId': sourceId.value,
    'novelId': novelId,
  };
  factory NovelKey.fromJson(Map<String, dynamic> json) => NovelKey(
    sourceId: SourceId(json['sourceId'] as String),
    novelId: json['novelId'] as String,
  );
  @override
  List<Object?> get values => [sourceId, novelId];
}

final class ChapterKey extends ValueModel {
  ChapterKey({required this.novelKey, required String chapterId})
    : chapterId = nonBlank(chapterId, 'chapterId');
  final NovelKey novelKey;
  final String chapterId;
  List<Object?> get identityFields => [...novelKey.identityFields, chapterId];
  Map<String, Object?> toJson() => {
    'novelKey': novelKey.toJson(),
    'chapterId': chapterId,
  };
  factory ChapterKey.fromJson(Map<String, dynamic> json) => ChapterKey(
    novelKey: NovelKey.fromJson(json['novelKey'] as Map<String, dynamic>),
    chapterId: json['chapterId'] as String,
  );
  @override
  List<Object?> get values => [novelKey, chapterId];
}

/// Source must supply a durable, secret-free opaque identifier. Domain does not
/// interpret URLs or sign requests; future SourceMedia owns resolution.
final class MediaRef extends ValueModel {
  MediaRef({required this.sourceId, required String mediaId})
    : mediaId = nonBlank(mediaId, 'mediaId');
  final SourceId sourceId;
  final String mediaId;
  List<Object?> get identityFields => [sourceId.value, mediaId];
  Map<String, Object?> toJson() => {
    'sourceId': sourceId.value,
    'mediaId': mediaId,
  };
  factory MediaRef.fromJson(Map<String, dynamic> json) => MediaRef(
    sourceId: SourceId(json['sourceId'] as String),
    mediaId: json['mediaId'] as String,
  );
  @override
  List<Object?> get values => [sourceId, mediaId];
}
