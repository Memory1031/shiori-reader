import 'package:html/dom.dart' as dom;
import '../../../domain/models/models.dart';

bool epubSvgAlignmentStylesSafe(Iterable<String> styles) => styles.every(
  (css) => !RegExp(
    r'(?:^|[;{}])\s*(?:transform|clip(?:-path)?|mask(?:-[\w-]+)?|filter)\s*:',
    caseSensitive: false,
  ).hasMatch(css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')),
);

/// Preserve only the horizontal meet alignment of a full-viewport raster.
/// Other SVG geometry continues through the existing native/presentation paths.
ParagraphAlignment? epubSvgImageAlignment(
  dom.Element image,
  Map<dom.Element, Map<String, String>> styles,
  ({int width, int height})? size, {
  bool stylesSafe = true,
}) {
  final svg = image.parent;
  if (image.localName != 'image' ||
      svg?.localName != 'svg' ||
      svg!.children.length != 1 ||
      size == null ||
      !stylesSafe) {
    return null;
  }
  for (final node in [svg, image]) {
    final css = styles[node] ?? const <String, String>{};
    if (['transform', 'clip-path', 'mask', 'filter'].any(
      (name) =>
          node.attributes.containsKey(name) ||
          css[name] != null && css[name] != 'none',
    )) {
      return null;
    }
  }
  final viewport = (svg.attributes['viewBox'] ?? '')
      .trim()
      .split(RegExp(r'[\s,]+'))
      .map(double.tryParse)
      .toList();
  if (viewport.length != 4 ||
      viewport.any((v) => v == null || !v.isFinite) ||
      viewport[0] != 0 ||
      viewport[1] != 0 ||
      viewport[2] != size.width ||
      viewport[3] != size.height) {
    return null;
  }
  String? dimension(dom.Element node, String name) =>
      styles[node]?[name] ?? node.attributes[name];
  if (dimension(svg, 'width') != '100%' ||
      dimension(svg, 'height') != '100%' ||
      double.tryParse(dimension(image, 'width') ?? '') != size.width ||
      double.tryParse(dimension(image, 'height') ?? '') != size.height ||
      double.tryParse(image.attributes['x'] ?? '0') != 0 ||
      double.tryParse(image.attributes['y'] ?? '0') != 0) {
    return null;
  }
  // A second fit inside the raster can change its paint rectangle.
  final imageAspect = image.attributes['preserveAspectRatio'];
  if (imageAspect != null && imageAspect.trim() != 'xMidYMid meet') return null;
  return switch ((svg.attributes['preserveAspectRatio'] ?? 'xMidYMid meet')
      .trim()) {
    'xMidYMid' || 'xMidYMid meet' => ParagraphAlignment.center,
    'xMinYMid' || 'xMinYMid meet' => ParagraphAlignment.start,
    'xMaxYMid' || 'xMaxYMid meet' => ParagraphAlignment.end,
    _ => null,
  };
}
