import 'package:html/dom.dart' as dom;

/// Shared screen-sheet media policy for native prose and inert authored
/// pages: a qualifier applies only when it is empty or an exact `all` /
/// `screen` match per comma-separated part. Viewport-dependent conditions
/// are deliberately not guessed — unknown means "does not apply on screen".
/// One predicate decides `<link media>`, `@import` qualifiers and `@media`
/// selectors so the three call sites cannot drift apart.
bool _screenMediaApplies(String input) {
  final media = input.trim().toLowerCase();
  if (media.isEmpty) return true;
  return media
      .split(',')
      .map((part) => part.trim())
      .any((part) => part == 'all' || part == 'screen');
}

/// Document stylesheets in cascade order with `@import` chains expanded.
/// Publisher toolchains routinely park the real rules behind an import-only
/// root sheet (STERAePub++-style `stylesheet.css`), so callers always see
/// the effective cascade: imports are followed depth-first and yielded
/// before the importing sheet's own remainder, matching CSS source order.
///
/// The walk stays bounded like every other CSS pass here — depth- and
/// count-capped, with a total character budget. Repeats inside one branch
/// are treated as cycles, while sibling occurrences stay legitimate cascade;
/// sheet content is cached per path, occurrences are not.
Iterable<(String, String)> epubDocumentStylesheets(
  dom.Document document,
  String path,
  String? Function(String, String) resolve,
  String Function(String) readText,
) sync* {
  final context = _ImportContext(resolve, readText);
  var inlineIndex = 0;
  for (final node in document.querySelectorAll('style, link')) {
    if (!_screenMediaApplies(node.attributes['media'] ?? '')) continue;
    if (node.attributes.containsKey('disabled')) continue;
    if (node.localName == 'style') {
      // Inline sheets share the document path; identity carries a per-node
      // suffix so cycle bookkeeping can never swallow the second sheet.
      yield* context.expand(
        '$path#style${inlineIndex++}',
        path,
        node.text,
        {},
        0,
      );
    } else {
      final rel = (node.attributes['rel'] ?? '').toLowerCase().split(
        RegExp(r'\s+'),
      );
      if (!rel.contains('stylesheet') || rel.contains('alternate')) continue;
      final href = node.attributes['href'];
      if (href == null || href.trim().isEmpty) continue;
      final resolved = resolve(path, href);
      if (resolved == null) continue;
      yield* context.expand(resolved, resolved, context.read(resolved), {}, 0);
    }
  }
}

final _cssCommentPattern = RegExp(r'/\*[\s\S]*?\*/');

/// Budgeted `@import` expansion for one document.
class _ImportContext {
  _ImportContext(this._resolve, this._readText);

  static const _maxDepth = 8;
  static const _maxImports = 64;
  static const _maxTotalChars = 8 * 1024 * 1024;

  final String? Function(String, String) _resolve;
  final String Function(String) _readText;
  final Map<String, String> _readCache = {};
  var _imports = 0;
  var _totalChars = 0;

  String read(String path) =>
      _readCache.putIfAbsent(path, () => _readText(path));

  /// Yield [text] — identity [identity], relative base [base] — with its
  /// leading `@import` block expanded. The active set is per branch: the
  /// same sheet may legitimately be imported twice in sibling branches,
  /// while a repeat inside one branch is a cycle. Every sheet counts its
  /// raw characters against [_maxTotalChars] before stripping comments,
  /// rejecting sheets that do not fit, so the budget bounds
  /// the CSS volume this expansion processes, not just future imports.
  Iterable<(String, String)> expand(
    String identity,
    String base,
    String text,
    Set<String> active,
    int depth,
  ) sync* {
    if (depth > _maxDepth || active.contains(identity)) return;
    if (_totalChars + text.length > _maxTotalChars) return;
    _totalChars += text.length;
    final css = text.replaceAll(_cssCommentPattern, '');
    var index = 0;
    if (css.startsWith('\uFEFF')) index = 1;
    while (_imports < _maxImports &&
        _totalChars < _maxTotalChars &&
        index < css.length) {
      while (index < css.length && _isCssWhitespace(css, index)) {
        index++;
      }
      if (index >= css.length) break;
      // CSS keeps imports ahead of every other rule: the first non-import
      // statement ends the legal prelude, and later lookalikes — quoted
      // strings, nested blocks — are content, never followed.
      if (_atKeyword(css, index, 'charset')) {
        final semi = css.indexOf(';', index);
        if (semi < 0) break;
        index = semi + 1;
        continue;
      }
      if (!_atKeyword(css, index, 'import')) break;
      final statement = _parseImportStatement(css, index);
      if (statement == null) break;
      index = statement.end;
      if (!_screenMediaApplies(statement.media)) continue;
      final resolved = _resolve(base, statement.href);
      if (resolved == null) continue;
      _imports++;
      yield* expand(resolved, resolved, read(resolved), {
        ...active,
        identity,
      }, depth + 1);
    }
    yield (base, css.substring(index));
  }
}

bool _isCssWhitespace(String css, int index) {
  const codes = {0x20, 0x09, 0x0A, 0x0D, 0x0C};
  return codes.contains(css.codeUnitAt(index));
}

