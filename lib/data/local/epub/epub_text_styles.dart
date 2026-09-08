import 'package:html/dom.dart' as dom;

/// A bounded rule walker, not a general CSS engine. Unknown conditional groups
/// are ignored rather than accidentally applying print/width-specific rules.
Iterable<(String, String)> epubScreenRules(
  String input, [
  int depth = 0,
]) sync* {
  if (depth > 8) return;
  final css = input.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  var start = 0, nesting = 0, open = -1;
  String? quote;
  for (var i = 0; i < css.length; i++) {
    final c = css[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
      continue;
    }
    if (c == ';' && nesting == 0) {
      start = i + 1;
      continue;
    }
    if (c == '{') {
      if (nesting++ == 0) open = i;
    }
    if (c == '}' && nesting > 0 && --nesting == 0) {
      final selector = css.substring(start, open).trim();
      final declarations = css.substring(open + 1, i);
      if (RegExp(
        r'^@media\s+(?:all|screen)$',
        caseSensitive: false,
      ).hasMatch(selector)) {
        yield* epubScreenRules(declarations, depth + 1);
      } else if (!selector.startsWith('@') && selector.isNotEmpty) {
        yield (selector, declarations);
      }
      start = i + 1;
    }
  }
}

/// Bounded subset for native prose: alignment and em indentation only.
/// Reader preferences own body size, line height and paragraph spacing.
Map<dom.Element, Map<String, String>> epubTextStyles(
  dom.Document doc,
  Iterable<String> sheets,
) {
  final values = <dom.Element, Map<String, String>>{};
  final important = <dom.Element, Set<String>>{};
  final rules = <(String, String, int)>[];
  for (final sheet in sheets) {
    for (final (selectors, declarations) in epubScreenRules(sheet)) {
      for (final selector in selectors.split(',')) {
        if (selector.contains('@') || rules.length >= 1000) continue;
        final score =
            '#'.allMatches(selector).length * 100 +
            RegExp(r'[.:\[]').allMatches(selector).length * 10 +
            RegExp(r'(?:^|\s)[a-zA-Z]').allMatches(selector).length;
        rules.add((selector.trim(), declarations, score));
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
      if ({'text-align', 'text-indent', 'display'}.contains(name)) {
        final raw = parts[1].trim().toLowerCase();
        final priority = RegExp(r'!\s*important\s*$').hasMatch(raw);
        final priorities = important[element] ??= {};
        if (!priority && priorities.contains(name)) continue;
        if (priority) priorities.add(name);
        (values[element] ??= {})[name] = raw
            .replaceFirst(RegExp(r'\s*!\s*important\s*$'), '')
            .trim();
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
    } on UnimplementedError {
      /* html's selector engine does not implement every CSS pseudo-class. */
    }
  }
  for (final e in doc.querySelectorAll('[style]')) {
    apply(e, e.attributes['style']!);
  }
  return values;
}
