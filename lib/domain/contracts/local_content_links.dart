import '../models/models.dart';
import 'cancellation.dart';
import 'result.dart';

enum LocalLinkUnavailable {
  external,
  missingDocument,
  missingAnchor,
  unsupported,
}

final class LocalContentLink {
  LocalContentLink({
    required this.source,
    required this.sourceBlockKey,
    required this.label,
    this.target,
    this.targetBlockKey,
    this.unavailable,
    this.sourceOffset,
    this.footnoteText,
  }) {
    if (sourceBlockKey.isEmpty ||
        label.trim().isEmpty ||
        (target == null) != (unavailable != null) ||
        target == null && targetBlockKey != null ||
        target != null && target!.novelKey != source.novelKey ||
        sourceOffset != null && sourceOffset! < 0 ||
        sourceOffset != null && unavailable == null && footnoteText == null ||
        footnoteText != null &&
            (sourceOffset == null || footnoteText!.trim().isEmpty)) {
      throw ArgumentError('Invalid local link');
    }
  }
  final ChapterKey source;
  final String sourceBlockKey, label;
  final ChapterKey? target;
  final String? targetBlockKey;
  final LocalLinkUnavailable? unavailable;

  /// Footnote marker start in source-block Unicode code points.
  final int? sourceOffset;
  final String? footnoteText;
  bool get isFootnote => sourceOffset != null;
  Map<String, Object?> toJson() => {
    'source': source.toJson(),
    'block': sourceBlockKey,
    'label': label,
    'target': target?.toJson(),
    'targetBlock': targetBlockKey,
    'unavailable': unavailable?.name,
    if (sourceOffset != null) 'sourceOffset': sourceOffset,
    if (footnoteText != null) 'footnoteText': footnoteText,
  };
  factory LocalContentLink.fromJson(Map<String, dynamic> json) =>
      LocalContentLink(
        source: ChapterKey.fromJson(json['source'] as Map<String, dynamic>),
        sourceBlockKey: json['block'] as String,
        label: json['label'] as String,
        sourceOffset: json['sourceOffset'] as int?,
        footnoteText: json['footnoteText'] as String?,
        target: json['target'] == null
            ? null
            : ChapterKey.fromJson(json['target'] as Map<String, dynamic>),
        targetBlockKey: json['targetBlock'] as String?,
        unavailable: json['unavailable'] == null
            ? null
            : LocalLinkUnavailable.values.byName(json['unavailable'] as String),
      );
}

abstract interface class LocalContentLinkRepository {
  Future<Result<List<LocalContentLink>>> loadContentLinks(
    ChapterKey source, {
    required CancellationToken cancellation,
  });
  Future<Result<List<ChapterKey>>> loadReadingOrder(
    NovelKey book, {
    required CancellationToken cancellation,
  });
}
