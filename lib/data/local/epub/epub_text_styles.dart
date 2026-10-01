import 'epub_rich_styles.dart';
import 'epub_trace.dart';
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
  String Function(String) readText, {
  EpubTraceCollector? trace,
}) sync* {
  final context = _ImportContext(resolve, readText, trace, path);
  var inlineIndex = 0;
  for (final node in document.querySelectorAll('style, link')) {
    if (!_screenMediaApplies(node.attributes['media'] ?? '')) {
      trace?.record(
        'css.sheet',
        path,
        location: epubTraceLocation(node),
        reason: (node.attributes['media'] ?? '').trim() == 'print'
            ? 'print_not_applied'
            : 'media_unknown',
      );
      continue;
    }
    if (node.attributes.containsKey('disabled')) {
      trace?.record(
        'css.sheet',
        path,
        location: epubTraceLocation(node),
        reason: 'disabled',
      );
      continue;
    }
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
      if (!rel.contains('stylesheet') || rel.contains('alternate')) {
        if (rel.contains('alternate')) {
          trace?.record(
            'css.sheet',
            path,
            location: epubTraceLocation(node),
            reason: 'alternate',
          );
        }
        continue;
      }
      final href = node.attributes['href'];
      if (href == null || href.trim().isEmpty) continue;
      final resolved = resolve(path, href);
      if (resolved == null) {
        trace?.record(
          'css.sheet',
          path,
          location: epubTraceLocation(node),
          reason: 'unusable_reference',
        );
        continue;
      }
      yield* context.expand(resolved, resolved, context.read(resolved), {}, 0);
    }
  }
}

final _cssCommentPattern = RegExp(r'/\*[\s\S]*?\*/');

/// Budgeted `@import` expansion for one document.
class _ImportContext {
  _ImportContext(this._resolve, this._readText, this.trace, this.path);
  final EpubTraceCollector? trace;
  final String path;

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
    if (depth > _maxDepth || active.contains(identity)) {
      trace?.record(
        'css.sheet',
        path,
        stylesheet: identity,
        reason: depth > _maxDepth ? 'import_depth_limit' : 'import_cycle',
      );
      return;
    }
    if (_totalChars + text.length > _maxTotalChars) {
      trace?.record(
        'css.sheet',
        path,
        stylesheet: identity,
        reason: 'sheet_budget',
      );
      return;
    }
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
      if (!_screenMediaApplies(statement.media)) {
        trace?.record(
          'css.sheet',
          path,
          stylesheet: identity,
          reason: statement.media.trim() == 'print'
              ? 'import_print'
              : 'import_media_unknown',
        );
        continue;
      }
      final resolved = _resolve(base, statement.href);
      if (resolved == null) {
        trace?.record(
          'css.sheet',
          path,
          stylesheet: identity,
          reason: 'import_unusable_reference',
        );
        continue;
      }
      _imports++;
      yield* expand(resolved, resolved, read(resolved), {
        ...active,
        identity,
      }, depth + 1);
    }
    if (_imports >= _maxImports) {
      trace?.record(
        'css.sheet',
        path,
        stylesheet: identity,
        reason: 'import_count_limit',
      );
    }
    trace?.record(
      'css.sheet',
      path,
      stylesheet: identity,
      reason: 'loaded',
      data: {'characters': css.length},
    );
    trace?.currentStylesheet = identity;
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
  EpubTraceCollector? trace,
  String path = '',
]) sync* {
  if (depth > 8) {
    trace?.record(
      'css.syntax',
      path,
      stylesheet: trace.currentStylesheet,
      reason: 'rule_depth_limit',
    );
    return;
  }
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
          yield* epubScreenRules(declarations, depth + 1, trace, path);
        } else {
          trace?.record(
            'css.syntax',
            path,
            stylesheet: trace.currentStylesheet,
            reason: selector.substring('@media'.length).trim() == 'print'
                ? 'print_not_applied'
                : 'media_unknown',
          );
        }
      } else if (!selector.startsWith('@') && selector.isNotEmpty) {
        yield (selector, declarations);
      } else if (selector.startsWith('@')) {
        trace?.record(
          'css.syntax',
          path,
          stylesheet: trace.currentStylesheet,
          reason: 'conditional_or_at_rule_unknown',
        );
      }
      start = i + 1;
    }
  }
  if (nesting != 0 || quote != null) {
    trace?.record(
      'css.syntax',
      path,
      stylesheet: trace.currentStylesheet,
      reason: 'incomplete_rule',
    );
  }
}

