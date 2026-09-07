import 'dart:typed_data';

/// Self-authored RGB checkerboard PNG. Stored DEFLATE blocks avoid platform IO
/// and external codecs during generation. No bundled or third-party artwork.
Uint8List fixturePng(int width, int height, int seed) {
  if (width < 1 || height < 1 || width > 1024 || height > 1024) {
    throw ArgumentError('Fixture dimensions must be 1..1024');
  }
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // PNG filter: none.
    for (var x = 0; x < width; x++) {
      final color = ((x ~/ 16 + y ~/ 16 + seed) % 2) == 0;
      raw.add([color ? 240 : 70, (seed * 31) & 255, color ? 130 : 210]);
    }
  }
  final pixels = raw.takeBytes();
  final zlib = BytesBuilder(copy: false)..add([0x78, 0x01]);
  for (var offset = 0; offset < pixels.length; offset += 65535) {
    final end = (offset + 65535).clamp(0, pixels.length);
    final length = end - offset;
    zlib.add([
      end == pixels.length ? 1 : 0,
      length & 255,
      length >> 8,
      (~length) & 255,
      ((~length) >> 8) & 255,
    ]);
    zlib.add(Uint8List.sublistView(pixels, offset, end));
  }
  var a = 1;
  var b = 0;
  for (final byte in pixels) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  zlib.add(_u32((b << 16) | a));
  final header = BytesBuilder()
    ..add(_u32(width))
    ..add(_u32(height))
    ..add([8, 2, 0, 0, 0]);
  return (BytesBuilder(copy: false)
        ..add([137, 80, 78, 71, 13, 10, 26, 10])
        ..add(_chunk('IHDR', header.takeBytes()))
        ..add(_chunk('IDAT', zlib.takeBytes()))
        ..add(_chunk('IEND', Uint8List(0))))
      .takeBytes();
}

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
Uint8List _chunk(String type, Uint8List data) {
  final content =
      (BytesBuilder()
            ..add(type.codeUnits)
            ..add(data))
          .takeBytes();
  var crc = 0xffffffff;
  for (final byte in content) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
    }
  }
  return (BytesBuilder()
        ..add(_u32(data.length))
        ..add(content)
        ..add(_u32((crc ^ 0xffffffff) & 0xffffffff)))
      .takeBytes();
}
