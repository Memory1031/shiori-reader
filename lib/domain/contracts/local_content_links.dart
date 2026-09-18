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
    this.targetOffset,
    this.unavailable,
    this.sourceOffset,
    this.sourceLength,
    this.footnoteText,
  }) {
    if (sourceBlockKey.isEmpty ||
        label.trim().isEmpty ||
        (target == null) != (unavailable != null) ||
        target == null && targetBlockKey != null ||
        targetOffset != null && (targetBlockKey == null || targetOffset! < 0) ||
        target != null && target!.novelKey != source.novelKey ||
        sourceOffset != null && sourceOffset! < 0 ||
        sourceLength != null && (sourceOffset == null || sourceLength! <= 0) ||
        sourceOffset != null &&
            sourceLength == null &&
            unavailable == null &&
            footnoteText == null ||
        footnoteText != null &&
            (sourceOffset == null || footnoteText!.trim().isEmpty)) {
      throw ArgumentError('Invalid local link');
    }
  }
  final ChapterKey source;
  final String sourceBlockKey, label;
  final ChapterKey? target;
  final String? targetBlockKey;

  /// Target-block Unicode code-point offset; absent in older manifests.
  final int? targetOffset;
  final LocalLinkUnavailable? unavailable;

  /// Footnote marker start in source-block Unicode code points.
  final int? sourceOffset;

  /// Ordinary inline links carry a range; older footnotes omit this field.
  final int? sourceLength;
  final String? footnoteText;
  bool get isFootnote => sourceOffset != null && sourceLength == null;
  Map<String, Object?> toJson() => {
    'source': source.toJson(),
    'block': sourceBlockKey,
    'label': label,
    'target': target?.toJson(),
    'targetBlock': targetBlockKey,
    if (targetOffset != null) 'targetOffset': targetOffset,
    'unavailable': unavailable?.name,
    if (sourceOffset != null) 'sourceOffset': sourceOffset,
    if (sourceLength != null) 'sourceLength': sourceLength,
    if (footnoteText != null) 'footnoteText': footnoteText,
  };
  factory LocalContentLink.fromJson(Map<String, dynamic> json) =>
      LocalContentLink(
        source: ChapterKey.fromJson(json['source'] as Map<String, dynamic>),
        sourceBlockKey: json['block'] as String,
        label: json['label'] as String,
        sourceOffset: json['sourceOffset'] as int?,
        sourceLength: json['sourceLength'] as int?,
        footnoteText: json['footnoteText'] as String?,
        target: json['target'] == null
            ? null
            : ChapterKey.fromJson(json['target'] as Map<String, dynamic>),
        targetBlockKey: json['targetBlock'] as String?,
        targetOffset: json['targetOffset'] as int?,
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
