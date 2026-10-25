import 'dart:convert';
import 'dart:typed_data';

// Self-authored 80x200 color-block image, not a publication asset.
Uint8List plainOrientationJpeg() => base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA0JCgsKCA0LCgsODg0PEyAVExISEyccHhcgLikxMC4p'
  'LSwzOko+MzZGNywtQFdBRkxOUlNSMj5aYVpQYEpRUk//2wBDAQ4ODhMREyYVFSZPNS01T09PT09P'
  'T09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0//wAARCADIAFADASIA'
  'AhEBAxEB/8QAFwABAQEBAAAAAAAAAAAAAAAAAAYFA//EABgQAQADAQAAAAAAAAAAAAAAAAAVZKLh'
  '/8QAFwEBAQEBAAAAAAAAAAAAAAAAAAUEBv/EACARAQAABgIDAQAAAAAAAAAAAAAEBUFDgcEDURMU'
  'ISP/2gAMAwEAAhEDEQA/AOADI7IAATCnTDVDVQZ3bzoAakEABTgJbvAABMKdMNUNVBndvOgBqQQA'
  'FOAlu8AAEwp0w1Q1UGd286AGpBAAU4CW7wAATCnTDVDVQZ3bzoAakEABTgJbvAABMKdMNUNVBndv'
  'OgBqQQAFOAlu8AAEwp0w1Q1UGd286AGpBAAXkLYx0hbGOtYcz5+Tt0/s8vbJhbGOkLYx1rB5+Ts9'
  'nl7ZMLYx1MwtjHV4mWqG5+T79QZ3E8v5/e9MmFsY6QtjHWsNXn5O0H2eXtkwtjHSFsY61g8/J2ez'
  'y9qYBGdqAAJlTJlqhqoM7t50ANSCAApgEt3gAAmVMmWqGqgzu3nQA1IIACmAS3eAACZUyZaoaqDO'
  '7edADUggAKYBLd4AAJlTJlqhqoM7t50ANSCAApgEt3gAAmVMmWqGqgzu3nQA1IIACmAS3eAACZBq'
  'hqoM7t50ANSCAA//2Q==',
);

Uint8List orientationSegment(int orientation, {bool little = true}) {
  final bytes = Uint8List(36);
  bytes.setRange(0, 10, [0xff, 0xe1, 0, 34, 69, 120, 105, 102, 0, 0]);
  final d = ByteData.sublistView(bytes);
  final e = little ? Endian.little : Endian.big;
  d.setUint16(10, little ? 0x4949 : 0x4d4d);
  d.setUint16(12, 42, e);
  d.setUint32(14, 8, e);
  d.setUint16(18, 1, e);
  d.setUint16(20, 0x0112, e);
  d.setUint16(22, 3, e);
  d.setUint32(24, 1, e);
  d.setUint16(28, orientation, e);
  return bytes;
}

Uint8List jpegWithSegments(
  List<Uint8List> segments, {
  bool afterFrame = false,
}) {
  final plain = plainOrientationJpeg();
  var at = 2;
  if (afterFrame) {
    while (at + 3 < plain.length) {
      if (plain[at] != 0xff) throw StateError('Invalid synthetic JPEG');
      if (plain[at + 1] == 0xda) break;
      at += 2 + (plain[at + 2] << 8 | plain[at + 3]);
    }
  }
  return Uint8List.fromList([
    ...plain.take(at),
    for (final segment in segments) ...segment,
    ...plain.skip(at),
  ]);
}
