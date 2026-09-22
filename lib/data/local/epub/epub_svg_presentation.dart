import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;

import 'epub_image_candidates.dart';

/// Rebuilds a bounded authored SVG page instead of passing publisher markup
/// through. Supported pages contain one local raster image plus positioned
/// text and simple transparent/decorative rectangles. Links are made inert.
String? epubSvgPresentation(
  dom.Document document,
  String path,
  Iterable<String> sheets,
  Uint8List Function(String) readBytes,
  String? Function(String, String) resolve,
) {
  final body = document.body;
  if (body == null || body.text.length > 2000) return null;
  // SVG stylesheet cascade is deliberately outside this first safe subset.
  if (sheets.any((css) => css.trim().isNotEmpty)) return null;
  try {
    return _SvgPage(path, readBytes, resolve).build(body);
  } on _UnsupportedSvg {
    return null;
  }
}

class _UnsupportedSvg implements Exception {
  const _UnsupportedSvg();
}

class _SvgPage {
  _SvgPage(this.path, this.readBytes, this.resolve);

  final String path;
  final Uint8List Function(String) readBytes;
  final String? Function(String, String) resolve;

  static const _namespace = 'http://www.w3.org/2000/svg';
  static const _escape = HtmlEscape(HtmlEscapeMode.attribute);

  final _output = StringBuffer();
  dom.Element? _root;
  int _nodes = 0;
  int _images = 0;
  int _texts = 0;

  Never _unsupported() => throw const _UnsupportedSvg();

  /// Only text nodes and nested tspans render glyphs; the skipped
  /// title/desc/metadata subtrees never count as visible text.
  bool _hasRenderedText(dom.Element text) {
    bool visit(dom.Node node) {
      if (node is dom.Text) return node.text.trim().isNotEmpty;
      return node is dom.Element &&
          node.namespaceUri == _namespace &&
          node.localName == 'tspan' &&
          node.nodes.any(visit);
    }

    return text.nodes.any(visit);
  }

  void _count(int depth) {
    if (++_nodes > 512 || depth > 32) _unsupported();
  }

  String _rawName(Object name) => name.toString().toLowerCase();

  String _localName(Object name) {
    final raw = _rawName(name);
    final braced = raw.lastIndexOf('}');
    if (braced >= 0 && braced + 1 < raw.length) {
      return raw.substring(braced + 1);
    }
    final colon = raw.lastIndexOf(':');
    return colon >= 0 ? raw.substring(colon + 1) : raw;
  }

  bool _zeroBox(String css) {
    for (final part in css.split(';')) {
      if (part.trim().isEmpty) continue;
      final split = part.indexOf(':');
      if (split <= 0 ||
          split != part.lastIndexOf(':') ||
          !{
            'margin',
            'padding',
          }.contains(part.substring(0, split).trim().toLowerCase()) ||
          !RegExp(r'^0(?:px)?$').hasMatch(part.substring(split + 1).trim())) {
        return false;
      }
    }
    return true;
  }

  void _findRoot(dom.Node node, int depth) {
    _count(depth);
    if (node is dom.Text) {
      if (node.text.trim().isNotEmpty) _unsupported();
      return;
    }
    if (node is! dom.Element) return;
    if (node.localName == 'svg' && node.namespaceUri == _namespace) {
      if (_root != null) _unsupported();
      _root = node;
      return;
    }
    if (!{
      'body',
      'div',
      'main',
      'section',
      'article',
    }.contains(node.localName)) {
      _unsupported();
    }
    for (final entry in node.attributes.entries) {
      final raw = _rawName(entry.key);
      final local = _localName(entry.key);
      if (local == 'style' && _zeroBox(entry.value)) continue;
      if ({'id', 'class', 'lang', 'dir'}.contains(local) ||
          raw.contains('xmlns') ||
          local.startsWith('on')) {
        continue;
      }
      _unsupported();
    }
    for (final child in node.nodes) {
      _findRoot(child, depth + 1);
    }
  }

  List<double> _numbers(String value, {int limit = 1}) {
    if (value.length > 1024) _unsupported();
    final parts = value.trim().split(RegExp(r'[\s,]+'));
    if (parts.isEmpty || parts.length > limit) _unsupported();
    final result = <double>[];
    for (final part in parts) {
      if (!RegExp(
        r'^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$',
      ).hasMatch(part)) {
        _unsupported();
      }
      final number = double.tryParse(part);
      if (number == null || !number.isFinite || number.abs() > 1000000) {
        _unsupported();
      }
      result.add(number);
    }
    return result;
  }

  void _attribute(String name, String value) {
    _output.write(' $name="${_escape.convert(value)}"');
  }

