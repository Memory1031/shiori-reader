import 'package:html/dom.dart' as dom;

/// Explicit, per-parse developer observer. Never attach to a book or diagnostic
/// slot. Only copied identifiers, bounded CSS tokens and scalar metadata survive.
final class EpubTraceCollector {
  EpubTraceCollector({this.capacity = 100000}) {
    if (capacity < 0 || capacity > 200000) {
      throw ArgumentError.value(capacity, 'capacity');
    }
  }
  final int capacity;
  final _events = <Map<String, Object?>>[];
  bool truncated = false;
  String? currentStylesheet;
  List<Map<String, Object?>> get events => List.unmodifiable(_events);
  bool get collecting => !truncated;

  void record(
    String kind,
    String path, {
    String? location,
    String? stylesheet,
    int? ruleIndex,
    int? declarationIndex,
    String? property,
    String? value,
    required String reason,
    Map<String, Object?> data = const {},
  }) {
    if (_events.length >= capacity) {
      truncated = true;
      return;
    }
    _events.add(
      Map.unmodifiable({
        'kind': kind,
        'document': traceIdentifier(path),
        'location': location == null ? null : traceIdentifier(location),
        'stylesheet': stylesheet == null ? null : traceIdentifier(stylesheet),
        'ruleIndex': ruleIndex,
        'declarationIndex': declarationIndex,
        'property': property == null
            ? null
            : traceIdentifier(property, limit: 80),
        'value': value == null ? null : traceCssValue(value),
        'reason': reason,
        'data': Map<String, Object?>.unmodifiable({
          for (final e in data.entries) e.key: _scalar(e.value),
        }),
      }),
    );
  }

  Object? _scalar(Object? value) {
    if (value is bool || value is int || value == null) return value;
    if (value is double) return value.isFinite ? value : null;
    if (value is String) {
      return RegExp(r'^[a-f0-9]{64}$').hasMatch(value) ? value : '[redacted]';
    }
    if (value is List) {
      return List<Object?>.unmodifiable(
        value.take(8).map((e) => e is num || e is bool ? _scalar(e) : null),
      );
    }
    return null;
  }
}

String traceIdentifier(String value, {int limit = 1024}) =>
    String.fromCharCodes(
      value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '_').runes.take(limit),
    );

/// CSS strings, functions containing URLs and arbitrary author text are private.
String traceCssValue(String value) {
  if (value.length > 120 ||
      !RegExp(r'^[a-zA-Z0-9#.%+(),\s!/-]+$').hasMatch(value) ||
      RegExp(
        r'url\s*\(|var\s*\(|(?:https?|data):',
        caseSensitive: false,
      ).hasMatch(value)) {
    return '[redacted]';
  }
  // Only finite CSS keywords/numbers/colors; arbitrary identifiers can be text.
  const keywords = {
    'none',
    'hidden',
    'solid',
    'dashed',
    'dotted',
    'double',
    'ridge',
    'groove',
    'inset',
    'outset',
    'thin',
    'medium',
    'thick',
    'inherit',
    'initial',
    'unset',
    'auto',
    'normal',
    'nowrap',
    'pre',
    'pre-wrap',
    'pre-line',
    'visible',
    'collapse',
    'black',
    'white',
    'red',
    'green',
    'blue',
    'yellow',
    'purple',
    'gray',
    'grey',
    'orange',
    'pink',
    'transparent',
    'currentcolor',
    'bold',
    'bolder',
    'italic',
    'oblique',
    'xx-small',
    'x-small',
    'small',
    'large',
    'x-large',
    'xx-large',
    'xxx-large',
    'block',
    'inline',
    'inline-block',
    'flex',
    'grid',
    'inline-flex',
    'inline-grid',
    'static',
    'relative',
    'absolute',
    'fixed',
    'left',
    'right',
    'center',
    'start',
    'end',
    'both',
    'ltr',
    'rtl',
    'horizontal-tb',
    'vertical-rl',
    'vertical-lr',
    'important',
    'top',
    'bottom',
    'baseline',
    'screen',
    'all',
    'print',
    'rgb',
    'rgba',
  };
  final cleaned = value.toLowerCase().replaceAll(
    RegExp(
      r'#[0-9a-f]+|[+-]?(?:\d*\.)?\d+(?:vmin|vmax|rem|px|em|pt|pc|cm|mm|in|vw|vh|%|deg)?',
    ),
    '',
  );
  if (RegExp(
    r'[a-z][a-z-]*',
  ).allMatches(cleaned).any((m) => !keywords.contains(m[0]))) {
    return '[redacted]';
  }
  return traceIdentifier(value, limit: 120);
}

/// Structural locator, never a fabricated source span or an author class/id.
String epubTraceLocation(dom.Element? node) {
  final parts = <String>[];
  for (var e = node; e != null && parts.length < 128; e = e.parent) {
    final siblings = e.parent?.children
        .where((n) => n.localName == e!.localName)
        .toList();
    parts.add(
      '${e.localName ?? "element"}[${siblings == null ? 1 : siblings.indexOf(e) + 1}]',
    );
  }
  return parts.reversed.join('/');
}
