import 'dart:typed_data';
import '../../../domain/contracts/local_book_decoder.dart';
import '../txt/txt_decoder.dart';

/// Mask forbidden controls only inside CSS comments before strict decoding.
/// ASCII delimiters can be scanned in UTF-8 or BOM-marked UTF-16 without
/// accepting malformed Unicode. Preserve raw length for stylesheet budgets.
String decodeEpubStylesheet(Uint8List bytes) {
  final bom = txtBom(bytes);
  final encoding = bom ?? TxtEncoding.utf8;
  final wide =
      encoding == TxtEncoding.utf16le || encoding == TxtEncoding.utf16be;
  final littleEndian = encoding == TxtEncoding.utf16le;
  final stride = wide ? 2 : 1;
  final start = bom == null
      ? 0
      : bom == TxtEncoding.utf8
      ? 3
      : 2;
  int unit(int at) => !wide
      ? bytes[at]
      : littleEndian
      ? bytes[at] | bytes[at + 1] << 8
      : bytes[at] << 8 | bytes[at + 1];

  Uint8List? normalized;
  var comment = false;
  var quote = 0;
  for (var at = start; at + stride <= bytes.length; at += stride) {
    final current = unit(at);
    final next = at + 2 * stride <= bytes.length ? unit(at + stride) : -1;
    if (comment) {
      if (current == 0x2a && next == 0x2f) {
        comment = false;
        at += stride;
      } else if (current <= 0x08 ||
          current == 0x0b ||
          current >= 0x0e && current <= 0x1f ||
          current == 0x7f) {
        normalized ??= Uint8List.fromList(bytes);
        normalized[at] = !wide || littleEndian ? 0x20 : 0;
        if (wide) normalized[at + 1] = littleEndian ? 0 : 0x20;
      }
      continue;
    }
    if (current == 0x5c) {
      at += stride;
    } else if (quote != 0) {
      if (current == quote) quote = 0;
    } else if (current == 0x22 || current == 0x27) {
      quote = current;
    } else if (current == 0x2f && next == 0x2a) {
      comment = true;
      at += stride;
    }
  }
  return decodeTxt(normalized ?? bytes, encoding);
}
