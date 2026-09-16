import '../content_identity.dart';
import 'identity.dart';
import 'value_model.dart';

enum ParagraphAlignment { start, center, end }

sealed class ContentBlock extends ValueModel {
  ContentBlock(int occurrence)
    : occurrence = nonNegative(occurrence, 'occurrence');
  final int occurrence;
  List<InlineImage> get inlineImages => const [];
  Iterable<MediaRef> get mediaRefs sync* {
    if (this case ImageBlock(:final media)) yield media;
    for (final image in inlineImages) {
      yield image.media;
    }
  }

  String get kind;
  List<Object?> get semanticFields;
  Map<String, Object?> get fieldsJson;
  ContentBlock withOccurrence(int occurrence);

  late final String semanticDigest = ContentIdentity.digest(
    kind,
    semanticFields,
  );
  late final String blockKey = ContentIdentity.digest('block', [
    kind,
    semanticFields,
    occurrence,
  ]);
  Map<String, Object?> toJson() => {
    'type': kind,
    ...fieldsJson,
    'occurrence': occurrence,
    'blockKey': blockKey,
  };

  static ContentBlock fromJson(Map<String, dynamic> json) {
    final occurrence = json['occurrence'] as int;
    final ContentBlock block = switch (json['type']) {
      'paragraph' => ParagraphBlock(
        inlineImages: (json['inlineImages'] as List? ?? const []).map(
          (v) => InlineImage.fromJson(v as Map<String, dynamic>),
        ),
        text: json['text'] as String,
        alignment: ParagraphAlignment.values.byName(
          json['alignment'] as String,
        ),
        leadingIndent: json['leadingIndent'] as int,
        occurrence: occurrence,
      ),
      'image' => ImageBlock(
        media: MediaRef.fromJson(json['media'] as Map<String, dynamic>),
        width: json['width'] as int?,
        height: json['height'] as int?,
        alt: json['alt'] as String?,
        caption: json['caption'] as String?,
        occurrence: occurrence,
      ),
      'heading' => HeadingBlock(
        inlineImages: (json['inlineImages'] as List? ?? const []).map(
          (v) => InlineImage.fromJson(v as Map<String, dynamic>),
        ),
        text: json['text'] as String,
        level: json['level'] as int,
        alignment: json['alignment'] == null
            ? ParagraphAlignment.start
            : ParagraphAlignment.values.byName(json['alignment'] as String),
        occurrence: occurrence,
      ),
      'divider' => DividerBlock(occurrence: occurrence),
      _ => throw const FormatException('Unknown content block type'),
    };
    if (json['blockKey'] != block.blockKey) {
      throw const FormatException('Content block digest mismatch');
    }
    return block;
  }
}

/// A raster image at a U+FFFC code-point offset in a text block.
final class InlineImage extends ValueModel {
  InlineImage({
    required this.offset,
    required this.media,
    required this.widthEm,
    required this.heightEm,
    this.alt,
  }) {
    if (offset < 0 ||
        !widthEm.isFinite ||
        !heightEm.isFinite ||
        widthEm <= 0 ||
        widthEm > 8 ||
        heightEm <= 0 ||
        heightEm > 4) {
      throw ArgumentError('Invalid inline image');
    }
  }
  final int offset;
  final MediaRef media;
  final double widthEm, heightEm;
  final String? alt;
  Map<String, Object?> toJson() => {
    'offset': offset,
    'media': media.toJson(),
    'widthEm': widthEm,
    'heightEm': heightEm,
    'alt': alt,
  };
  factory InlineImage.fromJson(Map<String, dynamic> json) => InlineImage(
    offset: json['offset'] as int,
    media: MediaRef.fromJson(json['media'] as Map<String, dynamic>),
    widthEm: (json['widthEm'] as num).toDouble(),
    heightEm: (json['heightEm'] as num).toDouble(),
    alt: json['alt'] as String?,
  );
  @override
  List<Object?> get values => [offset, media, widthEm, heightEm, alt];
}

