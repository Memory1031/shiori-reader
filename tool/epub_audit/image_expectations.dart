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
  ({int width, int height})? displaySize,
  bool displaySizeChecked = false,
}) {
  final encodedWidth = width, encodedHeight = height;
  // A checked null means malformed/ambiguous metadata, not orientation 1.
  if (displaySizeChecked || displaySize != null) {
    width = displaySize?.width;
    height = displaySize?.height;
  }
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
  if (alignment == null && _singleImageDocument(image, styles)) {
    alignment = 'center';
    basis = 'reader_single_image_document_default';
  }
  return {
    'encodedNaturalSize': {'width': encodedWidth, 'height': encodedHeight},
    'displayNaturalSize': {'width': width, 'height': height},
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

/// Source-only evidence for the Reader's single-ImageBlock default. Require a
/// sole ordinary raster and a chain of simple wrappers. Empty sibling blocks,
/// explicit breaks and complex SVGs remain unknown, not guessed as author CSS.
bool _singleImageDocument(
  dom.Element image,
  Map<dom.Element, Map<String, String>> styles,
) {
  if (image.localName != 'img') return false;
  dom.Element? current = image;
  while (current != null) {
    final css = styles[current] ?? const <String, String>{};
    if (current.attributes.containsKey('hidden') ||
        css['display'] == 'none' ||
        {'hidden', 'collapse'}.contains(css['visibility']) ||
        !{null, 'static', 'initial'}.contains(css['position']) ||
        !{null, 'none', 'initial'}.contains(css['float']) ||
        !{null, 'none', 'initial'}.contains(css['transform'])) {
      return false;
    }
    if (current.localName == 'body') return true;
    final parent = current.parent;
    if (parent == null ||
        !{
          'body',
          'div',
          'p',
          'figure',
          'a',
          'span',
        }.contains(parent.localName) ||
        parent.children.length != 1 ||
        parent.nodes.whereType<dom.Text>().any(
          (t) => t.text.trim().isNotEmpty,
        )) {
      return false;
    }
    current = parent;
  }
  return false;
}
