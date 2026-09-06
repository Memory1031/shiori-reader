import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Version 1 only canonicalizes line endings. No trim, Unicode normalization,
/// HTML parsing, typography, or Source-specific cleanup belongs here.
abstract final class ContentIdentity {
  static const normalizationVersion = 1;

  static String normalizeText(String text) {
    validateUnicode(text);
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  /// Ordered JSON arrays avoid map iteration order and separator collisions.
  /// Only null/bool/int/String/nested arrays are allowed in identity inputs.
  static String canonicalInput(String kind, List<Object?> fields) {
    void check(Object? value) {
      if (value is String) {
        validateUnicode(value);
      } else if (value is List<Object?>) {
        value.forEach(check);
      } else if (value != null && value is! int && value is! bool) {
        throw ArgumentError('Unsupported canonical identity field');
      }
    }

    final input = <Object?>['shiori', normalizationVersion, kind, fields];
    check(input);
    return jsonEncode(input);
  }

  static String digest(String kind, List<Object?> fields) =>
      sha256.convert(utf8.encode(canonicalInput(kind, fields))).toString();

  static void validateUnicode(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= text.length ||
            text.codeUnitAt(i) < 0xdc00 ||
            text.codeUnitAt(i) > 0xdfff) {
          throw ArgumentError('Unpaired Unicode surrogate');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw ArgumentError('Unpaired Unicode surrogate');
      }
    }
  }
}
