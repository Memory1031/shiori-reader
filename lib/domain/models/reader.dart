import 'identity.dart';
import 'novel.dart';
import 'value_model.dart';

// scroll is retained for legacy settings and isolated viewport experiments.
// The application reader normalizes preferences to paged.
enum ReaderMode { paged, scroll }

enum ReaderThemeMode { system, light, dark }

enum ReaderPaper { paper, warm }

final class ReaderSettings extends ValueModel {
  static const schemaVersion = 3;
  ReaderSettings({
    double fontSize = 20,
    double lineHeight = 1.6,
    double paragraphSpacing = 20,
    double horizontalPadding = 40,
    this.mode = ReaderMode.paged,
    this.themeMode = ReaderThemeMode.system,
    this.paper = ReaderPaper.paper,
    this.controlsHintSeen = false,
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
  final ReaderMode mode;
  final ReaderPaper paper;
  final bool controlsHintSeen;
  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? horizontalPadding,
    ReaderThemeMode? themeMode,
    ReaderMode? mode,
    ReaderPaper? paper,
    bool? controlsHintSeen,
  }) => ReaderSettings(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    horizontalPadding: horizontalPadding ?? this.horizontalPadding,
    themeMode: themeMode ?? this.themeMode,
    mode: mode ?? this.mode,
    paper: paper ?? this.paper,
    controlsHintSeen: controlsHintSeen ?? this.controlsHintSeen,
  );
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'paragraphSpacing': paragraphSpacing,
    'horizontalPadding': horizontalPadding,
    'themeMode': themeMode.name,
    'mode': mode.name,
    'paper': paper.name,
    'controlsHintSeen': controlsHintSeen,
  };
  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    if (![1, 2, schemaVersion].contains(json['schemaVersion'])) {
      throw const FormatException('Unsupported reader settings version');
    }
    double number(String key, double min, double max) {
      final value = (json[key] as num).toDouble();
      if (!value.isFinite) throw const FormatException('Non-finite setting');
      return value.clamp(min, max);
    }

    return ReaderSettings(
      paper: json['schemaVersion'] == 3
          ? ReaderPaper.values.byName(json['paper'] as String)
          : ReaderPaper.paper,
      controlsHintSeen: json['schemaVersion'] == 3
          ? json['controlsHintSeen'] as bool
          : false,
      mode: json['schemaVersion'] == 1
          ? ReaderMode.paged
          : ReaderMode.values.byName(json['mode'] as String),
      fontSize: number('fontSize', 14, 32),
      lineHeight: number('lineHeight', 1.2, 2.4),
      paragraphSpacing: number('paragraphSpacing', 0, 32),
      horizontalPadding: number('horizontalPadding', 12, 48),
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
    mode,
    paper,
    controlsHintSeen,
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