void validateInlineImages(String text, List<InlineImage> images) {
  if (images.isEmpty) return;
  final runes = text.runes.toList();
  var previous = -1;
  for (final image in images) {
    if (image.offset <= previous ||
        image.offset >= runes.length ||
        runes[image.offset] != 0xfffc) {
      throw ArgumentError('Inline image must reference a unique placeholder');
    }
    previous = image.offset;
  }
}

final class ParagraphBlock extends ContentBlock {
  ParagraphBlock({
    required String text,
    Iterable<InlineImage> inlineImages = const [],
    this.alignment = ParagraphAlignment.start,
    this.leadingIndent = 0,
    int occurrence = 0,
  }) : inlineImages = List.unmodifiable(inlineImages),
       text = ContentIdentity.normalizeText(text),
       super(occurrence) {
    validateInlineImages(this.text, this.inlineImages);
    if (leadingIndent < 0 || leadingIndent > 8) {
      throw ArgumentError('Indent must be 0..8 em');
    }
  }
  final String text;
  @override
  final List<InlineImage> inlineImages;
  final ParagraphAlignment alignment;

  /// Semantic leading indent in em; presentation resolves actual pixels.
  final int leadingIndent;
  @override
  String get kind => 'paragraph';
  @override
  List<Object?> get semanticFields => [
    text,
    alignment.name,
    leadingIndent,
    if (inlineImages.isNotEmpty)
      inlineImages
          .map((i) => [i.offset, i.media.identityFields, i.alt])
          .toList(),
  ];
  @override
  Map<String, Object?> get fieldsJson => {
    'text': text,
    if (inlineImages.isNotEmpty)
      'inlineImages': inlineImages.map((i) => i.toJson()).toList(),
    'alignment': alignment.name,
    'leadingIndent': leadingIndent,
  };
  @override
  ParagraphBlock withOccurrence(int occurrence) => ParagraphBlock(
    text: text,
    inlineImages: inlineImages,
    alignment: alignment,
    leadingIndent: leadingIndent,
    occurrence: occurrence,
  );
  @override
  List<Object?> get values => [...semanticFields, inlineImages, occurrence];
}

final class ImageBlock extends ContentBlock {
  ImageBlock({
    required this.media,
    this.width,
    this.height,
    String? alt,
    String? caption,
    int occurrence = 0,
  }) : alt = alt == null ? null : ContentIdentity.normalizeText(alt),
       caption = caption == null
           ? null
           : ContentIdentity.normalizeText(caption),
       super(occurrence) {
    if ((width != null && width! <= 0) || (height != null && height! <= 0)) {
      throw ArgumentError('Known image dimensions must be positive');
    }
  }
  final MediaRef media;
  final int? width;
  final int? height;
  final String? alt;
  final String? caption;
  @override
  String get kind => 'image';
  // Dimensions are discoverable layout metadata, not semantic identity.
  @override
  List<Object?> get semanticFields => [media.identityFields, alt, caption];
  @override
  Map<String, Object?> get fieldsJson => {
    'media': media.toJson(),
    'width': width,
    'height': height,
    'alt': alt,
    'caption': caption,
  };
  @override
  ImageBlock withOccurrence(int occurrence) => ImageBlock(
    media: media,
    width: width,
    height: height,
    alt: alt,
    caption: caption,
    occurrence: occurrence,
  );
  @override
  List<Object?> get values => [media, width, height, alt, caption, occurrence];
}

