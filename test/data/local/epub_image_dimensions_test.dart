import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_image_dimensions.dart';

void main() {
  Uint8List webp(String tag, List<int> payload) => Uint8List.fromList([
    ...'RIFF'.codeUnits,
    12 + payload.length + (payload.length & 1),
    0,
    0,
    0,
    ...'WEBP'.codeUnits,
    ...tag.codeUnits,
    payload.length,
    0,
    0,
    0,
    ...payload,
    if (payload.length.isOdd) 0,
  ]);
  final fixtures = <String, Uint8List>{
    'PNG': Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      ...'IHDR'.codeUnits,
      0,
      0,
      1,
      144,
      0,
      0,
      3,
      132,
    ]),
    'GIF': Uint8List.fromList([...'GIF89a'.codeUnits, 144, 1, 132, 3]),
    'JPEG baseline': Uint8List.fromList([
      255,
      216,
      255,
      224,
      0,
      4,
      0,
      0,
      255,
      192,
      0,
      11,
      8,
      3,
      132,
      1,
      144,
      1,
      1,
      17,
      0,
    ]),
    'JPEG progressive': Uint8List.fromList([
      255,
      216,
      255,
      194,
      0,
      11,
      8,
      3,
      132,
      1,
      144,
      1,
      1,
      17,
      0,
    ]),
    'WebP extended': webp('VP8X', [0, 0, 0, 0, 143, 1, 0, 131, 3, 0]),
    'WebP lossy': webp('VP8 ', [0, 0, 0, 157, 1, 42, 144, 1, 132, 3]),
    'WebP lossless': webp('VP8L', [47, 143, 193, 224, 0]),
  };
  for (final entry in fixtures.entries) {
    test('${entry.key} header supplies tall image dimensions', () {
      expect(epubImageDimensions(entry.value), (width: 400, height: 900));
    });
    test('${entry.key} truncated header stays unknown without throwing', () {
      for (var length = 0; length < entry.value.length; length++) {
        expect(
          epubImageDimensions(Uint8List.sublistView(entry.value, 0, length)),
          isNull,
        );
      }
    });
  }
  test('zero, excessive and malformed dimensions stay unknown', () {
    expect(
      epubImageDimensions(
        Uint8List.fromList([...'GIF89a'.codeUnits, 0, 0, 1, 0]),
      ),
      isNull,
    );
    expect(
      epubImageDimensions(
        Uint8List.fromList([...'GIF89a'.codeUnits, 255, 255, 255, 255]),
      ),
      isNull,
    );
    expect(
      epubImageDimensions(Uint8List.fromList([255, 216, 255, 224, 0, 0])),
      isNull,
    );
  });
}
