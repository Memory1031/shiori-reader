import '../../../domain/models/models.dart';

/// Undo only floating-point round-trip noise at an integer character boundary.
/// Flooring e.g. 63000 / total * total must not drift to the preceding line on
/// every reopen. Genuine fractional offsets still round down.
int readerCharacterOffset(double fraction, int total) {
  final value = fraction * total;
  final integer = value.round();
  return (value - integer).abs() < 1e-7 ? integer : value.floor();
}

/// Resolve persistent semantic identity before any transient render chunks exist.
/// Pixel hints are deliberately ignored: the lazy pivot does not have a stable
/// document-wide scroll origin, even when typography settings are identical.
({ReaderPosition position, bool usedFallback}) resolveReaderPosition(
  ChapterContent content,
  ReaderPosition saved,
) {
  var block =
      saved.contentRevision == content.contentRevision &&
          saved.blockIndex < content.blocks.length &&
          content.blocks[saved.blockIndex].blockKey == saved.blockKey
      ? saved.blockIndex
      : content.blocks.indexWhere((b) => b.blockKey == saved.blockKey);
  final fallback = block < 0;
  var fraction = saved.blockFraction;
  if (fallback) {
    final coarse = saved.chapterFraction * content.blocks.length;
    block = coarse.floor().clamp(0, content.blocks.length - 1);
    fraction = (coarse - block).clamp(0, 1);
  }
  return (
    position: ReaderPosition(
      contentRevision: content.contentRevision,
      blockKey: content.blocks[block].blockKey,
      blockIndex: block,
      blockFraction: fraction,
      chapterFraction: ReaderPosition.fractionFor(
        blockIndex: block,
        blockFraction: fraction,
        blockCount: content.blocks.length,
      ),
    ),
    usedFallback: fallback,
  );
}
