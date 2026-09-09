import 'dart:convert';
import 'package:html/dom.dart' as dom;

/// Deterministic offline selection, not responsive browser layout. Try eligible
/// picture sources in document order, then the existing img src, then srcset.
/// Unknown viewport conditions are not guessed. No URL is fetched here.
Iterable<String> epubImageCandidates(dom.Element image) sync* {
  final picture = image.parent;
  if (picture?.localName == 'picture') {
    for (final source in picture!.children) {
      if (source == image) break;
      if (source.localName != 'source') continue;
      final type = (source.attributes['type'] ?? '').trim().toLowerCase();
      if (type.isNotEmpty &&
          !{
            'image/png',
            'image/jpeg',
            'image/gif',
            'image/webp',
          }.contains(type)) {
        continue;
      }
      final media = (source.attributes['media'] ?? '').trim().toLowerCase();
      if (media.isNotEmpty &&
          !media.split(',').any((m) => {'all', 'screen'}.contains(m.trim()))) {
        continue;
      }
      yield* _srcset(source.attributes['srcset'] ?? '');
    }
  }
  final src =
      image.attributes['src'] ??
      image.attributes['href'] ??
      image.attributes['xlink:href'] ??
      image.attributes[const dom.AttributeName(
        'xlink',
        'href',
        'http://www.w3.org/1999/xlink',
      )];
  if (src != null && src.trim().isNotEmpty) yield src;
  yield* _srcset(image.attributes['srcset'] ?? '');
}

/// URLs may contain commas; only trailing commas or descriptor separators end
/// a candidate. This deliberately supports one positive w/x descriptor only.
Iterable<String> _srcset(String input) sync* {
  if (input.length > 65536) return;
  var at = 0, count = 0;
  bool space(int c) => c == 32 || c == 9 || c == 10 || c == 12 || c == 13;
  while (at < input.length && count++ < 128) {
    while (at < input.length &&
        (space(input.codeUnitAt(at)) || input[at] == ',')) {
      at++;
    }
    final start = at;
    while (at < input.length && !space(input.codeUnitAt(at))) {
      at++;
    }
    var url = input.substring(start, at);
    if (url.isEmpty) return;
    if (url.endsWith(',')) {
      url = url.replaceFirst(RegExp(r',+$'), '');
      if (url.isNotEmpty) yield url;
      continue;
    }
    final descriptorStart = at;
    while (at < input.length && input[at] != ',') {
      at++;
    }
    final descriptor = input.substring(descriptorStart, at).trim();
    if (at < input.length) at++;
    if (descriptor.isNotEmpty) {
      final match = RegExp(
        r'^((?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?)([wx])$',
      ).firstMatch(descriptor);
      if (match == null) continue;
      final value = double.tryParse(match[1]!);
      if (value == null || !value.isFinite || value <= 0) continue;
      if (match[2] == 'w' && !RegExp(r'^\d+$').hasMatch(match[1]!)) {
        continue;
      }
    }
    yield url;
  }
}

/// Shared byte signature recognition for native media and inert img resources.
String? epubRasterMime(List<int> b) {
  if (b.length < 4) return null;
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) {
    return 'image/png';
  }
  if (b[0] == 0xff && b[1] == 0xd8) return 'image/jpeg';
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
  if (b.length >= 12 &&
      ascii.decode(b.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(b.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}
