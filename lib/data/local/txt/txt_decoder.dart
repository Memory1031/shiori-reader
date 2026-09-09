import 'dart:convert';
import '../../../domain/content_identity.dart';
import '../../../domain/contracts/local_book_decoder.dart';
import 'gb18030_tables.dart';

TxtEncoding? txtBom(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 239 &&
      bytes[1] == 187 &&
      bytes[2] == 191) {
    return TxtEncoding.utf8;
  }
  if (bytes.length >= 2) {
    if (bytes[0] == 255 && bytes[1] == 254) return TxtEncoding.utf16le;
    if (bytes[0] == 254 && bytes[1] == 255) return TxtEncoding.utf16be;
  }
  return null;
}

String decodeTxt(List<int> bytes, TxtEncoding encoding) {
  try {
    final bom = txtBom(bytes);
    if (bom != null && bom != encoding) throw const FormatException();
    final input = bom == null
        ? bytes
        : bytes.sublist(bom == TxtEncoding.utf8 ? 3 : 2);
    final String text;
    switch (encoding) {
      case TxtEncoding.utf8:
        text = utf8.decode(input, allowMalformed: false);
      case TxtEncoding.utf16le:
      case TxtEncoding.utf16be:
        if (input.length.isOdd) throw const FormatException();
        final le = encoding == TxtEncoding.utf16le;
        text = String.fromCharCodes([
          for (var i = 0; i < input.length; i += 2)
            le ? input[i] | input[i + 1] << 8 : input[i] << 8 | input[i + 1],
        ]);
        ContentIdentity.validateUnicode(text);
      case TxtEncoding.gb18030:
        text = decodeGb18030(input);
    }
    // Control bytes are not book whitespace. Never synthesize U+FFFD.
    if (RegExp(r'[\x00-\x08\x0b\x0e-\x1f\x7f]').hasMatch(text)) {
      throw const FormatException();
    }
    return text;
  } catch (_) {
    throw const LocalParseException(LocalParseProblem.encoding);
  }
}

/// Strict WHATWG GB18030 decoder, including the GBK subset and four-byte
/// Unicode ranges. No replacement/ignore recovery on malformed sequences.
String decodeGb18030(List<int> bytes) {
  final out = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    final first = bytes[i];
    if (first < 0x80) {
      out.writeCharCode(first);
      continue;
    }
    if (first == 0x80) {
      out.writeCharCode(0x20ac);
      continue;
    }
    if (first < 0x81 || first > 0xfe || ++i >= bytes.length) {
      throw const FormatException();
    }
    final second = bytes[i];
    int point;
    if (second >= 0x30 && second <= 0x39) {
      if (i + 2 >= bytes.length) throw const FormatException();
      final third = bytes[++i], fourth = bytes[++i];
      if (third < 0x81 || third > 0xfe || fourth < 0x30 || fourth > 0x39) {
        throw const FormatException();
      }
      final pointer =
          (((first - 0x81) * 10 + second - 0x30) * 126 + third - 0x81) * 10 +
          fourth -
          0x30;
      if ((pointer > 39419 && pointer < 189000) || pointer > 1237575) {
        throw const FormatException();
      }
      if (pointer == 7457) {
        point = 0xe7c7;
      } else {
        var lo = 0, hi = gb18030Ranges.length ~/ 2;
        while (lo + 1 < hi) {
          final mid = (lo + hi) ~/ 2;
          if (gb18030Ranges[mid * 2] <= pointer) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        point = gb18030Ranges[lo * 2 + 1] + pointer - gb18030Ranges[lo * 2];
      }
    } else {
      if (second < 0x40 || second > 0xfe || second == 0x7f) {
        throw const FormatException();
      }
      final pointer =
          (first - 0x81) * 190 + second - (second < 0x7f ? 0x40 : 0x41);
      point = gb18030At(pointer);
      if (point < 0) throw const FormatException();
    }
    out.writeCharCode(point);
  }
  return out.toString();
}

/// Only a byte-order hint, never a detected truth. Sparse ASCII/newline NUL
/// lanes qualify; unmarked all-CJK text without this evidence needs override.
TxtEncoding? txtUtf16Hint(List<int> bytes) {
  if (bytes.length < 8 || bytes.length.isOdd) return null;
  final count = (bytes.length ~/ 2).clamp(0, 2048);
  var even = 0, odd = 0;
  for (var i = 0; i < count; i++) {
    if (bytes[i * 2] == 0) even++;
    if (bytes[i * 2 + 1] == 0) odd++;
  }
  if (odd >= 4 && odd >= count * .3 && even <= count * .15) {
    return TxtEncoding.utf16le;
  }
  if (even >= 4 && even >= count * .3 && odd <= count * .15) {
    return TxtEncoding.utf16be;
  }
  return null;
}

String txtPreviewSample(String text) {
  final length = text.runes.length;
  if (length <= 600) return text;
  final middle = length ~/ 2 - 99;
  final tail = length - 198;
  final chunks = [StringBuffer(), StringBuffer(), StringBuffer()];
  var index = 0;
  for (final point in text.runes) {
    if (index < 198) chunks[0].writeCharCode(point);
    if (index >= middle && index < middle + 198) chunks[1].writeCharCode(point);
    if (index >= tail) chunks[2].writeCharCode(point);
    index++;
  }
  return chunks.map((b) => b.toString()).join('\n⋯\n');
}

/// Full input is validated before presenting its bounded sample. No heuristic
/// can prove an unmarked legacy encoding, so legacy choices need confirmation.
TxtEncodingPreview inspectTxt(List<int> bytes, TxtEncoding? requested) {
  final bom = txtBom(bytes);
  final candidates = requested != null
      ? [requested]
      : bom != null
      ? [bom]
      : [TxtEncoding.utf8, ?txtUtf16Hint(bytes), TxtEncoding.gb18030];
  final samples = <TxtEncoding, String>{};
  String? utf8Text;
  var sameText = true;
  for (final encoding in candidates) {
    try {
      final text = decodeTxt(bytes, encoding);
      if (text.trim().isEmpty) continue;
      if (encoding == TxtEncoding.utf8) {
        utf8Text = text;
      } else if (text != utf8Text) {
        sameText = false;
      }
      samples[encoding] = txtPreviewSample(text);
    } on LocalParseException {
      /* Invalid candidates are never selectable. */
    }
  }
  if (samples.isEmpty) {
    throw const LocalParseException(LocalParseProblem.encoding);
  }
  return TxtEncodingPreview(
    samples,
    detected: requested != null
        ? null
        : bom ?? (utf8Text != null && sameText ? TxtEncoding.utf8 : null),
  );
}