/// At-keywords start with `@`: `@import`, `@charset`. A plain match must
/// never accept an at-keyword position, and vice versa, so `url` uses
/// [_identifier] while the prelude scanner uses [_atKeyword].
bool _atKeyword(String css, int index, String keyword) {
  if (index >= css.length || css[index] != '@') return false;
  return _identifier(css, index + 1, keyword);
}

bool _identifier(String css, int index, String keyword) {
  final end = index + keyword.length;
  if (end > css.length) return false;
  if (css.substring(index, end).toLowerCase() != keyword) return false;
  if (end == css.length) return true;
  final c = css.codeUnitAt(end);
  return !((c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x2D ||
      c == 0x5F ||
      c == 0x5C ||
      c >= 0x80);
}

({String href, String media, int end})? _parseImportStatement(
  String css,
  int start,
) {
  var i = _skipCssWhitespace(css, start + 1 + 'import'.length);
  String href;
  if (_identifier(css, i, 'url')) {
    i = _skipCssWhitespace(css, i + 'url'.length);
    if (i >= css.length || css[i] != '(') return null;
    i = _skipCssWhitespace(css, ++i);
    final quote = i < css.length && (css[i] == '"' || css[i] == "'")
        ? css[i]
        : null;
    if (quote != null) i++;
    final begin = i;
    while (i < css.length && (quote != null || css[i] != ')')) {
      if (quote != null) {
        if (css[i] == quote) break;
      } else if (_isCssWhitespace(css, i)) {
        break;
      }
      i++;
    }
    href = css.substring(begin, i);
    if (quote != null) {
      if (i >= css.length || css[i] != quote) return null;
      i++;
    }
    i = _skipCssWhitespace(css, i);
    if (i >= css.length || css[i] != ')') return null;
    i++;
  } else if (i < css.length && (css[i] == '"' || css[i] == "'")) {
    final quote = css[i];
    final begin = ++i;
    while (i < css.length && css[i] != quote) {
      i++;
    }
    if (i >= css.length) return null;
    href = css.substring(begin, i);
    i++;
  } else {
    return null;
  }
  i = _skipCssWhitespace(css, i);
  final semi = css.indexOf(';', i);
  if (semi < 0) return null;
  return (href: href, media: css.substring(i, semi), end: semi + 1);
}

int _skipCssWhitespace(String css, int index) {
  while (index < css.length && _isCssWhitespace(css, index)) {
    index++;
  }
  return index;
}

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
      if (selector.toLowerCase().startsWith('@media')) {
        if (_screenMediaApplies(selector.substring('@media'.length))) {
          yield* epubScreenRules(declarations, depth + 1);
        }
      } else if (!selector.startsWith('@') && selector.isNotEmpty) {
        yield (selector, declarations);
      }
      start = i + 1;
    }
  }
}

/// Bounded native prose styles: alignment, indentation, whitespace and visibility.
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
      if ({
        'color',
        'font-size',
        'font-weight',
        'font-style',
        'max-width',
        'padding',
        'margin',
        'margin-left',
        'margin-right',
        'border',
        'border-width',
        'border-color',
        'border-style',
        'background-color',
        'position',
        'float',
        'height',
        'width',
        'text-align',
        'text-indent',
        'display',
        'white-space',
        'visibility',
      }.contains(name)) {
        final raw = parts[1].trim().toLowerCase();
        final priority = RegExp(r'!\s*important\s*$').hasMatch(raw);
        final value = raw
            .replaceFirst(RegExp(r'\s*!\s*important\s*$'), '')
            .trim();
        if (name == 'white-space' &&
            !{
              'normal',
              'nowrap',
              'pre',
              'pre-wrap',
              'pre-line',
              'inherit',
              'initial',
              'unset',
            }.contains(value)) {
          continue;
        }
        if (name == 'visibility' &&
            !{
              'visible',
              'hidden',
              'collapse',
              'inherit',
              'initial',
              'unset',
            }.contains(value)) {
          continue;
        }

        var properties = {name: value};
        if (name.startsWith('margin')) {
          final tokens = value.split(RegExp(r'\s+'));
          if (tokens.isEmpty ||
              tokens.length > (name == 'margin' ? 4 : 1) ||
              tokens.any(
                (t) => !RegExp(
                  r'^(auto|initial|inherit|unset|0|[+-]?(?:\d*\.)?\d+(?:px|em|rem|%))$',
                ).hasMatch(t),
              )) {
            continue;
          }
          // Expand before cascading so shorthand, longhand and !important
          // compete per side. Vertical margins remain reader-owned.
          if (name == 'margin') {
            properties = {
              'margin-left': tokens.length == 4
                  ? tokens[3]
                  : tokens.length >= 2
                  ? tokens[1]
                  : tokens[0],
              'margin-right': tokens.length >= 2 ? tokens[1] : tokens[0],
            };
          }
        }
        final priorities = important[element] ??= {};
        for (final property in properties.entries) {
          if (!priority && priorities.contains(property.key)) continue;
          if (priority) priorities.add(property.key);
          (values[element] ??= {})[property.key] = property.value;
        }
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
