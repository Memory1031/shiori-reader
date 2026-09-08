import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart' show getCrc32;
import '../../../domain/contracts/local_book_decoder.dart';

Never invalidZip() =>
    throw const LocalParseException(LocalParseProblem.invalid);
Never zipLimit() => throw const LocalParseException(LocalParseProblem.tooLarge);

/// A bounded, read-only ZIP view. Never extracts archive paths to disk.
/// Supports single-disk, non-ZIP64 stored/deflate EPUB entries only.
class EpubZip {
  EpubZip(this.bytes) : data = ByteData.sublistView(bytes) {
    _index();
  }
  static const maxEntries = 4096,
      maxEntry = 16 * 1024 * 1024,
      maxExpanded = 256 * 1024 * 1024,
      maxRatio = 200;
  final Uint8List bytes;
  final ByteData data;
  final entries = <String, ZipEntry>{};
  int u16(int at) => data.getUint16(at, Endian.little);
  int u32(int at) => data.getUint32(at, Endian.little);
  void bounds(int at, int length) {
    if (at < 0 || length < 0 || at + length > bytes.length) invalidZip();
  }

  void _index() {
    if (bytes.length < 22) invalidZip();
    var end = bytes.length - 22;
    final min = (bytes.length - 65557).clamp(0, bytes.length);
    while (end >= min &&
        (u32(end) != 0x06054b50 || end + 22 + u16(end + 20) != bytes.length)) {
      end--;
    }
    if (end < min || u16(end + 4) != 0 || u16(end + 6) != 0) invalidZip();
    final count = u16(end + 10),
        centralSize = u32(end + 12),
        central = u32(end + 16);
    if (count == 0 || count != u16(end + 8)) invalidZip();
    if (count > maxEntries) zipLimit();
    if (central + centralSize != end) invalidZip();
    var at = central, total = 0;
    final spans = <(int, int)>[];
    for (var i = 0; i < count; i++) {
      bounds(at, 46);
      if (u32(at) != 0x02014b50) invalidZip();
      final flags = u16(at + 8), method = u16(at + 10), crc = u32(at + 16);
      final packed = u32(at + 20), size = u32(at + 24);
      final nameSize = u16(at + 28),
          extraSize = u16(at + 30),
          commentSize = u16(at + 32);
      final local = u32(at + 42), mode = u32(at + 38) >> 16;
      if (flags & 1 != 0) {
        throw const LocalParseException(LocalParseProblem.drm);
      }
      if (flags & ~0x080e != 0 ||
          (method != 0 && method != 8) ||
          u16(at + 34) != 0 ||
          mode & 0xf000 == 0xa000) {
        invalidZip();
      }
      if (size > maxEntry ||
          (total += size) > maxExpanded ||
          size > (packed + 1024) * maxRatio) {
        zipLimit();
      }
      bounds(at + 46, nameSize + extraSize + commentSize);
      final name = utf8.decode(bytes.sublist(at + 46, at + 46 + nameSize));
      _safeName(name);
      if (entries.containsKey(name)) invalidZip();
      // Refuse Zip64 even when only an extra field advertises it.
      var extra = at + 46 + nameSize;
      final extraEnd = extra + extraSize;
      while (extra < extraEnd) {
        if (extra + 4 > extraEnd || u16(extra) == 1) invalidZip();
        extra += 4 + u16(extra + 2);
        if (extra > extraEnd) invalidZip();
      }
      bounds(local, 30);
      if (u32(local) != 0x04034b50 ||
          u16(local + 6) != flags ||
          u16(local + 8) != method) {
        invalidZip();
      }
      final localName = u16(local + 26), localExtra = u16(local + 28);
      bounds(local + 30, localName + localExtra);
      if (utf8.decode(bytes.sublist(local + 30, local + 30 + localName)) !=
          name) {
        invalidZip();
      }
      if (flags & 8 == 0 &&
          (u32(local + 14) != crc ||
              u32(local + 18) != packed ||
              u32(local + 22) != size)) {
        invalidZip();
      }
      final body = local + 30 + localName + localExtra;
      if (body + packed > central) invalidZip();
      spans.add((local, body + packed));
      entries[name] = ZipEntry(body, packed, size, method, crc);
      at += 46 + nameSize + extraSize + commentSize;
    }
    if (at != end) invalidZip();
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < spans.length; i++) {
      if (spans[i].$1 < spans[i - 1].$2) invalidZip();
    }
  }

  Uint8List read(String name, {int limit = maxEntry}) {
    final entry = entries[name];
    if (entry == null) invalidZip();
    if (entry.size > limit) zipLimit();
    final input = Uint8List.sublistView(
      bytes,
      entry.offset,
      entry.offset + entry.packed,
    );
    final sink = _LimitedBytes(entry.size);
    if (entry.method == 0) {
      sink.add(input);
    } else {
      final decoder = ZLibDecoder(raw: true).startChunkedConversion(sink);
      // Enforce actual output on every zlib callback, not only declared sizes.
      for (var at = 0; at < input.length; at += 1024) {
        decoder.add(
          Uint8List.sublistView(input, at, (at + 1024).clamp(0, input.length)),
        );
      }
      decoder.close();
    }
    final value = sink.bytes.takeBytes();
    if (value.length != entry.size || getCrc32(value) != entry.crc) {
      invalidZip();
    }
    return value;
  }

  static void _safeName(String name) {
    if (name.isEmpty ||
        name.length > 1024 ||
        name.startsWith('/') ||
        name.contains('\\') ||
        name.contains(':') ||
        name.contains('\x00')) {
      invalidZip();
    }
    final parts = name.split('/');
    if (parts.any((p) => p == '..' || p == '.') ||
        parts.take(parts.length - 1).contains('')) {
      invalidZip();
    }
  }
}

final class ZipEntry {
  const ZipEntry(this.offset, this.packed, this.size, this.method, this.crc);
  final int offset, packed, size, method, crc;
}

class _LimitedBytes extends ByteConversionSinkBase {
  _LimitedBytes(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > limit) zipLimit();
    bytes.add(chunk);
  }

  @override
  void close() {}
}
