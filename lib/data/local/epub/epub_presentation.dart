import 'dart:convert';
import 'dart:typed_data';
import 'package:html/dom.dart' as dom;

/// Builds a self-contained, inert document for short, authored layout pages.
/// The caller resolves archive paths; no filesystem or network URLs survive.
String? epubPresentation(
  dom.Document document,
  String path,
  String Function(String) readText,
  Uint8List Function(String) readBytes,
  String? Function(String, String) resolve,
) {
  final body = document.body;
  if (body == null || body.text.length > 2000) return null;
  final sheets = <(String, String)>[];
  for (final link in document.querySelectorAll('link[rel="stylesheet"]')) {
    final ref = resolve(path, link.attributes['href'] ?? '');
    if (ref != null) sheets.add((ref, readText(ref)));
  }
  for (final style in document.querySelectorAll('style')) {
    sheets.add((path, style.text));
  }
  final layout = RegExp(
    r'(?:float\s*:\s*(?:left|right)|(?:^|[;{])\s*(?:-webkit-)?transform\s*:|writing-mode\s*:\s*vertical|position\s*:\s*absolute)',
    caseSensitive: false,
  );
  var authored = body
      .querySelectorAll('[style]')
      .any((e) => layout.hasMatch(e.attributes['style']!));
  for (final (_, css) in sheets) {
    for (final rule in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(css)) {
      if (!layout.hasMatch(rule.group(2)!)) continue;
      try {
        if (body.querySelector(
              rule.group(1)!.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').trim(),
            ) !=
            null) {
          authored = true;
        }
      } on FormatException {
        /* Unsupported selectors do not select a page. */
      }
    }
  }
  if (!authored) return null;
  var resourceBytes = 0;
  final resources = <String, String>{};
  String resource(String base, String href) {
    final ref = resolve(base, href.trim());
    if (ref == null) return '';
    if (resources.containsKey(ref)) return resources[ref]!;
    final ext = ref.split('.').last.toLowerCase();
    final mime = const {
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'ttf': 'font/ttf',
      'otf': 'font/otf',
      'woff': 'font/woff',
      'woff2': 'font/woff2',
    }[ext];
    if (mime == null) return '';
    final bytes = readBytes(ref);
    if (bytes.isEmpty) return '';
    resourceBytes += bytes.length;
    if (resourceBytes > 8 * 1024 * 1024) return '';
    return resources[ref] = 'data:$mime;base64,${base64Encode(bytes)}';
  }

  String css(String base, String value) => value
      .replaceAll(RegExp(r'@import\s+[^;]+;', caseSensitive: false), '')
      .replaceAllMapped(
        RegExp(r'''url\(\s*["']?([^"')]+)["']?\s*\)''', caseSensitive: false),
        (m) => 'url("${resource(base, m.group(1)!)}")',
      )
      .replaceAll('</', r'<\/');
  final copy = body.clone(true);
  const allowed = {
    'div',
    'p',
    'span',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'br',
    'hr',
    'em',
    'strong',
    'b',
    'i',
    'small',
    'ruby',
    'rt',
    'rp',
    'section',
    'article',
    'blockquote',
    'figure',
    'figcaption',
    'img',
    'ul',
    'ol',
    'li',
  };
  for (final e in copy.querySelectorAll('*').toList()) {
    if (!allowed.contains(e.localName)) {
      e.remove();
      continue;
    }
    final original = Map<Object, String>.from(e.attributes);
    e.attributes.clear();
    for (final name in ['class', 'id', 'lang', 'dir', 'title']) {
      if (original[name] case final value?) e.attributes[name] = value;
    }
    if (original['style'] case final value?) {
      e.attributes['style'] = css(path, value);
    }
    if (e.localName == 'img') {
      e.attributes['src'] = resource(path, original['src'] ?? '');
      e.attributes['alt'] = original['alt'] ?? '';
    }
  }
  final bodyAttributes = Map<Object, String>.from(copy.attributes);
  copy.attributes.clear();
  for (final name in ['class', 'lang', 'dir']) {
    if (bodyAttributes[name] case final value?) copy.attributes[name] = value;
  }
  if (bodyAttributes['style'] case final value?) {
    copy.attributes['style'] = css(path, value);
  }
  final styles = sheets.map((s) => css(s.$1, s.$2)).join('\n');
  return '''<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'; script-src 'none'; base-uri 'none'; form-action 'none'">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>$styles</style></head>${copy.outerHtml}</html>''';
}
