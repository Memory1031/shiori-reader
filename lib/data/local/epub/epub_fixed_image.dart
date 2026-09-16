import 'package:html/dom.dart' as dom;
import '../../../domain/contracts/local_book_decoder.dart';

/// The supported fixed-page subset is one raster candidate plus plain
/// containers and explicitly unpainted SVG link rectangles. Hotspots are
/// intentionally discarded, not converted to whole-image links.
dom.Element epubFixedImage(dom.Document doc, Iterable<String> sheets) {
  Never unsupported() =>
      throw const LocalParseException(LocalParseProblem.fixedLayout);

  // Do not infer transparency from a presentation attribute if author CSS
  // could override it, add a stroke, generated content, or another layer.
  // This deliberately accepts a small CSS subset, not arbitrary FXL styling.
  const layoutProperties = {
    'margin',
    'margin-top',
    'margin-right',
    'margin-bottom',
    'margin-left',
    'padding',
    'padding-top',
    'padding-right',
    'padding-bottom',
    'padding-left',
    'width',
    'height',
    'min-width',
    'min-height',
    'max-width',
    'max-height',
    'font-size',
    'line-height',
    'text-align',
    'vertical-align',
    'box-sizing',
    'position',
    'top',
    'right',
    'bottom',
    'left',
    '-webkit-text-combine',
  };
  void checkCss(String css) {
    final cleaned = css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    for (final declaration in RegExp(
      r'(?:^|[;{}])\s*([^;{}:]+):',
    ).allMatches(cleaned)) {
      if (!layoutProperties.contains(declaration[1]!.trim().toLowerCase())) {
        unsupported();
      }
    }
  }

  for (final sheet in sheets) {
    checkCss(sheet);
  }
  dom.Element? image;
  const containers = {
    'html',
    'body',
    'div',
    'main',
    'p',
    'section',
    'article',
    'figure',
    'span',
    'a',
    'svg',
  };
  void walk(dom.Node node) {
    if (node is dom.Text) {
      if (node.text.trim().isNotEmpty) unsupported();
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName;
    if ({'head', 'script', 'style'}.contains(tag)) return;
    if (node.attributes['style'] case final css?) checkCss(css);
    for (final name in [
      'transform',
      'clip-path',
      'mask',
      'filter',
      'opacity',
      'visibility',
      'display',
      'hidden',
    ]) {
      if (node.attributes.containsKey(name)) unsupported();
    }
    if (tag == 'rect') {
      final link = node.parent;
      final svg = link?.parent;
      final href =
          link?.attributes['href'] ??
          link?.attributes['xlink:href'] ??
          link?.attributes[const dom.AttributeName(
            'xlink',
            'href',
            'http://www.w3.org/1999/xlink',
          )];
      final fill = node.attributes['fill']?.trim().toLowerCase();
      final fillOpacity = double.tryParse(
        node.attributes['fill-opacity'] ?? '',
      );
      final stroke = node.attributes['stroke']?.trim().toLowerCase();
      if (node.namespaceUri != 'http://www.w3.org/2000/svg' ||
          link?.localName != 'a' ||
          svg?.localName != 'svg' ||
          href == null ||
          href.trim().isEmpty ||
          !(fill == 'none' || fillOpacity == 0) ||
          stroke != null && stroke != 'none' ||
          node.nodes.isNotEmpty) {
        unsupported();
      }
      return;
    }
    // Inherited SVG paint must not turn a transparent rectangle into artwork.
    if (node.attributes.keys.any(
      (a) => {
        'fill',
        'fill-opacity',
        'stroke',
        'stroke-opacity',
        'stroke-width',
      }.contains(a.toString()),
    )) {
      unsupported();
    }
    if (tag == 'img' || tag == 'image') {
      if (image != null || node.nodes.isNotEmpty) unsupported();
      image = node;
      return;
    }
    if (!containers.contains(tag)) unsupported();
    for (final child in node.nodes) {
      walk(child);
    }
  }

  walk(doc.documentElement!);
  return image ?? unsupported();
}