  void _paintAttribute(String name, String value) {
    if ({'x', 'y', 'dx', 'dy'}.contains(name)) {
      _numbers(value, limit: 64);
    } else if (name == 'letter-spacing') {
      _numbers(value);
    } else if ({
      'width',
      'height',
      'rx',
      'ry',
      'font-size',
      'stroke-width',
    }.contains(name)) {
      if (_numbers(value).single < 0) _unsupported();
    } else if ({'opacity', 'fill-opacity', 'stroke-opacity'}.contains(name)) {
      final number = _numbers(value).single;
      if (number < 0 || number > 1) _unsupported();
    } else if ({'fill', 'stroke'}.contains(name)) {
      if (!RegExp(
        r'^(?:#[0-9a-fA-F]{3}|#[0-9a-fA-F]{6}|[a-zA-Z]+)$',
      ).hasMatch(value)) {
        _unsupported();
      }
    } else if (name == 'font-family') {
      if (value.length > 128 ||
          !RegExp(r'''^[a-zA-Z0-9 ,"\'_-]+$''').hasMatch(value)) {
        _unsupported();
      }
    } else if (name == 'font-weight') {
      if (!RegExp(r'^(?:normal|bold|[1-9]00)$').hasMatch(value)) {
        _unsupported();
      }
    } else if (name == 'font-style') {
      if (!{'normal', 'italic', 'oblique'}.contains(value)) _unsupported();
    } else if (name == 'text-anchor') {
      if (!{'start', 'middle', 'end'}.contains(value)) _unsupported();
    } else {
      _unsupported();
    }
    _attribute(name, value);
  }

  void _draw(dom.Node node, int depth, {bool inText = false}) {
    _count(depth);
    if (node is dom.Text) {
      if (inText) {
        _output.write(const HtmlEscape().convert(node.text));
      } else if (node.text.trim().isNotEmpty) {
        _unsupported();
      }
      return;
    }
    if (node is! dom.Element) return;
    if (node.namespaceUri != _namespace) _unsupported();
    final tag = node.localName!;
    if ({'title', 'desc', 'metadata'}.contains(tag)) return;
    if (!{'svg', 'g', 'a', 'image', 'text', 'tspan', 'rect'}.contains(tag)) {
      _unsupported();
    }
    if (tag == 'svg' && node != _root || tag == 'tspan' && !inText) {
      _unsupported();
    }
    if (inText && tag != 'tspan') _unsupported();
    if (tag == 'text' && _hasRenderedText(node)) _texts++;

    final renderedTag = tag == 'a' ? 'g' : tag;
    _output.write('<$renderedTag');
    for (final entry in node.attributes.entries) {
      final raw = _rawName(entry.key);
      final local = _localName(entry.key);
      final value = entry.value.trim();
      // Publisher links, handlers and identifiers never reach the WebView.
      if ({'id', 'class', 'version', 'role', 'target'}.contains(local) ||
          raw.contains('xmlns') ||
          raw.startsWith('aria-') ||
          local.startsWith('on')) {
        continue;
      }
      if (local == 'href') {
        if (tag != 'image' && tag != 'a') _unsupported();
        continue;
      }
      if (tag == 'svg' && {'width', 'height', 'viewbox'}.contains(local)) {
        continue;
      }
      if (tag == 'svg' && local == 'style' && _zeroBox(value)) continue;
      if (local == 'preserveaspectratio') {
        if (!RegExp(
          r'^(?:none|x(?:Min|Mid|Max)Y(?:Min|Mid|Max)(?: (?:meet|slice))?)$',
        ).hasMatch(value)) {
          _unsupported();
        }
        if (tag != 'svg') _attribute('preserveAspectRatio', value);
        continue;
      }
      _paintAttribute(local, value);
    }

    if (tag == 'svg') {
      final box = node.attributes['viewBox'] ?? node.attributes['viewbox'];
      if (box == null) _unsupported();
      final values = _numbers(box, limit: 4);
      if (values.length != 4 || values[2] <= 0 || values[3] <= 0) {
        _unsupported();
      }
      _attribute('xmlns', _namespace);
      _attribute('viewBox', box);
      _attribute('preserveAspectRatio', 'xMidYMin meet');
      _attribute('width', '100%');
      _attribute('height', '100%');
    }

    if (tag == 'image') {
      if (++_images > 1 || node.nodes.isNotEmpty) _unsupported();
      // SVG images have no intrinsic-size fallback: missing or zero
      // width/height renders nothing, unlike HTML img.
      final width = node.attributes['width'];
      final height = node.attributes['height'];
      if (width == null || height == null) _unsupported();
      if (_numbers(width).single <= 0 || _numbers(height).single <= 0) {
        _unsupported();
      }
      final href = epubImageCandidates(node).firstOrNull;
      if (href == null) _unsupported();
      final ref = resolve(path, href);
      if (ref == null) _unsupported();
      final bytes = readBytes(ref);
      final mime = epubRasterMime(bytes);
      if (mime == null || bytes.length > 8 * 1024 * 1024) _unsupported();
      _attribute('href', 'data:$mime;base64,${base64Encode(bytes)}');
    }

    _output.write('>');
    for (final child in node.nodes) {
      _draw(child, depth + 1, inText: inText || tag == 'text');
    }
    _output.write('</$renderedTag>');
  }

  String? build(dom.Element body) {
    _findRoot(body, 0);
    final svg = _root;
    if (svg == null || !svg.querySelectorAll('text').any(_hasRenderedText)) {
      return null;
    }
    _draw(svg, 0);
    // Bitmap-only wrappers already have a cheaper native rendering path.
    if (_images != 1 || _texts == 0) return null;
    return '''<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'none'; base-uri 'none'; form-action 'none'">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
html body.shiori-svg-page{padding:0!important;overflow:hidden;}
body.shiori-svg-page>svg{display:block;width:100%;height:100vh;}
</style></head><body class="shiori-svg-page">$_output</body></html>''';
  }
}
