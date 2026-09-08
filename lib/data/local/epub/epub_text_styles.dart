import 'package:html/dom.dart' as dom;

/// Bounded subset for native prose: alignment and em indentation only.
/// Reader preferences own body size, line height and paragraph spacing.
Map<dom.Element, Map<String, String>> epubTextStyles(
  dom.Document doc,
  Iterable<String> sheets,
) {
  final values = <dom.Element, Map<String, String>>{};
  final rules = <(String, String, int)>[];
  for (final sheet in sheets) {
    final css = sheet.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    for (final match in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(css)) {
      for (final selector in match.group(1)!.split(',')) {
        if (selector.contains('@') || rules.length >= 1000) continue;
        final score =
            '#'.allMatches(selector).length * 100 +
            RegExp(r'[.:\[]').allMatches(selector).length * 10 +
            RegExp(r'(?:^|\s)[a-zA-Z]').allMatches(selector).length;
        rules.add((selector.trim(), match.group(2)!, score));
      }
    }
  }
  // Stable specificity order; retain source order for ties.
  final order = [for (var i = 0; i < rules.length; i++) i]
    ..sort((a, b) {
      final c = rules[a].$3.compareTo(rules[b].$3);
      return c == 0 ? a.compareTo(b) : c;
    });
  void apply(dom.Element element, String declarations) {
    for (final declaration in declarations.split(';')) {
      final parts = declaration.split(':');
      if (parts.length != 2) continue;
      final name = parts[0].trim().toLowerCase();
      if (name == 'text-align' || name == 'text-indent') {
        (values[element] ??= {})[name] = parts[1].trim().toLowerCase();
      }
    }
  }

  for (final i in order) {
    try {
      for (final element in doc.querySelectorAll(rules[i].$1)) {
        apply(element, rules[i].$2);
      }
    } on FormatException {
      /* Unsupported selectors remain native defaults. */
    }
  }
  for (final e in doc.querySelectorAll('[style]')) {
    apply(e, e.attributes['style']!);
  }
  return values;
}
