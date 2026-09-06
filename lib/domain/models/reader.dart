import 'identity.dart';
import 'novel.dart';
import 'value_model.dart';

enum ReaderThemeMode { system, light, dark }

final class ReaderSettings extends ValueModel {
  static const schemaVersion = 1;
  ReaderSettings({
    double fontSize = 20,
    double lineHeight = 1.7,
    double paragraphSpacing = 12,
    double horizontalPadding = 20,
    this.themeMode = ReaderThemeMode.system,
  }) : fontSize = finiteRange(fontSize, 14, 32, 'fontSize'),
       lineHeight = finiteRange(lineHeight, 1.2, 2.4, 'lineHeight'),
       paragraphSpacing = finiteRange(
         paragraphSpacing,
         0,
         32,
         'paragraphSpacing',
       ),
       horizontalPadding = finiteRange(
         horizontalPadding,
         12,
         48,
         'horizontalPadding',
       );
  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final double horizontalPadding;
  final ReaderThemeMode themeMode;
  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? horizontalPadding,
    ReaderThemeMode? themeMode,
  }) => ReaderSettings(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    horizontalPadding: horizontalPadding ?? this.horizontalPadding,
    themeMode: themeMode ?? this.themeMode,
  );
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'paragraphSpacing': paragraphSpacing,
    'horizontalPadding': horizontalPadding,
    'themeMode': themeMode.name,
  };
  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported reader settings version');
    }
    return ReaderSettings(
      fontSize: (json['fontSize'] as num).toDouble(),
      lineHeight: (json['lineHeight'] as num).toDouble(),
      paragraphSpacing: (json['paragraphSpacing'] as num).toDouble(),
      horizontalPadding: (json['horizontalPadding'] as num).toDouble(),
      themeMode: ReaderThemeMode.values.byName(json['themeMode'] as String),
    );
  }
  @override
  List<Object?> get values => [
    fontSize,
    lineHeight,
    paragraphSpacing,
    horizontalPadding,
    themeMode,
  ];
}

final class ReaderPosition extends ValueModel {
  ReaderPosition({
    required String contentRevision,
    required String blockKey,
    required int blockIndex,
    required double blockFraction,
    required double chapterFraction,
    double? pixelOffset,
    String? layoutKey,
  }) : contentRevision = nonBlank(contentRevision, 'contentRevision'),
       blockKey = nonBlank(blockKey, 'blockKey'),
       blockIndex = nonNegative(blockIndex, 'blockIndex'),
       blockFraction = finiteRange(blockFraction, 0, 1, 'blockFraction'),
       chapterFraction = finiteRange(chapterFraction, 0, 1, 'chapterFraction'),
       pixelOffset = pixelOffset == null
           ? null
           : finiteRange(pixelOffset, 0, double.maxFinite, 'pixelOffset'),
       layoutKey = layoutKey == null ? null : nonBlank(layoutKey, 'layoutKey') {
    if ((pixelOffset == null) != (layoutKey == null)) {
      throw ArgumentError('Pixel hint requires both offset and layout key');
    }
  }
  final String contentRevision;
  final String blockKey;
  final int blockIndex;
  final double blockFraction;
  final double chapterFraction;
  final double? pixelOffset;
  final String? layoutKey;

  static double fractionFor({
    required int blockIndex,
    required double blockFraction,
    required int blockCount,
  }) {
    nonNegative(blockCount, 'blockCount');
    nonNegative(blockIndex, 'blockIndex');
    finiteRange(blockFraction, 0, 1, 'blockFraction');
    if (blockCount == 0) {
      if (blockIndex != 0 || blockFraction != 0) {
        throw ArgumentError('Invalid empty position');
      }
      return 0;
    }
    if (blockIndex >= blockCount) {
      throw ArgumentError('Block index outside chapter');
    }
    return (blockIndex + blockFraction) / blockCount;
  }

  @override
  List<Object?> get values => [
    contentRevision,
    blockKey,
    blockIndex,
    blockFraction,
    chapterFraction,
    pixelOffset,
    layoutKey,
  ];
}

final class BookshelfEntry extends ValueModel {
  BookshelfEntry({required this.snapshot, required DateTime addedAt})
    : addedAt = addedAt.toUtc();
  final NovelSummary snapshot;
  final DateTime addedAt;
  @override
  List<Object?> get values => [snapshot, addedAt];
}

final class ReadingProgress extends ValueModel {
  ReadingProgress({
    required this.snapshot,
    required this.chapterKey,
    required int chapterOrdinalSnapshot,
    required String catalogRevision,
    required this.position,
    required this.completed,
    required DateTime lastReadAt,
  }) : chapterOrdinalSnapshot = nonNegative(
         chapterOrdinalSnapshot,
         'chapterOrdinalSnapshot',
       ),
       catalogRevision = nonBlank(catalogRevision, 'catalogRevision'),
       lastReadAt = DateTime.fromMillisecondsSinceEpoch(
         lastReadAt.millisecondsSinceEpoch,
         isUtc: true,
       ) {
    if (snapshot.key != chapterKey.novelKey) {
      throw ArgumentError('Progress belongs to another novel');
    }
  }
  NovelKey get novelKey => snapshot.key;
  final NovelSummary snapshot;
  final ChapterKey chapterKey;
  final int chapterOrdinalSnapshot;
  final String catalogRevision;
  final ReaderPosition position;
  final bool completed;
  final DateTime lastReadAt;
  @override
  List<Object?> get values => [
    snapshot,
    chapterKey,
    chapterOrdinalSnapshot,
    catalogRevision,
    position,
    completed,
    lastReadAt,
  ];
}
