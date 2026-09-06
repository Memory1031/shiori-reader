import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'package:image/image.dart' as image;

import 'transport.dart';

typedef Json = Map<String, dynamic>;
const bookId = 31607;
const volumeId = 44117;
const chapterId = 309555;
const bookTitle = '桌游咖（玩乐关系/玩玩的戀愛關係）';
const author = '葵关南';

Json object(Object? value) {
  require(value is Json, 'invalid_object');
  return value as Json;
}

List<Json> rows(Json data) {
  require(data['list'] is List, 'invalid_list');
  return (data['list'] as List<dynamic>).map(object).toList();
}

Json envelope(Object? value) {
  final json = object(value);
  require(json['code'] == 0, 'business_status_rejected');
  return object(json['data']);
}

void assertBook(Json data) {
  require(
    data['book_id'] == bookId &&
        data['title'] == bookTitle &&
        data['author_name'] == author,
    'book_identity_mismatch',
  );
}

Json selectTarget(List<Json> items, String key, int id) {
  final found = items.where((row) => row[key] == id).toList();
  require(found.length == 1, 'target_missing_or_duplicated');
  return found.single;
}

void assertChapter(Json data) {
  require(
    data['book_id'] == bookId &&
        data['volume_id'] == volumeId &&
        data['chapter_id'] == chapterId,
    'chapter_identity_mismatch',
  );
  require(data['locked'] == 0, 'chapter_access_unverified');
}

void assertSingleCatalogPage(Json data, String key) {
  final pagination = object(data['pagination']);
  final items = rows(data);
  require(
    pagination['page'] == 1 &&
        pagination['page_count'] == 1 &&
        pagination['total'] == items.length,
    'catalog_shape_changed',
  );
  require(
    items.every((row) => row[key] is int && (row[key] as int) > 0) &&
        items.map((row) => row[key]).toSet().length == items.length,
    'catalog_identity_invalid',
  );
}

class BodyEvidence {
  BodyEvidence(this.statistics, this.imageSources);
  final Json statistics;
  // Ephemeral only: never serialize this list or include it in errors.
  final List<String> imageSources;
}

BodyEvidence inspectBody(String bodyHtml, String bodyText) {
  require(
    bodyText.trim().isNotEmpty && bodyHtml.trim().isNotEmpty,
    'empty_body',
  );
  final document = html.parseFragment(bodyHtml);
  final paragraphs = document.querySelectorAll('p');
  final textParagraphs = paragraphs.where((p) => p.text.trim().isNotEmpty);
  require(textParagraphs.isNotEmpty, 'empty_semantic_text');
  final images = document.querySelectorAll('img');
  require(images.isNotEmpty, 'body_image_missing');
  final sources = images.map((img) => img.attributes['src'] ?? '').toList();
  require(sources.every((src) => src.isNotEmpty), 'image_src_missing');
  return BodyEvidence({
    'htmlCodeUnits': bodyHtml.length,
    'textCodeUnits': bodyText.length,
    'textUtf8Bytes': utf8.encode(bodyText).length,
    'paragraphCount': paragraphs.length,
    'nonemptyTextParagraphCount': textParagraphs.length,
    'imageCount': images.length,
    'rubyCount': document.querySelectorAll('ruby').length,
  }, sources);
}

BodyEvidence chapterBody(Json data) {
  assertChapter(data);
  // render_preview alone is never evidence of a full chapter.
  final snapshot = object(data['body_snapshot']);
  require(
    snapshot['body_html'] is String && snapshot['body_text'] is String,
    'body_snapshot_missing',
  );
  return inspectBody(
    snapshot['body_html'] as String,
    snapshot['body_text'] as String,
  );
}

Json decodeIllustration(Uint8List bytes, String mime) {
  require({'image/jpeg', 'image/png'}.contains(mime), 'image_mime_rejected');
  try {
    // JpegDecoder.startDecode calls readInfo, which allocates coefficient
    // buffers. Bound all frame headers BEFORE even calling that API.
    final expectedFormat = mime == 'image/jpeg'
        ? image.ImageFormat.jpg
        : image.ImageFormat.png;
    final image.Decoder decoder = mime == 'image/jpeg'
        ? image.JpegDecoder()
        : image.PngDecoder();
    require(decoder.isValidFile(bytes), 'image_mime_mismatch');
    if (mime == 'image/jpeg') {
      _boundJpegFrames(bytes);
    } else {
      require(
        bytes.length >= 33 && ascii.decode(bytes.sublist(12, 16)) == 'IHDR',
        'image_header_invalid',
      );
      final header = ByteData.sublistView(bytes);
      _boundDimensions(header.getUint32(16), header.getUint32(20));
    }
    final info = decoder.startDecode(bytes);
    require(
      info != null &&
          info.width > 0 &&
          info.height > 0 &&
          info.width * info.height <= 20000000 &&
          info.numFrames == 1,
      'image_dimensions_rejected',
    );
    final decoded = decoder.decodeFrame(0);
    require(
      decoded != null &&
          decoded.width == info!.width &&
          decoded.height == info.height,
      'image_decode_failed',
    );
    return {
      'mime': mime,
      'format': expectedFormat.name,
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'width': decoded!.width,
      'height': decoded.height,
      'decoded': true,
      'decoder': 'package:image (pure Dart)',
    };
  } on ProbeFailure {
    rethrow;
  } catch (_) {
    throw const ProbeFailure('image_decode_failed');
  }
}

void _boundDimensions(int width, int height) {
  require(
    width > 0 && height > 0 && width * height <= 20000000,
    'image_dimensions_rejected',
  );
}

void _boundJpegFrames(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 2;
  var frames = 0;
  while (offset < bytes.length) {
    if (bytes[offset++] != 0xff) continue;
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    require(offset < bytes.length, 'image_header_invalid');
    final marker = bytes[offset++];
    if (marker == 0xd9) break;
    if (marker == 0 || marker == 1 || (marker >= 0xd0 && marker <= 0xd7)) {
      continue;
    }
    require(offset + 2 <= bytes.length, 'image_header_invalid');
    final length = data.getUint16(offset);
    require(
      length >= 2 && offset + length <= bytes.length,
      'image_header_invalid',
    );
    if ({0xc0, 0xc1, 0xc2}.contains(marker)) {
      frames++;
      require(length >= 8 && frames == 1, 'image_header_invalid');
      _boundDimensions(data.getUint16(offset + 5), data.getUint16(offset + 3));
      // Avoid unusual sampling/component layouts in this minimal probe.
      final components = bytes[offset + 7];
      require(
        bytes[offset + 2] == 8 &&
            {1, 3, 4}.contains(components) &&
            length == 8 + 3 * components,
        'image_header_invalid',
      );
      for (var c = 0; c < components; c++) {
        final sampling = bytes[offset + 9 + c * 3];
        require(
          (sampling >> 4) >= 1 &&
              (sampling >> 4) <= 2 &&
              (sampling & 15) >= 1 &&
              (sampling & 15) <= 2,
          'image_header_invalid',
        );
      }
    }
    offset += length;
  }
  require(frames == 1, 'image_header_invalid');
}
