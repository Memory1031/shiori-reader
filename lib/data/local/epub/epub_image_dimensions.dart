import 'dart:typed_data';

/// Reads raster headers without allocating decoded pixels. Broken or unsupported
/// headers leave dimensions unknown so the reader can use its normal fallback.
({int width, int height})? epubImageDimensions(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  bool tag(int at, String value) =>
      at + value.length <= bytes.length &&
      List.generate(
        value.length,
        (i) => bytes[at + i] == value.codeUnitAt(i),
      ).every((matches) => matches);
  int le24(int at) => bytes[at] | bytes[at + 1] << 8 | bytes[at + 2] << 16;
  ({int width, int height})? valid(int w, int h) =>
      w > 0 && h > 0 && w <= 32768 && h <= 32768 && w * h <= 100000000
      ? (width: w, height: h)
      : null;
  if (bytes.length >= 24 &&
      bytes[0] == 137 &&
      tag(1, 'PNG\r\n\x1a\n') &&
      tag(12, 'IHDR')) {
    return valid(data.getUint32(16), data.getUint32(20));
  }
  if (bytes.length >= 10 && (tag(0, 'GIF87a') || tag(0, 'GIF89a'))) {
    return valid(
      data.getUint16(6, Endian.little),
      data.getUint16(8, Endian.little),
    );
  }
  if (bytes.length >= 12 && tag(0, 'RIFF') && tag(8, 'WEBP')) {
    final end = data.getUint32(4, Endian.little) + 8;
    if (end > bytes.length) return null;
    for (var at = 12; at + 8 <= end;) {
      final length = data.getUint32(at + 4, Endian.little);
      final start = at + 8;
      if (start + length > end) return null;
      if (tag(at, 'VP8X') && length >= 10) {
        return valid(le24(start + 4) + 1, le24(start + 7) + 1);
      }
      if (tag(at, 'VP8L') && length >= 5 && bytes[start] == 0x2f) {
        final bits = data.getUint32(start + 1, Endian.little);
        return valid((bits & 0x3fff) + 1, ((bits >> 14) & 0x3fff) + 1);
      }
      if (tag(at, 'VP8 ') &&
          length >= 10 &&
          bytes[start] & 1 == 0 &&
          tag(start + 3, '\x9d\x01\x2a')) {
        return valid(
          data.getUint16(start + 6, Endian.little) & 0x3fff,
          data.getUint16(start + 8, Endian.little) & 0x3fff,
        );
      }
      at = start + length + (length & 1);
    }
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    var at = 2;
    while (at < bytes.length) {
      if (bytes[at++] != 0xff) return null;
      while (at < bytes.length && bytes[at] == 0xff) {
        at++;
      }
      if (at >= bytes.length) return null;
      final marker = bytes[at++];
      if (marker == 0xda || marker == 0xd9 || marker == 0) return null;
      if (marker == 1 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      if (at + 2 > bytes.length) return null;
      final length = data.getUint16(at);
      if (length < 2 || at + length > bytes.length) return null;
      if ({
        0xc0,
        0xc1,
        0xc2,
        0xc3,
        0xc5,
        0xc6,
        0xc7,
        0xc9,
        0xca,
        0xcb,
        0xcd,
        0xce,
        0xcf,
      }.contains(marker)) {
        if (length < 8) return null;
        return valid(data.getUint16(at + 5), data.getUint16(at + 3));
      }
      at += length;
    }
  }
  return null;
}

/// Header-only display dimensions for bounded JPEG EXIF orientation. Encoded
/// dimensions remain available through [epubImageDimensions]. Never transforms
/// image bytes; the platform decoder owns orientation of the displayed pixels.
/// Malformed or ambiguous EXIF leaves display dimensions unknown.
({int width, int height})? epubDisplayImageDimensions(Uint8List bytes) {
  final size = epubImageDimensions(bytes);
  if (size == null ||
      bytes.length < 2 ||
      bytes[0] != 0xff ||
      bytes[1] != 0xd8) {
    return size;
  }
  final orientation = _jpegOrientation(bytes);
  if (orientation == null) return null;
  return orientation >= 5 ? (width: size.height, height: size.width) : size;
}

int? _jpegOrientation(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var at = 2, markers = 0;
  int? orientation;
  // No entropy data, thumbnails, recursive IFDs, or pixel decoding are read.
  while (at < bytes.length) {
    if (at >= 1024 * 1024 || ++markers > 256) return null;
    if (bytes[at++] != 0xff) return null;
    while (at < bytes.length && bytes[at] == 0xff) {
      if (at >= 1024 * 1024) return null;
      at++;
    }
    if (at >= bytes.length) return null;
    final marker = bytes[at++];
    if (marker == 0xda || marker == 0xd9) return orientation ?? 1;
    if (marker == 0 || marker == 0xd8) return null;
    if (marker == 1 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (at + 2 > bytes.length) return null;
    final length = data.getUint16(at);
    final end = at + length;
    if (length < 2 || end > bytes.length || end > 1024 * 1024) return null;
    final start = at + 2;
    if (marker == 0xe1 &&
        length >= 8 &&
        bytes[start] == 0x45 &&
        bytes[start + 1] == 0x78 &&
        bytes[start + 2] == 0x69 &&
        bytes[start + 3] == 0x66 &&
        bytes[start + 4] == 0 &&
        bytes[start + 5] == 0) {
      final exif = _exifOrientation(data, start + 6, end);
      if (!exif.valid ||
          orientation != null &&
              exif.orientation != null &&
              orientation != exif.orientation) {
        return null;
      }
      orientation = exif.orientation ?? orientation;
    }
    at = end;
  }
  return orientation ?? 1;
}

({bool valid, int? orientation}) _exifOrientation(
  ByteData data,
  int tiff,
  int end,
) {
  const invalid = (valid: false, orientation: null);
  if (end - tiff < 8) return invalid;
  final order = data.getUint16(tiff);
  if (order != 0x4949 && order != 0x4d4d) return invalid;
  final endian = order == 0x4949 ? Endian.little : Endian.big;
  if (data.getUint16(tiff + 2, endian) != 42) return invalid;
  final offset = data.getUint32(tiff + 4, endian);
  if (offset < 8 || offset > end - tiff - 2) return invalid;
  final directory = tiff + offset;
  final count = data.getUint16(directory, endian);
  if (count > 1024 || directory + 2 + count * 12 + 4 > end) return invalid;
  int? orientation;
  for (var i = 0; i < count; i++) {
    final entry = directory + 2 + i * 12;
    if (data.getUint16(entry, endian) != 0x0112) continue;
    if (data.getUint16(entry + 2, endian) != 3 ||
        data.getUint32(entry + 4, endian) != 1) {
      return invalid;
    }
    final value = data.getUint16(entry + 8, endian);
    if (value < 1 || value > 8 || orientation != null && orientation != value) {
      return invalid;
    }
    orientation = value;
  }
  return (valid: true, orientation: orientation);
}
