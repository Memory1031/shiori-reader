import 'package:html/dom.dart' as dom;
import 'report.dart';

/// Independent source expectation, deliberately narrower than SVG rendering.
/// Unknown geometry remains an observation rather than an invented contract.
Json sourceImageExpectation(
  dom.Element image,
  Map<dom.Element, Map<String, String>> styles,
  int? width,
  int? height, {
  bool stylesSafe = true,
}) {
  String? alignment;
  for (
    var owner = image.parent;
    owner != null && alignment == null;
    owner = owner.parent
  ) {
    alignment = switch (styles[owner]?['text-align']) {
      'center' => 'center',
      'left' || 'start' => 'start',
      'right' || 'end' => 'end',
      _ => null,
    };
  }
  var basis = alignment == null ? 'unknown_author_intent' : 'source_text_align';
  final svg = image.parent;
  if (stylesSafe &&
      alignment == null &&
      image.localName == 'image' &&
      svg?.localName == 'svg' &&
      svg!.children.length == 1 &&
      width != null &&
      height != null) {
    final view = (svg.attributes['viewBox'] ?? '').trim().split(
      RegExp(r'[\s,]+'),
    );
    bool dimension(dom.Element n, String name, String value) =>
        (styles[n]?[name] ?? n.attributes[name]) == value;
    final simple =
        view.length == 4 &&
        double.tryParse(view[0]) == 0 &&
        double.tryParse(view[1]) == 0 &&
        double.tryParse(view[2]) == width &&
        double.tryParse(view[3]) == height &&
        dimension(svg, 'width', '100%') &&
        dimension(svg, 'height', '100%') &&
        double.tryParse(image.attributes['width'] ?? '') == width &&
        double.tryParse(image.attributes['height'] ?? '') == height &&
        double.tryParse(image.attributes['x'] ?? '0') == 0 &&
        double.tryParse(image.attributes['y'] ?? '0') == 0 &&
        [svg, image].every(
          (n) => ['transform', 'clip-path', 'mask', 'filter'].every(
            (k) =>
                !n.attributes.containsKey(k) &&
                (styles[n]?[k] == null || styles[n]?[k] == 'none'),
          ),
        ) &&
        ['width', 'height'].every(
          (k) =>
              styles[image]?[k] == null ||
              double.tryParse(styles[image]![k]!) ==
                  (k == 'width' ? width : height),
        ) &&
        (image.attributes['preserveAspectRatio'] == null ||
            image.attributes['preserveAspectRatio'] == 'xMidYMid meet');
    if (simple) {
      alignment = switch ((svg.attributes['preserveAspectRatio'] ??
              'xMidYMid meet')
          .trim()) {
        'xMidYMid' || 'xMidYMid meet' => 'center',
        'xMinYMid' || 'xMinYMid meet' => 'start',
        'xMaxYMid' || 'xMaxYMid meet' => 'end',
        _ => null,
      };
      if (alignment != null) basis = 'source_single_raster_svg_meet';
    }
  }
  return {
    'encodedNaturalSize': {'width': width, 'height': height},
    'expectedAlignment': alignment,
    'alignmentBasis': basis,
    'aspectClass': width == null || height == null
        ? 'unknown'
        : height / width >= 5
        ? 'tall_narrow'
        : width > height
        ? 'landscape'
        : 'portrait',
  };
}
