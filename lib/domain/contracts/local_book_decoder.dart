import '../models/models.dart';
import 'cancellation.dart';
import 'local_books.dart';

enum TxtEncoding { utf8, utf16le, utf16be, gb18030 }

/// Only strictly decoded choices are offered; preview is never committed text.
final class TxtEncodingPreview {
  TxtEncodingPreview(Map<TxtEncoding, String> samples, {this.detected})
    : samples = Map.unmodifiable(samples);
  final Map<TxtEncoding, String> samples;
  final TxtEncoding? detected;
}

typedef ChooseTxtEncoding = Future<TxtEncoding> Function(TxtEncodingPreview);

abstract interface class LocalBookDecoder {
  Future<LocalBookContent> decode(
    LocalImportSession session, {
    required LocalBookFormat format,
    required String filename,
    required CancellationToken cancellation,
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
  });
}

enum LocalParseProblem { invalid, tooLarge, encoding, drm, fixedLayout }

final class LocalParseException extends FormatException {
  const LocalParseException(this.problem) : super('Local book parsing failed');
  final LocalParseProblem problem;
}

/// EPUB TOC is independent of the unique, spine-ordered chapter catalog.
/// A null blockKey explicitly falls back to the chapter start.
final class LocalNavigationEntry {
  LocalNavigationEntry({
    required this.title,
    required this.chapterKey,
    this.blockKey,
    Iterable<LocalNavigationEntry> children = const [],
  }) : children = List.unmodifiable(children);
  final String title;
  final ChapterKey chapterKey;
  final String? blockKey;
  final List<LocalNavigationEntry> children;

  Map<String, Object?> toJson() => {
    'title': title,
    'chapter': chapterKey.toJson(),
    'block': blockKey,
    'children': children.map((e) => e.toJson()).toList(),
  };

  factory LocalNavigationEntry.fromJson(Map<String, dynamic> json) =>
      LocalNavigationEntry(
        title: json['title'] as String,
        chapterKey: ChapterKey.fromJson(
          json['chapter'] as Map<String, dynamic>,
        ),
        blockKey: json['block'] as String?,
        children: (json['children'] as List).map(
          (e) => LocalNavigationEntry.fromJson(e as Map<String, dynamic>),
        ),
      );
}
