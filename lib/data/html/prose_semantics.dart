/// Shared text semantics only. Resource resolution and DOM ownership stay with
/// each source adapter; this module has no network, storage or Flutter imports.
enum ProseWhiteSpace { normal, pre, preWrap, preLine }

ProseWhiteSpace proseWhiteSpace(String? css, ProseWhiteSpace inherited) =>
    switch (css) {
      'normal' || 'nowrap' || 'initial' => ProseWhiteSpace.normal,
      'pre' => ProseWhiteSpace.pre,
      'pre-wrap' => ProseWhiteSpace.preWrap,
      'pre-line' => ProseWhiteSpace.preLine,
      _ => inherited,
    };

int? proseHeadingLevel(String? tag) =>
    RegExp(r'^h[1-6]$').hasMatch(tag ?? '') ? int.parse(tag![1]) : null;

/// Keep authored wide spaces and NBSP. Explicit br is written separately from
/// source whitespace so normal mode never collapses a requested line break.
class ProseTextBuffer {
  final _buffer = StringBuffer();
  bool _preserved = false;
  bool _pendingSpace = false;
  bool _lineStart = true;

  void text(String value, ProseWhiteSpace mode) {
    value = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    switch (mode) {
      case ProseWhiteSpace.pre:
      case ProseWhiteSpace.preWrap:
        _preserved = true;
      case ProseWhiteSpace.preLine:
        for (final rune in value.runes) {
          if (rune == 32 || rune == 9 || rune == 12) {
            _pendingSpace = !_lineStart;
          } else {
            write(String.fromCharCode(rune));
          }
        }
        return;
      case ProseWhiteSpace.normal:
        value = value.replaceAll(RegExp(r'[ \t\n\f]+'), ' ');
    }
    write(value);
  }

  void write(String value) {
    if (value.isEmpty) return;
    if (_pendingSpace && !value.startsWith('\n')) _buffer.write(' ');
    _pendingSpace = false;
    _buffer.write(value);
    _lineStart = value.endsWith('\n');
  }

  String take() {
    final value = _buffer.toString();
    final preserve = _preserved;
    _buffer.clear();
    _preserved = false;
    _pendingSpace = false;
    _lineStart = true;
    return preserve
        ? value
        : value.replaceAll(RegExp(r'^[ \t\r\n\f]+|[ \t\r\n\f]+$'), '');
  }
}
