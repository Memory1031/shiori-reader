import 'package:html/dom.dart' as dom;

bool _semantic(dom.Element node, String value) {
  if ((node.attributes['role'] ?? '')
      .split(RegExp(r'\s+'))
      .contains('doc-$value')) {
    return true;
  }
  for (final entry in node.attributes.entries) {
    final parts = entry.key.toString().split(':');
    if (parts.length != 2 || parts.last != 'type') continue;
    String? namespace;
    for (dom.Element? parent = node; parent != null; parent = parent.parent) {
      namespace = parent.attributes['xmlns:${parts.first}'];
      if (namespace != null) break;
    }
    if ((namespace == 'http://www.idpf.org/2007/ops' ||
            namespace == null && parts.first == 'epub') &&
        entry.value.split(RegExp(r'\s+')).contains(value)) {
      return true;
    }
  }
  return false;
}

bool epubNoteref(dom.Element node) =>
    node.localName == 'a' &&
    (_semantic(node, 'noteref') || node.classes.contains('duokan-footnote'));

bool epubFootnote(dom.Element node) =>
    _semantic(node, 'footnote') || _semantic(node, 'endnote');

Map<String, dom.Element> epubNoteTargets(dom.Document document) {
  final result = <String, dom.Element>{};
  for (final node in document.querySelectorAll('[id]')) {
    result.putIfAbsent(node.id, () => node);
  }
  return result;
}

/// Plain, inert note text. Hidden note containers are intentional popup sources;
/// scripts, styles and explicit backlinks do not become annotation content.
String? epubFootnoteText(dom.Element node) {
  final buffer = StringBuffer();
  var exceeded = false;
  void walk(dom.Node current) {
    if (exceeded) return;
    if (current is dom.Text) {
      if (buffer.length + current.text.length > 16384) {
        exceeded = true;
        return;
      }
      buffer.write(current.text);
    } else if (current is dom.Element) {
      if ({
            'script',
            'style',
            'iframe',
            'object',
            'audio',
            'video',
          }.contains(current.localName) ||
          _semantic(current, 'backlink')) {
        return;
      }
      final block = {'p', 'li', 'div', 'br'}.contains(current.localName);
      if (block) buffer.write('\n');
      for (final child in current.nodes) {
        walk(child);
      }
      if (block) buffer.write('\n');
    }
  }

  walk(node);
  if (exceeded) return null;
  final text = buffer
      .toString()
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
  return text.isEmpty ? null : text;
}

String epubFootnoteMarker(int number) =>
    '⁽${number.toString().split('').map((digit) => '⁰¹²³⁴⁵⁶⁷⁸⁹'[int.parse(digit)]).join()}⁾';
