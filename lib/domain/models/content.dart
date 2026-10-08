import 'package:characters/characters.dart';

import '../content_identity.dart';
import 'identity.dart';
import 'table_row.dart';
export 'table_row.dart';
import 'value_model.dart';
import 'content_style.dart';
export 'content_style.dart';
import 'inline_ruby.dart';
export 'inline_ruby.dart';
import 'inline_stack.dart';
export 'inline_stack.dart';

enum ParagraphAlignment { start, center, end }

sealed class ContentBlock extends ValueModel {
  ContentBlock(
    int occurrence, {
    this.box,
    this.layout,
    this.hasAuthoredFontSize = false,
  }) : occurrence = nonNegative(occurrence, 'occurrence');
  final int occurrence;
  final BlockBox? box;

  /// Element-local geometry inside the one supported outer container.
  final BlockBox? layout;

  /// Effective size on the block itself, including inheritance; unrelated
  /// inline color or a child-only size never suppresses default heading size.
  final bool hasAuthoredFontSize;
  List<InlineTextStyle> get inlineStyles => const [];
  List<InlineImage> get inlineImages => const [];
  List<InlineRuby> get inlineRuby => const [];
  List<InlineStack> get inlineStacks => const [];
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
    if (box != null) 'box': box!.toJson(),
    if (layout != null) 'layout': layout!.toJson(),
    if (hasAuthoredFontSize) 'hasAuthoredFontSize': true,
    'occurrence': occurrence,
    'blockKey': blockKey,
  };

  static ContentBlock fromJson(Map<String, dynamic> json) {
    final occurrence = json['occurrence'] as int;
    final box = json['box'] == null
        ? null
        : BlockBox.fromJson(json['box'] as Map<String, dynamic>);
    final layout = json['layout'] == null
        ? null
        : BlockBox.fromJson(json['layout'] as Map<String, dynamic>);
    final styles = (json['inlineStyles'] as List? ?? const []).map(
      (v) => InlineTextStyle.fromJson(v as Map<String, dynamic>),
    );
    final ContentBlock block = switch (json['type']) {
      'paragraph' => ParagraphBlock(
        linkDecoration: json['linkDecoration'] == null
            ? null
            : LinkDecoration.fromJson(
                json['linkDecoration'] as Map<String, dynamic>,
              ),
        hasAuthoredFontSize: json['hasAuthoredFontSize'] as bool? ?? false,
        authoredGapEm: (json['authoredGapEm'] as num?)?.toDouble(),
        hangingIndentEm: (json['hangingIndentEm'] as num?)?.toDouble(),
        trailingLabelStart: json['trailingLabelStart'] as int?,
        tableRow: json['tableRow'] == null
            ? null
            : TableRowLayout.fromJson(
                Map<String, Object?>.from(json['tableRow'] as Map),
              ),
        inlineStyles: styles,
        inlineStacks: (json['inlineStacks'] as List? ?? const []).map(
          (v) => InlineStack.fromJson(v as Map<String, dynamic>),
        ),
        inlineRuby: (json['inlineRuby'] as List? ?? const []).map(
          (v) => InlineRuby.fromJson(v as Map<String, dynamic>),
        ),
        box: box,
        layout: layout,
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
        box: box,
        layout: layout,
        media: MediaRef.fromJson(json['media'] as Map<String, dynamic>),
        width: json['width'] as int?,
        height: json['height'] as int?,
        alt: json['alt'] as String?,
        caption: json['caption'] as String?,
        occurrence: occurrence,
      ),
      'heading' => HeadingBlock(
        hasAuthoredFontSize: json['hasAuthoredFontSize'] as bool? ?? false,
        inlineStyles: styles,
        inlineStacks: (json['inlineStacks'] as List? ?? const []).map(
          (v) => InlineStack.fromJson(v as Map<String, dynamic>),
        ),
        inlineRuby: (json['inlineRuby'] as List? ?? const []).map(
          (v) => InlineRuby.fromJson(v as Map<String, dynamic>),
        ),
        box: box,
        layout: layout,
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
      'divider' => DividerBlock(
        occurrence: occurrence,
        box: box,
        layout: layout,
      ),
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
    Iterable<InlineRuby> inlineRuby = const [],
    Iterable<InlineStack> inlineStacks = const [],
    Iterable<InlineTextStyle> inlineStyles = const [],
    BlockBox? box,
    BlockBox? layout,
    bool hasAuthoredFontSize = false,
    this.alignment = ParagraphAlignment.start,
    this.leadingIndent = 0,
    this.authoredGapEm,
    this.hangingIndentEm,
    this.trailingLabelStart,
    this.tableRow,
    this.linkDecoration,
    int occurrence = 0,
  }) : inlineStacks = List.unmodifiable(inlineStacks),
       inlineRuby = List.unmodifiable(inlineRuby),
       inlineStyles = List.unmodifiable(inlineStyles),
       inlineImages = List.unmodifiable(inlineImages),
       text = ContentIdentity.normalizeText(text),
       super(
         occurrence,
         layout: layout,
         box: box,
         hasAuthoredFontSize: hasAuthoredFontSize,
       ) {
    if (linkDecoration != null &&
        (this.text.isEmpty ||
            this.inlineImages.isNotEmpty ||
            this.inlineRuby.isNotEmpty ||
            this.inlineStacks.isNotEmpty ||
            tableRow != null ||
            hangingIndentEm != null ||
            trailingLabelStart != null)) {
      throw ArgumentError('Invalid decorated link paragraph');
    }
    if (authoredGapEm != null &&
        (!authoredGapEm!.isFinite ||
            authoredGapEm! <= 0 ||
            authoredGapEm! > 16 ||
            this.text.isNotEmpty)) {
      throw ArgumentError('Invalid authored gap');
    }
    if (hangingIndentEm != null &&
        (!hangingIndentEm!.isFinite ||
            hangingIndentEm! <= 0 ||
            hangingIndentEm! > 32 ||
            this.text.isEmpty)) {
      throw ArgumentError('Invalid hanging indent');
    }
    if (trailingLabelStart case final start?) {
      final runes = this.text.runes.toList();
      final boundaries = <int>{0};
      var end = 0;
      for (final cluster in this.text.characters) {
        end += cluster.runes.length;
        boundaries.add(end);
      }
      if (start <= 0 ||
          start >= runes.length ||
          runes.length - start > 64 ||
          !boundaries.contains(start) ||
          String.fromCharCodes(runes.skip(start)).trim().isEmpty ||
          runes.skip(start).any((r) => r == 10 || r == 0xfffc) ||
          this.inlineRuby.any((r) => r.end > start) ||
          this.inlineStacks.any((s) => s.end > start)) {
        throw ArgumentError('Invalid trailing label range');
      }
    }
    if (tableRow case final row?) {
      final boundaries = <int>{0};
      var offset = 0;
      for (final cluster in this.text.characters) {
        offset += cluster.runes.length;
        boundaries.add(offset);
      }
      if (row.rightStart >= offset ||
          !boundaries.contains(row.leftEnd) ||
          !boundaries.contains(row.rightStart) ||
          this.text.runes.take(row.leftEnd).any((r) => r == 10) ||
          String.fromCharCodes(
            this.text.runes.take(row.leftEnd),
          ).trim().isEmpty ||
          String.fromCharCodes(
            this.text.runes.skip(row.rightStart),
          ).trim().isEmpty ||
          hangingIndentEm != null ||
          trailingLabelStart != null ||
          authoredGapEm != null ||
          this.inlineImages.isNotEmpty ||
          this.inlineRuby.isNotEmpty ||
          this.inlineStacks.isNotEmpty) {
        throw ArgumentError('Invalid table row');
      }
    }
    validateInlineStacks(
      this.text,
      this.inlineStacks,
      this.inlineRuby.map((r) => (r.start, r.end)),
    );
    validateInlineRuby(this.text, this.inlineRuby);
    validateInlineStyles(this.text, this.inlineStyles);
    validateInlineImages(this.text, this.inlineImages);
    if (leadingIndent < 0 || leadingIndent > 8) {
      throw ArgumentError('Indent must be 0..8 em');
    }
  }
  final String text;

  /// Relative height of explicit blank lines in an authored container.
  final double? authoredGapEm;

  /// LTR continuation inset; the first line remains at the ordinary origin.
  /// Layout metadata only, never a semantic indent or a persisted pixel value.
  final double? hangingIndentEm;

  /// Code point start of a short, right-aligned suffix ending at text.runes.length.
  final int? trailingLabelStart;
  final TableRowLayout? tableRow;
  final LinkDecoration? linkDecoration;
  @override
  final List<InlineImage> inlineImages;
  @override
  final List<InlineRuby> inlineRuby;
  @override
  final List<InlineStack> inlineStacks;
  @override
  final List<InlineTextStyle> inlineStyles;
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
    if (inlineRuby.isNotEmpty)
      ['ruby', inlineRuby.map((r) => r.values).toList()],
  ];
  @override
  Map<String, Object?> get fieldsJson => {
    'text': text,
    if (inlineStacks.isNotEmpty)
      'inlineStacks': inlineStacks.map((s) => s.toJson()).toList(),
    if (inlineRuby.isNotEmpty)
      'inlineRuby': inlineRuby.map((r) => r.toJson()).toList(),
    if (authoredGapEm != null) 'authoredGapEm': authoredGapEm,
    if (hangingIndentEm != null) 'hangingIndentEm': hangingIndentEm,
    if (trailingLabelStart != null) 'trailingLabelStart': trailingLabelStart,
    if (tableRow != null) 'tableRow': tableRow!.toJson(),
    if (linkDecoration != null) 'linkDecoration': linkDecoration!.toJson(),
    if (inlineStyles.isNotEmpty)
      'inlineStyles': inlineStyles.map((s) => s.toJson()).toList(),
    if (inlineImages.isNotEmpty)
      'inlineImages': inlineImages.map((i) => i.toJson()).toList(),
    'alignment': alignment.name,
    'leadingIndent': leadingIndent,
  };
  @override
  ParagraphBlock withOccurrence(int occurrence) => ParagraphBlock(
    hasAuthoredFontSize: hasAuthoredFontSize,
    text: text,
    authoredGapEm: authoredGapEm,
    hangingIndentEm: hangingIndentEm,
    trailingLabelStart: trailingLabelStart,
    tableRow: tableRow,
    linkDecoration: linkDecoration,
    inlineImages: inlineImages,
    inlineRuby: inlineRuby,
    inlineStacks: inlineStacks,
    inlineStyles: inlineStyles,
    box: box,
    layout: layout,
    alignment: alignment,
    leadingIndent: leadingIndent,
    occurrence: occurrence,
  );
  @override
  List<Object?> get values => [
    ...semanticFields,
    inlineStacks,
    inlineImages,
    inlineStyles,
    authoredGapEm,
    hangingIndentEm,
    trailingLabelStart,
    tableRow,
    linkDecoration,
    hasAuthoredFontSize,
    box,
    layout,
    occurrence,
  ];
}

