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
  var text = _decodeText(bytes, encoding);
  // Preserve the shared EPUB/resource decoder's existing double-BOM behavior.
  if (txtBom(bytes) == TxtEncoding.utf8 && text.startsWith('\ufeff')) {
    text = text.substring(1);
  }
  if (_resourceControls.hasMatch(text)) {
    throw const LocalParseException(LocalParseProblem.encoding);
  }
  return text;
}

final _resourceControls = RegExp(r'[\x00-\x08\x0b\x0e-\x1f\x7f]');
final _txtControls = RegExp(r'[\x01-\x08\x0e-\x1f\x7f]');

/// Keep source coordinates. Check NUL after decoding, not on UTF-16 bytes.
String decodeTxtSource(List<int> bytes, TxtEncoding encoding) {
  final text = _decodeText(bytes, encoding);
  if (text.contains('\x00')) {
    throw const LocalParseException(LocalParseProblem.encoding);
  }
  return text;
}

/// Normalize separators before filtering so CR + control + LF cannot become
/// a new CRLF pair. FF, TAB and Unicode formatting characters stay intact.
String cleanTxtText(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\x0b', '\n')
    .replaceAll(_txtControls, '');

String _decodeText(List<int> bytes, TxtEncoding encoding) {
  try {
    final bom = txtBom(bytes);
    if (bom != null && bom != encoding) throw const FormatException();
    switch (encoding) {
      case TxtEncoding.utf8:
        // Dart strips the first UTF-8 BOM itself; the next FEFF is content.
        return utf8.decode(bytes, allowMalformed: false);
      case TxtEncoding.utf16le:
      case TxtEncoding.utf16be:
        if (bytes.length.isOdd) throw const FormatException();
        final le = encoding == TxtEncoding.utf16le;
        final text = String.fromCharCodes([
          for (var i = bom == null ? 0 : 2; i < bytes.length; i += 2)
            le ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
        ]);
        ContentIdentity.validateUnicode(text);
        return text;
      case TxtEncoding.gb18030:
        return decodeGb18030(bytes);
    }
  } on FormatException {
    throw const LocalParseException(LocalParseProblem.encoding);
  } on ArgumentError {
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

/// Use evidence from the entire file. When both lanes have strong evidence,
/// validate both byte orders instead of choosing by a small difference.
List<TxtEncoding> txtUtf16Candidates(List<int> bytes) {
  if (bytes.length < 8 || bytes.length.isOdd) return const [];
  final count = bytes.length ~/ 2;
  var even = 0, odd = 0;
  for (var i = 0; i < count; i++) {
    if (bytes[i * 2] == 0) even++;
    if (bytes[i * 2 + 1] == 0) odd++;
  }
  final le = odd >= 4 && odd >= count * .3;
  final be = even >= 4 && even >= count * .3;
  return [
    if (le && (be || even <= count * .15)) TxtEncoding.utf16le,
    if (be && (le || odd <= count * .15)) TxtEncoding.utf16be,
  ];
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

/// Full input is validated before automatic selection or preview. Explicit
/// overrides retain the confirmation contract; review also shows auto choices.
TxtEncodingPreview inspectTxt(
  List<int> bytes,
  TxtEncoding? requested, {
  bool reviewText = false,
}) {
  final bom = txtBom(bytes);
  final texts = <TxtEncoding, String>{};
  var empty = false;
  void inspect(TxtEncoding encoding) {
    try {
      final text = cleanTxtText(decodeTxtSource(bytes, encoding));
      if (text.trim().isEmpty) {
        empty = true;
      } else {
        texts[encoding] = text;
      }
    } on LocalParseException {
      /* Invalid candidates are never selectable. */
    }
  }

  if (requested != null || bom != null) {
    inspect(requested ?? bom!);
  } else {
    inspect(TxtEncoding.utf8);
    // Empty but valid UTF-8 is not evidence for a different encoding.
    if (empty) throw const LocalParseException(LocalParseProblem.invalid);
    if (texts.isNotEmpty && !reviewText) {
      return TxtEncodingPreview({
        TxtEncoding.utf8: txtPreviewSample(texts[TxtEncoding.utf8]!),
      }, detected: TxtEncoding.utf8);
    }
    for (final encoding in txtUtf16Candidates(bytes)) {
      inspect(encoding);
    }
    inspect(TxtEncoding.gb18030);
  }
  if (texts.isEmpty) {
    throw LocalParseException(
      empty ? LocalParseProblem.invalid : LocalParseProblem.encoding,
    );
  }
  final samples = texts.map(
    (key, text) => MapEntry(key, txtPreviewSample(text)),
  );
  if (texts.length == 2 && samples.values.first == samples.values.last) {
    // Make a difference outside the head/middle/tail windows visible.
    final left = texts.values.first, right = texts.values.last;
    if (left != right) {
      final a = RuneIterator(left), b = RuneIterator(right);
      var index = 0;
      while (a.moveNext() && b.moveNext() && a.current == b.current) {
        index++;
      }
      final start = (index - 48).clamp(0, index);
      samples.updateAll(
        (key, _) =>
            (start == 0 ? '' : '⋯\n') +
            String.fromCharCodes(texts[key]!.runes.skip(start).take(198)),
      );
    }
  }
  return TxtEncodingPreview(
    samples,
    detected: requested == null && !reviewText && texts.length == 1
        ? texts.keys.single
        : null,
  );
}