/// Bounded native prose styles: alignment, indentation, whitespace and visibility.
/// Reader preferences own body size, line height and paragraph spacing.
Map<dom.Element, Map<String, String>> epubTextStyles(
  dom.Document doc,
  Iterable<String> sheets, {
  EpubTraceCollector? trace,
  String path = '',
}) {
  final values = <dom.Element, Map<String, String>>{};
  final important = <dom.Element, Set<String>>{};
  final rules = <(String, String, int)>[];
  final sources = trace == null ? null : <(String?, int)>[];
  var trackedOrigins = 0;
  final origins = trace == null
      ? null
      : <dom.Element, Map<String, Map<String, Object?>>>{};
  for (final sheet in sheets) {
    var sourceRule = 0;
    for (final (selectors, declarations) in epubScreenRules(
      sheet,
      0,
      trace,
      path,
    )) {
      if (trace != null) {
        var d = 0;
        for (final declaration in declarations.split(';')) {
          final colon = declaration.indexOf(':');
          if (colon > 0) {
            trace.record(
              'css.source',
              path,
              stylesheet: trace.currentStylesheet,
              ruleIndex: sourceRule,
              declarationIndex: d,
              property: declaration.substring(0, colon).trim().toLowerCase(),
              value: declaration.substring(colon + 1).trim(),
              reason: 'loaded_declaration_inventory',
            );
          }
          d++;
          if (!trace.collecting) break;
        }
      }
      for (final selector in selectors.split(',')) {
        if (selector.contains('@') || rules.length >= 1000) {
          trace?.record(
            'css.syntax',
            path,
            stylesheet: trace.currentStylesheet,
            reason: 'rule_count_limit',
          );
          continue;
        }
        final score =
            '#'.allMatches(selector).length * 100 +
            RegExp(r'[.:\[]').allMatches(selector).length * 10 +
            RegExp(r'(?:^|\s)[a-zA-Z]').allMatches(selector).length;
        rules.add((selector.trim(), declarations, score));
        sources?.add((trace?.currentStylesheet, sourceRule));
      }
      sourceRule++;
    }
  }
  // Stable specificity order; retain source order for ties.
  final order = [for (var i = 0; i < rules.length; i++) i]
    ..sort((a, b) {
      final c = rules[a].$3.compareTo(rules[b].$3);
      return c == 0 ? a.compareTo(b) : c;
    });
  void apply(
    dom.Element element,
    String declarations,
    int ruleIndex,
    String? sheet,
  ) {
    var declarationIndex = -1;
    for (final declaration in declarations.split(';')) {
      declarationIndex++;
      final parts = declaration.split(':');
      if (parts.length != 2) {
        if (parts.length > 2) {
          trace?.record(
            'css.syntax',
            path,
            stylesheet: sheet,
            ruleIndex: ruleIndex,
            declarationIndex: declarationIndex,
            reason: 'declaration_syntax_unknown',
          );
        }
        continue;
      }
      final name = parts[0].trim().toLowerCase();
      if ({
        'color',
        'font-size',
        'font-weight',
        'font-style',
        'max-width',
        'padding',
        'padding-left',
        'padding-right',
        'padding-top',
        'padding-bottom',
        'border-collapse',
        'border-right',
        'border-left',
        'border-top',
        'border-bottom',
        'border-left-width',
        'border-left-color',
        'border-left-style',
        'border-top-width',
        'border-top-color',
        'border-top-style',
        'border-bottom-width',
        'border-bottom-color',
        'border-bottom-style',
        'border-right-width',
        'border-right-color',
        'border-right-style',
        'vertical-align',
        'margin',
        'margin-left',
        'margin-right',
        'margin-top',
        'margin-bottom',
        'border-radius',
        'border',
        'border-width',
        'border-color',
        'border-style',
        'background-color',
        'position',
        'float',
        'clear',
        'direction',
        'unicode-bidi',
        'writing-mode',
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
          trace?.record(
            'css.decision',
            path,
            location: epubTraceLocation(element),
            stylesheet: sheet,
            ruleIndex: ruleIndex,
            declarationIndex: declarationIndex,
            property: name,
            value: value,
            reason: 'rejected_value',
          );
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
          trace?.record(
            'css.decision',
            path,
            location: epubTraceLocation(element),
            stylesheet: sheet,
            ruleIndex: ruleIndex,
            declarationIndex: declarationIndex,
            property: name,
            value: value,
            reason: 'rejected_value',
          );
          continue;
        }

        final properties = _expandNativeDeclaration(name, value);
        if (properties == null) {
          trace?.record(
            'css.decision',
            path,
            location: epubTraceLocation(element),
            stylesheet: sheet,
            ruleIndex: ruleIndex,
            declarationIndex: declarationIndex,
            property: name,
            value: value,
            reason: 'rejected_value',
          );
          continue;
        }
        final priorities = important[element] ??= {};
        for (final property in properties.entries) {
          if (!priority && priorities.contains(property.key)) {
            trace?.record(
              'css.decision',
              path,
              location: epubTraceLocation(element),
              stylesheet: sheet,
              ruleIndex: ruleIndex,
              declarationIndex: declarationIndex,
              property: name,
              value: value,
              reason: 'overridden_important',
            );
            continue;
          }
          if (origins != null && trace!.collecting) {
            if (++trackedOrigins > trace.capacity) {
              trace.truncated = true;
            } else {
              final previous = origins[element]?[property.key];
              if (previous != null) {
                trace.record(
                  'css.decision',
                  path,
                  location: epubTraceLocation(element),
                  stylesheet: previous['sheet'] as String?,
                  ruleIndex: previous['rule'] as int,
                  declarationIndex: previous['declaration'] as int,
                  property: property.key,
                  value: previous['value'] as String,
                  reason: 'overridden',
                );
              }
              (origins[element] ??= {})[property.key] = {
                'sheet': sheet,
                'rule': ruleIndex,
                'declaration': declarationIndex,
                'value': property.value,
              };
            }
          }
          if (priority) priorities.add(property.key);
          (values[element] ??= {})[property.key] = property.value;
        }
      } else {
        trace?.record(
          'css.decision',
          path,
          location: epubTraceLocation(element),
          stylesheet: sheet,
          ruleIndex: ruleIndex,
          declarationIndex: declarationIndex,
          property: name,
          value: parts[1].trim(),
          reason: 'property_not_in_native_subset',
        );
      }
    }
  }

  for (final i in order) {
    try {
      final selector = rules[i].$1;
      // html 0.15 counts raw nodes for nth-child. Resolve the two terminal
      // cell positions against element siblings, independent of source whitespace.
      final nth = RegExp(r':nth-child\(\s*([12])\s*\)$').firstMatch(selector);
      final selected = doc.querySelectorAll(
        nth == null ? selector : selector.substring(0, nth.start),
      );
      if (selected.isEmpty) {
        trace?.record(
          'css.selector',
          path,
          stylesheet: sources?[i].$1,
          ruleIndex: sources?[i].$2 ?? i,
          reason: 'unmatched',
        );
      }
      for (final element in selected) {
        if (nth != null &&
            element.parent?.children.indexOf(element) !=
                int.parse(nth[1]!) - 1) {
          continue;
        }
        apply(element, rules[i].$2, sources?[i].$2 ?? i, sources?[i].$1);
      }
    } on FormatException {
      trace?.record(
        'css.selector',
        path,
        stylesheet: sources?[i].$1,
        ruleIndex: sources?[i].$2 ?? i,
        reason: 'unknown',
      );
      /* Unsupported selectors remain native defaults. */
    } on UnimplementedError {
      trace?.record(
        'css.selector',
        path,
        stylesheet: sources?[i].$1,
        ruleIndex: sources?[i].$2 ?? i,
        reason: 'unknown',
      );
      /* html's selector engine does not implement every CSS pseudo-class. */
    }
  }
  for (final e in doc.querySelectorAll('[style]')) {
    apply(e, e.attributes['style']!, -1, path);
  }
  if (origins != null) {
    for (final e in origins.entries) {
      for (final p in e.value.entries) {
        trace!.record(
          'css.cascade',
          path,
          location: epubTraceLocation(e.key),
          stylesheet: p.value['sheet'] as String?,
          ruleIndex: p.value['rule'] as int,
          declarationIndex: p.value['declaration'] as int,
          property: p.key,
          value: p.value['value'] as String,
          reason: 'winner',
        );
        if (!trace.collecting) break;
      }
      if (!trace!.collecting) break;
    }
  }
  return values;
}

