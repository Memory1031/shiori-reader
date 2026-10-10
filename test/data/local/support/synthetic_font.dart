import 'dart:typed_data';

/// Self-authored two-glyph TrueType font. ASCII glyphs are simple rectangles;
/// different advances make font selection observable without licensed assets.
Uint8List syntheticFont({int advance = 600}) {
  Uint8List table(int size, void Function(ByteData) fill) {
    final bytes = Uint8List(size);
    fill(ByteData.sublistView(bytes));
    return bytes;
  }

  final tables = <String, Uint8List>{};
  tables['head'] = table(54, (d) {
    d.setUint32(0, 0x00010000);
    d.setUint32(4, 0x00010000);
    d.setUint32(12, 0x5f0f3cf5);
    d.setUint16(18, 1000);
    d.setInt16(40, advance - 100);
    d.setInt16(42, 700);
    d.setUint16(46, 8);
    d.setInt16(48, 2);
  });
  tables['hhea'] = table(36, (d) {
    d.setUint32(0, 0x00010000);
    d.setInt16(4, 800);
    d.setInt16(6, -200);
    d.setUint16(10, advance);
    d.setInt16(16, advance - 100);
    d.setInt16(18, 1);
    d.setUint16(34, 2);
  });
  tables['maxp'] = table(32, (d) {
    d.setUint32(0, 0x00010000);
    d.setUint16(4, 2);
    d.setUint16(6, 4);
    d.setUint16(8, 1);
    d.setUint16(14, 2);
  });
  tables['hmtx'] = table(8, (d) {
    d.setUint16(0, advance);
    d.setUint16(4, advance);
  });
  tables['glyf'] = table(34, (d) {
    d.setInt16(0, 1);
    d.setInt16(6, advance - 100);
    d.setInt16(8, 700);
    d.setUint16(10, 3);
    for (var i = 14; i < 18; i++) {
      d.setUint8(i, 1);
    }
    d.setInt16(20, advance - 100);
    d.setInt16(24, -(advance - 100));
    d.setInt16(30, 700);
  });
  tables['loca'] = table(6, (d) {
    d.setUint16(4, 17);
  });
  tables['cmap'] = table(234, (d) {
    d.setUint16(2, 1);
    d.setUint16(4, 3);
    d.setUint16(6, 1);
    d.setUint32(8, 12);
    const p = 12;
    d.setUint16(p, 4);
    d.setUint16(p + 2, 222);
    d.setUint16(p + 6, 4);
    d.setUint16(p + 8, 4);
    d.setUint16(p + 10, 1);
    d.setUint16(p + 14, 126);
    d.setUint16(p + 16, 65535);
    d.setUint16(p + 20, 32);
    d.setUint16(p + 22, 65535);
    d.setUint16(p + 26, 1);
    d.setUint16(p + 28, 4);
    for (var i = 0; i < 95; i++) {
      d.setUint16(p + 32 + i * 2, 1);
    }
  });
  tables['post'] = table(32, (d) {
    d.setUint32(0, 0x00030000);
  });
  tables['OS/2'] = table(78, (d) {
    d.setInt16(2, advance);
    d.setUint16(4, 400);
    d.setUint16(6, 5);
    d.setUint16(62, 64);
    d.setUint16(64, 32);
    d.setUint16(66, 126);
    d.setInt16(68, 800);
    d.setInt16(70, -200);
    d.setUint16(74, 800);
    d.setUint16(76, 200);
  });
  final names = {
    1: 'Shiori Synthetic',
    2: 'Regular',
    4: 'Shiori Synthetic',
    6: 'ShioriSynthetic',
  };
  final strings = BytesBuilder();
  final records = <List<int>>[];
  for (final entry in names.entries) {
    final start = strings.length;
    for (final c in entry.value.codeUnits) {
      strings.add([c >> 8, c & 255]);
    }
    records.add([entry.key, entry.value.length * 2, start]);
  }
  tables['name'] = table(6 + records.length * 12 + strings.length, (d) {
    d.setUint16(2, records.length);
    d.setUint16(4, 6 + records.length * 12);
    for (var i = 0; i < records.length; i++) {
      final p = 6 + i * 12;
      d.setUint16(p, 3);
      d.setUint16(p + 2, 1);
      d.setUint16(p + 4, 0x409);
      d.setUint16(p + 6, records[i][0]);
      d.setUint16(p + 8, records[i][1]);
      d.setUint16(p + 10, records[i][2]);
    }
    Uint8List.view(
      d.buffer,
    ).setRange(6 + records.length * 12, d.lengthInBytes, strings.takeBytes());
  });
  int checksum(Uint8List b) {
    final padded = Uint8List((b.length + 3) & ~3)..setRange(0, b.length, b);
    final d = ByteData.sublistView(padded);
    var result = 0;
    for (var i = 0; i < padded.length; i += 4) {
      result = (result + d.getUint32(i)) & 0xffffffff;
    }
    return result;
  }

  final sorted = tables.keys.toList()..sort();
  final length =
      12 +
      sorted.length * 16 +
      tables.values.fold<int>(0, (n, b) => n + ((b.length + 3) & ~3));
  final result = Uint8List(length), data = ByteData.sublistView(result);
  data.setUint32(0, 0x00010000);
  data.setUint16(4, sorted.length);
  data.setUint16(6, 128);
  data.setUint16(8, 3);
  data.setUint16(10, sorted.length * 16 - 128);
  var offset = 12 + sorted.length * 16, head = 0;
  for (var i = 0; i < sorted.length; i++) {
    final name = sorted[i], b = tables[name]!;
    final p = 12 + i * 16;
    result.setRange(p, p + 4, name.codeUnits);
    data.setUint32(p + 4, checksum(b));
    data.setUint32(p + 8, offset);
    data.setUint32(p + 12, b.length);
    result.setRange(offset, offset + b.length, b);
    if (name == 'head') {
      head = offset;
    }
    offset += (b.length + 3) & ~3;
  }
  data.setUint32(head + 8, (0xb1b0afba - checksum(result)) & 0xffffffff);
  return result;
}
