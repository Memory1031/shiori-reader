import 'dart:typed_data';
import '../../../domain/models/models.dart';
import 'epub_rich_styles.dart';
import 'epub_text_styles.dart';

/// Optional, bounded assets used by native styles. No external resource fetch.
class EpubNativeFonts {
  EpubNativeFonts(
    Iterable<(String, String)> sheets,
    String? Function(String, String) resolve,
    MediaRef? Function(String) read,
  ) {
    var faces = 0;
    for (final (base, css) in sheets) {
      for (final (selector, declaration) in epubScreenRules(
        css,
        0,
        null,
        '',
        true,
      )) {
        if (selector != '@font-face' || ++faces > 64) continue;
        final properties = <String, String>{};
        for (final part in declaration.split(';')) {
          final colon = part.indexOf(':');
          if (colon > 0) {
            properties[part.substring(0, colon).trim().toLowerCase()] = part
                .substring(colon + 1)
                .trim();
          }
        }
        final name = fontName(properties['font-family'] ?? '');
        if (name.isEmpty || name.length > 128) continue;
        final sources = properties['src'] ?? '';
        for (final url in RegExp(
          r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^\s)]+))\s*\)''',
          caseSensitive: false,
        ).allMatches(sources).take(8)) {
          final path = resolve(
            base.split('#').first,
            url[1] ?? url[2] ?? url[3]!,
          );
          if (path == null) continue;
          final ref = read(path);
          if (ref == null) continue;
          final list = _families.putIfAbsent(name, () => []);
          if (!list.contains(ref) && list.length < 8) list.add(ref);
          break; // src alternatives describe one face, not separate faces.
        }
      }
    }
  }
  final _families = <String, List<MediaRef>>{};
  List<EmbeddedFontFamily> resolve(String value) => [
    for (final name in value.split(',').take(8).map(fontName))
      if (_families[name] case final sources?) EmbeddedFontFamily(sources),
  ];
}

String fontName(String input) {
  final value = input.trim().toLowerCase();
  return value.length > 1 &&
          (value.startsWith('"') && value.endsWith('"') ||
              value.startsWith("'") && value.endsWith("'"))
      ? value.substring(1, value.length - 1)
      : value;
}

/// Structural SFNT check before handing optional data to the platform loader.
bool epubNativeFontBytes(Uint8List bytes) {
  if (bytes.length < 12 || bytes.length > 8 * 1024 * 1024) return false;
  final data = ByteData.sublistView(bytes);
  if (!{0x00010000, 0x4f54544f}.contains(data.getUint32(0))) return false;
  final count = data.getUint16(4);
  if (count == 0 || count > 128 || 12 + count * 16 > bytes.length) return false;
  final tags = <int>{};
  for (var i = 0; i < count; i++) {
    final p = 12 + i * 16;
    final offset = data.getUint32(p + 8), length = data.getUint32(p + 12);
    if (offset < 12 + count * 16 ||
        offset + length > bytes.length ||
        !tags.add(data.getUint32(p))) {
      return false;
    }
  }
  return tags.containsAll({
    0x636d6170,
    0x68656164,
    0x68686561,
    0x686d7478,
    0x6d617870,
  });
}

BlockBackgroundImage? epubBackgroundImage(
  Map<String, String> css,
  MediaRef? Function(String) image,
  ({int width, int height})? Function(MediaRef) dimensions,
) {
  final path = css['background-image'];
  if (path == null ||
      path == 'none' ||
      css['background-repeat'] != 'no-repeat' ||
      !{null, 'scroll'}.contains(css['background-attachment']) ||
      !{null, 'padding-box'}.contains(css['background-origin']) ||
      !{null, 'border-box'}.contains(css['background-clip'])) {
    return null;
  }
  final sizes = (css['background-size'] ?? 'auto').split(RegExp(r'\s+'));
  if (sizes.length == 2 && sizes.every((s) => s != 'auto')) return null;
  if (sizes.isEmpty ||
      sizes.length > 2 ||
      sizes.any(
        (s) =>
            s != 'auto' &&
            (epubLayoutLength(s) == null || epubLayoutLength(s)!.value == 0),
      )) {
    return null;
  }
  final positions = (css['background-position'] ?? '0% 0%').split(
    RegExp(r'\s+'),
  );
  if (positions.length > 2) return null;
  if (positions.length == 1) {
    if ({'top', 'bottom'}.contains(positions[0])) {
      positions.insert(0, 'center');
    } else {
      positions.add('center');
    }
  }
  if ({'top', 'bottom'}.contains(positions[0]) ||
      {'left', 'right'}.contains(positions[1])) {
    final first = positions[0];
    positions[0] = positions[1];
    positions[1] = first;
  }
  double? position(String value, bool horizontal) {
    if (value == 'center') return .5;
    if (value == (horizontal ? 'left' : 'top')) return 0;
    if (value == (horizontal ? 'right' : 'bottom')) return 1;
    if (!value.endsWith('%')) return null;
    final n = double.tryParse(value.substring(0, value.length - 1));
    return n != null && n.isFinite && n >= 0 && n <= 100 ? n / 100 : null;
  }

  final x = position(positions[0], true), y = position(positions[1], false);
  if (x == null || y == null) return null;
  final ref = image(path);
  if (ref == null) return null;
  final size = dimensions(ref);
  if (size == null) return null;
  return BlockBackgroundImage(
    media: ref,
    intrinsicWidth: size.width,
    intrinsicHeight: size.height,
    width: sizes[0] == 'auto' ? null : epubLayoutLength(sizes[0]),
    height: sizes.length == 1 || sizes[1] == 'auto'
        ? null
        : epubLayoutLength(sizes[1]),
    x: x,
    y: y,
  );
}