final class ImageBlock extends ContentBlock {
  ImageBlock({
    required this.media,
    BlockBox? box,
    BlockBox? layout,
    this.width,
    this.height,
    String? alt,
    String? caption,
    int occurrence = 0,
  }) : alt = alt == null ? null : ContentIdentity.normalizeText(alt),
       caption = caption == null
           ? null
           : ContentIdentity.normalizeText(caption),
       super(occurrence, layout: layout, box: box) {
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
    box: box,
    layout: layout,
    width: width,
    height: height,
    alt: alt,
    caption: caption,
    occurrence: occurrence,
  );
  @override
  List<Object?> get values => [
    media,
    width,
    height,
    alt,
    caption,
    box,
    layout,
    occurrence,
  ];
}

final class HeadingBlock extends ContentBlock {
  HeadingBlock({
    required String text,
    Iterable<InlineImage> inlineImages = const [],
    Iterable<InlineRuby> inlineRuby = const [],
    Iterable<InlineStack> inlineStacks = const [],
    Iterable<InlineTextStyle> inlineStyles = const [],
    BlockBox? box,
    BlockBox? layout,
    bool hasAuthoredFontSize = false,
    this.level = 1,
    this.alignment = ParagraphAlignment.start,
    int occurrence = 0,
  }) : inlineStacks = List.unmodifiable(inlineStacks),
       inlineRuby = List.unmodifiable(inlineRuby),
       inlineStyles = List.unmodifiable(inlineStyles),
       inlineImages = List.unmodifiable(inlineImages),
       text = nonBlank(ContentIdentity.normalizeText(text), 'heading'),
       super(
         occurrence,
         layout: layout,
         box: box,
         hasAuthoredFontSize: hasAuthoredFontSize,
       ) {
    validateInlineStacks(
      this.text,
      this.inlineStacks,
      this.inlineRuby.map((r) => (r.start, r.end)),
    );
    validateInlineRuby(this.text, this.inlineRuby);
    validateInlineStyles(this.text, this.inlineStyles);
    validateInlineImages(this.text, this.inlineImages);
    if (level < 1 || level > 6) {
      throw ArgumentError('Heading level must be 1..6');
    }
  }
  final String text;
  @override
  final List<InlineImage> inlineImages;
  @override
  final List<InlineRuby> inlineRuby;
  @override
  final List<InlineStack> inlineStacks;
  @override
  final List<InlineTextStyle> inlineStyles;
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
    if (inlineRuby.isNotEmpty)
      ['ruby', inlineRuby.map((r) => r.values).toList()],
  ];
  @override
  Map<String, Object?> get fieldsJson => {
    'text': text,
    if (inlineStacks.isNotEmpty)
      'inlineStacks': inlineStacks.map((s) => s.toJson()).toList(),
    if (inlineRuby.isNotEmpty)
      'inlineRuby': inlineRuby.map((r) => r.toJson()).toList(),
    if (inlineStyles.isNotEmpty)
      'inlineStyles': inlineStyles.map((s) => s.toJson()).toList(),
    if (inlineImages.isNotEmpty)
      'inlineImages': inlineImages.map((i) => i.toJson()).toList(),
    'level': level,
    if (alignment != ParagraphAlignment.start) 'alignment': alignment.name,
  };
  @override
  HeadingBlock withOccurrence(int occurrence) => HeadingBlock(
    hasAuthoredFontSize: hasAuthoredFontSize,
    text: text,
    inlineImages: inlineImages,
    inlineRuby: inlineRuby,
    inlineStacks: inlineStacks,
    inlineStyles: inlineStyles,
    box: box,
    layout: layout,
    level: level,
    alignment: alignment,
    occurrence: occurrence,
  );
  @override
  List<Object?> get values => [
    ...semanticFields,
    inlineStacks,
    inlineImages,
    inlineStyles,
    box,
    layout,
    hasAuthoredFontSize,
    occurrence,
  ];
}

final class DividerBlock extends ContentBlock {
  DividerBlock({int occurrence = 0, BlockBox? box, BlockBox? layout})
    : super(occurrence, layout: layout, box: box);
  @override
  String get kind => 'divider';
  @override
  List<Object?> get semanticFields => const [];
  @override
  Map<String, Object?> get fieldsJson => const {};
  @override
  DividerBlock withOccurrence(int occurrence) =>
      DividerBlock(occurrence: occurrence, box: box, layout: layout);
  @override
  List<Object?> get values => [box, layout, occurrence];
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