final class HeadingBlock extends ContentBlock {
  HeadingBlock({
    required String text,
    Iterable<InlineImage> inlineImages = const [],
    this.level = 1,
    this.alignment = ParagraphAlignment.start,
    int occurrence = 0,
  }) : inlineImages = List.unmodifiable(inlineImages),
       text = nonBlank(ContentIdentity.normalizeText(text), 'heading'),
       super(occurrence) {
    validateInlineImages(this.text, this.inlineImages);
    if (level < 1 || level > 6) {
      throw ArgumentError('Heading level must be 1..6');
    }
  }
  final String text;
  @override
  final List<InlineImage> inlineImages;
  final int level;
  final ParagraphAlignment alignment;
  @override
  String get kind => 'heading';
  @override
  List<Object?> get semanticFields => [
    text,
    level,
    if (inlineImages.isNotEmpty)
      inlineImages
          .map((i) => [i.offset, i.media.identityFields, i.alt])
          .toList(),
    if (alignment != ParagraphAlignment.start) alignment.name,
  ];
  @override
  Map<String, Object?> get fieldsJson => {
    'text': text,
    if (inlineImages.isNotEmpty)
      'inlineImages': inlineImages.map((i) => i.toJson()).toList(),
    'level': level,
    if (alignment != ParagraphAlignment.start) 'alignment': alignment.name,
  };
  @override
  HeadingBlock withOccurrence(int occurrence) => HeadingBlock(
    text: text,
    inlineImages: inlineImages,
    level: level,
    alignment: alignment,
    occurrence: occurrence,
  );
  @override
  List<Object?> get values => [...semanticFields, inlineImages, occurrence];
}

final class DividerBlock extends ContentBlock {
  DividerBlock({int occurrence = 0}) : super(occurrence);
  @override
  String get kind => 'divider';
  @override
  List<Object?> get semanticFields => const [];
  @override
  Map<String, Object?> get fieldsJson => const {};
  @override
  DividerBlock withOccurrence(int occurrence) =>
      DividerBlock(occurrence: occurrence);
  @override
  List<Object?> get values => [occurrence];
}

final class ChapterContent extends ValueModel {
  factory ChapterContent({
    required ChapterKey key,
    required String title,
    required Iterable<ContentBlock> blocks,
  }) {
    final occurrences = <String, int>{};
    final indexed = <ContentBlock>[];
    var readable = false;
    for (final block in blocks) {
      for (final media in block.mediaRefs) {
        if (media.sourceId != key.novelKey.sourceId) {
          throw ArgumentError('Body image belongs to another Source');
        }
      }
      if (block is ImageBlock) {
        readable = true;
      } else if (block is ParagraphBlock && block.text.trim().isNotEmpty) {
        readable = true;
      }
      final digest = block.semanticDigest;
      final occurrence = occurrences[digest] ?? 0;
      occurrences[digest] = occurrence + 1;
      indexed.add(block.withOccurrence(occurrence));
    }
    if (!readable) throw ArgumentError('Chapter has no readable text or image');
    return ChapterContent._(
      key,
      nonBlank(ContentIdentity.normalizeText(title), 'title'),
      List.unmodifiable(indexed),
    );
  }
  ChapterContent._(this.key, this.title, this.blocks);
  final ChapterKey key;
  final String title;
  final List<ContentBlock> blocks;
  late final String contentRevision = ContentIdentity.digest('chapter', [
    title,
    [for (final block in blocks) block.blockKey],
  ]);

  /// Domain representation only; timestamps/parser/cache codec versions belong
  /// to a future storage envelope, not to this normalized content identity.
  Map<String, Object?> toJson() => {
    'normalizationVersion': ContentIdentity.normalizationVersion,
    'key': key.toJson(),
    'title': title,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'contentRevision': contentRevision,
  };

  factory ChapterContent.fromJson(Map<String, dynamic> json) {
    if (json['normalizationVersion'] != ContentIdentity.normalizationVersion) {
      throw const FormatException('Unsupported content normalization version');
    }
    final input = (json['blocks'] as List<dynamic>)
        .map((b) => ContentBlock.fromJson(b as Map<String, dynamic>))
        .toList();
    final content = ChapterContent(
      key: ChapterKey.fromJson(json['key'] as Map<String, dynamic>),
      title: json['title'] as String,
      blocks: input,
    );
    if (json['contentRevision'] != content.contentRevision ||
        List.generate(
          input.length,
          (i) => input[i] == content.blocks[i],
        ).contains(false)) {
      throw const FormatException('Chapter digest or occurrence mismatch');
    }
    return content;
  }
  @override
  List<Object?> get values => [key, title, blocks];
}