const _borderStyles = {
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
};
const _sides = ['top', 'right', 'bottom', 'left'];
List<String> _four(List<String> t) => [
  t[0],
  t.length > 1 ? t[1] : t[0],
  t.length > 2 ? t[2] : t[0],
  t.length > 3
      ? t[3]
      : t.length > 1
      ? t[1]
      : t[0],
];
bool _borderWidth(String t) =>
    {'thin', 'medium', 'thick'}.contains(t) ||
    RegExp(r'^(0|(?:\d*\.)?\d+(?:px|em))$').hasMatch(t);
bool _borderColor(String t) => t == 'currentcolor' || epubColor(t) != null;

Map<String, String>? _expandNativeDeclaration(String name, String value) {
  final tokens = RegExp(
    r'rgb\([^)]*\)|[^\s]+',
  ).allMatches(value).map((m) => m[0]!).toList();
  if (tokens.isEmpty) return null;
  if (name == 'font-size' &&
      !{'inherit', 'unset', 'initial'}.contains(value) &&
      epubFontScale(value, 1) == null) {
    return null;
  }
  if (name.startsWith('margin') || name.startsWith('padding')) {
    final shorthand = name == 'margin' || name == 'padding';
    if (tokens.length > (shorthand ? 4 : 1) ||
        tokens.any(
          (t) =>
              !RegExp(
                r'^(auto|initial|inherit|unset|0|[+-]?(?:\d*\.)?\d+(?:px|em|rem|%))$',
              ).hasMatch(t) ||
              name.startsWith('padding') && (t == 'auto' || t.startsWith('-')),
        )) {
      return null;
    }
    if (!shorthand) return {name: value};
    final values = _four(tokens);
    return {
      name: value,
      for (var i = 0; i < 4; i++) '$name-${_sides[i]}': values[i],
    };
  }
  if ({'border-width', 'border-style', 'border-color'}.contains(name)) {
    bool valid(String t) => name == 'border-width'
        ? _borderWidth(t)
        : name == 'border-style'
        ? _borderStyles.contains(t)
        : _borderColor(t);
    if (tokens.length > 4 || tokens.any((t) => !valid(t))) return null;
    final values = _four(tokens), suffix = name.substring(7);
    return {
      name: value,
      for (var i = 0; i < 4; i++) 'border-${_sides[i]}-$suffix': values[i],
    };
  }
  if (name == 'border' || _sides.any((side) => name == 'border-$side')) {
    String? width, style, color;
    for (final token in tokens) {
      if (_borderWidth(token) && width == null) {
        width = token;
      } else if (_borderStyles.contains(token) && style == null) {
        style = token;
      } else if (_borderColor(token) && color == null) {
        color = token;
      } else {
        return null;
      }
    }
    final sides = name == 'border' ? _sides : [name.substring(7)];
    return {
      name: value,
      for (final side in sides) ...{
        'border-$side-width': width ?? 'medium',
        'border-$side-style': style ?? 'none',
        'border-$side-color': color ?? 'currentcolor',
      },
    };
  }
  if (name.startsWith('border-') &&
      name != 'border-collapse' &&
      name != 'border-radius') {
    if (name.endsWith('-width') && !_borderWidth(value) ||
        name.endsWith('-style') && !_borderStyles.contains(value) ||
        name.endsWith('-color') && !_borderColor(value)) {
      return null;
    }
  }
  return {name: value};
}
