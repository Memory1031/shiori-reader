import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_image_dimensions.dart';
import 'support/oriented_jpeg.dart';

void main() {
  test('EXIF changes display axes, never encoded dimensions or bytes', () {
    for (final little in [true, false]) {
      for (var orientation = 1; orientation <= 8; orientation++) {
        final bytes = jpegWithSegments([
          orientationSegment(orientation, little: little),
        ]);
        final before = bytes.toList();
        expect(epubImageDimensions(bytes), (width: 80, height: 200));
        expect(
          epubDisplayImageDimensions(bytes),
          orientation >= 5
              ? (width: 200, height: 80)
              : (width: 80, height: 200),
        );
        expect(bytes, before);
      }
    }
    expect(epubDisplayImageDimensions(plainOrientationJpeg()), (
      width: 80,
      height: 200,
    ));
    expect(
      epubDisplayImageDimensions(
        jpegWithSegments([orientationSegment(8)], afterFrame: true),
      ),
      (width: 200, height: 80),
    );
  });
  test('malformed and conflicting metadata never becomes a confident fit', () {
    final badOffset = orientationSegment(6);
    ByteData.sublistView(badOffset).setUint32(14, 0xffffffff, Endian.little);
    final badType = orientationSegment(6);
    ByteData.sublistView(badType).setUint16(22, 4, Endian.little);
    final badCount = orientationSegment(6);
    ByteData.sublistView(badCount).setUint32(24, 2, Endian.little);
    final badEntries = orientationSegment(6);
    ByteData.sublistView(badEntries).setUint16(18, 0xffff, Endian.little);
    final badOrder = orientationSegment(6)..[10] = 0;
    for (final segments in [
      [badOffset],
      [badType],
      [badCount],
      [badEntries],
      [badOrder],
      [orientationSegment(0)],
      [orientationSegment(9)],
      [orientationSegment(6), orientationSegment(8)],
    ]) {
      final bytes = jpegWithSegments(segments);
      expect(epubImageDimensions(bytes), (width: 80, height: 200));
      expect(epubDisplayImageDimensions(bytes), isNull);
    }
    expect(
      epubDisplayImageDimensions(
        jpegWithSegments([orientationSegment(6), orientationSegment(6)]),
      ),
      (width: 200, height: 80),
    );
    final tooManyMarkers = jpegWithSegments([
      for (var i = 0; i < 257; i++) Uint8List.fromList([0xff, 0xee, 0, 2]),
    ]);
    expect(epubImageDimensions(tooManyMarkers), (width: 80, height: 200));
    expect(epubDisplayImageDimensions(tooManyMarkers), isNull);
    final full = jpegWithSegments([orientationSegment(6)]);
    for (var end = 0; end < full.length; end++) {
      expect(
        () => epubDisplayImageDimensions(Uint8List.sublistView(full, 0, end)),
        returnsNormally,
      );
    }
  });
}
