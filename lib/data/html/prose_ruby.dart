import 'package:html/dom.dart';
import '../../domain/models/models.dart';

/// Common group/mono ruby. Complex, nested or interactive markup uses the
/// caller's existing base + parenthetical annotation fallback.
List<({List<Node> base, String annotation})>? proseRuby(Element ruby) {
  const inline = {'rb', 'rt', 'rp', 'span', 'b', 'strong', 'i', 'em', 'u'};
  if (ruby.querySelectorAll('*').any((e) => !inline.contains(e.localName))) {
    return null;
  }
  final pairs = <({List<Node> base, String annotation})>[];
  var base = <Node>[];
  for (final node in ruby.nodes) {
    if (node is! Text && node is! Element) continue;
    if (node is Element && node.localName == 'rp') continue;
    if (node is Element && node.localName == 'rt') {
      final annotation = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final text = base.map((n) => n.text ?? '').join().trim();
      if (text.isEmpty ||
          annotation.isEmpty ||
          text.runes.length > 64 ||
          annotation.runes.length > 256) {
        return null;
      }
      pairs.add((base: base, annotation: annotation));
      base = [];
    } else {
      // rt/rp must be direct children; otherwise the pairing is ambiguous.
      if (node is Element && node.querySelector('rt, rp') != null) return null;
      base.add(node);
    }
  }
  if (pairs.isEmpty || base.any((n) => (n.text ?? '').trim().isNotEmpty)) {
    return null;
  }
  return pairs;
}

/// Record buffer UTF-16 offsets, then normalize to emitted code-point ranges.
final class ProseRubyRanges {
  final _ranges = <(int, int, String)>[];
  void add(int start, int end, String annotation) {
    if (end > start) _ranges.add((start, end, annotation));
  }

  List<InlineRuby> take(String raw, String text) {
    final trim = raw.indexOf(text);
    final result = <InlineRuby>[];
    for (final (from, to, annotation) in _ranges) {
      var start = (from - trim).clamp(0, text.length);
      var end = (to - trim).clamp(0, text.length);
      while (start < end && text[start].trim().isEmpty) {
        start++;
      }
      while (end > start && text[end - 1].trim().isEmpty) {
        end--;
      }
      if (start < end && !text.substring(start, end).contains('\n')) {
        result.add(
          InlineRuby(
            start: text.substring(0, start).runes.length,
            length: text.substring(start, end).runes.length,
            annotation: annotation,
          ),
        );
      }
    }
    _ranges.clear();
    return result;
  }
}
