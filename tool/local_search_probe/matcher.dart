import 'package:shiori/domain/contracts/local_books.dart';
import 'package:shiori/domain/models/models.dart';

/// Experimental source-text scan; never called by the application.
final class ProbeBlock {
  const ProbeBlock(
    this.chapter,
    this.revision,
    this.key,
    this.index,
    this.text, {
    this.sourceOffset = 0,
    this.ownedUnits,
  });
  final ChapterKey chapter;
  final String revision, key, text;
  final int index;

  /// Original-block code-point offset of a batch slice.
  final int sourceOffset;

  /// Only match starts below this UTF-16 boundary belong to the slice.
  final int? ownedUnits;
}

/// Reading order first; non-linear and auxiliary chapters follow stored order.
List<ProbeBlock> snapshot(LocalBookContent book) {
  final chapters = {for (final c in book.chapters) c.key: c};
  final order = <ChapterKey>{
    ...?book.readingOrder,
    if (book.readingOrder == null)
      ...book.catalog.flatChapters.map((c) => c.key),
    ...book.chapters.map((c) => c.key),
  };
  return [
    for (final c in [
      ...order.map((key) => chapters[key]!),
      ...book.auxiliaryChapters,
    ])
      for (var i = 0; i < c.blocks.length; i++)
        if (c.blocks[i]
            case ParagraphBlock(:final text) || HeadingBlock(:final text))
          ProbeBlock(c.key, c.contentRevision, c.blocks[i].blockKey, i, text),
  ];
}

final class ProbeHit {
  ProbeHit(ProbeBlock block, this.start, this.end, this.snippet)
    : chapter = block.chapter,
      revision = block.revision,
      blockKey = block.key,
      blockIndex = block.index;
  final ChapterKey chapter;
  final String revision, blockKey;
  final int blockIndex;

  /// Half-open original-block Unicode code-point range.
  final int start, end;
  final String snippet;
}

final _asciiUpper = RegExp('[A-Z]');
String _fold(String text) => text.replaceAllMapped(
  _asciiUpper,
  (match) => String.fromCharCode(match[0]!.codeUnitAt(0) + 32),
);

int _count(String text, int start, int end) {
  var count = 0;
  for (var i = start; i < end; i++, count++) {
    final u = text.codeUnitAt(i);
    if (u >= 0xd800 &&
        u <= 0xdbff &&
        i + 1 < end &&
        text.codeUnitAt(i + 1) >= 0xdc00 &&
        text.codeUnitAt(i + 1) <= 0xdfff) {
      i++;
    }
  }
  return count;
}

int _step(String text, int index, int count) {
  for (var n = 0; n < count.abs(); n++) {
    if (count < 0) {
      if (index == 0) break;
      index--;
      if (index > 0 &&
          text.codeUnitAt(index) >= 0xdc00 &&
          text.codeUnitAt(index) <= 0xdfff &&
          text.codeUnitAt(index - 1) >= 0xd800 &&
          text.codeUnitAt(index - 1) <= 0xdbff) {
        index--;
      }
    } else {
      if (index == text.length) break;
      final u = text.codeUnitAt(index++);
      if (u >= 0xd800 &&
          u <= 0xdbff &&
          index < text.length &&
          text.codeUnitAt(index) >= 0xdc00 &&
          text.codeUnitAt(index) <= 0xdfff) {
        index++;
      }
    }
  }
  return index;
}

({List<ProbeHit> hits, int count}) scan(
  List<ProbeBlock> blocks,
  String query, {
  int limit = 1000,
}) {
  if (limit < 0) throw ArgumentError.value(limit, 'limit');
  if (query.isEmpty || query.contains('\ufffc')) return (hits: [], count: 0);
  final needle = _fold(query);
  final hits = <ProbeHit>[];
  var count = 0;
  for (final block in blocks) {
    final folded = _fold(block.text);
    var from = 0, previous = 0, offset = 0;
    while (true) {
      final found = folded.indexOf(needle, from);
      if (found < 0 || found >= (block.ownedUnits ?? block.text.length)) break;
      count++;
      if (hits.length < limit) {
        offset += _count(block.text, previous, found);
        final end = found + needle.length;
        hits.add(
          ProbeHit(
            block,
            block.sourceOffset + offset,
            block.sourceOffset + offset + _count(block.text, found, end),
            block.text.substring(
              _step(block.text, found, -24),
              _step(block.text, end, 24),
            ),
          ),
        );
        previous = found;
      }
      from = found + 1;
    }
  }
  return (hits: hits, count: count);
}
