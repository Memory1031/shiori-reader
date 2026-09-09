/// Bounded, line-oriented structural analysis. Offsets here are UTF-16 indices
/// only for slicing; persistent identity is counted separately in code points.
final class TxtLine {
  const TxtLine(this.start, this.end);
  final int start, end;
}

List<TxtLine> txtLines(String text, void Function() tooMany) {
  final result = <TxtLine>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c != 10 && c != 13) continue;
    if (c == 13 && i + 1 < text.length && text.codeUnitAt(i + 1) == 10) i++;
    result.add(TxtLine(start, i + 1));
    start = i + 1;
    if (result.length > 100000) tooMany();
  }
  if (start < text.length) result.add(TxtLine(start, text.length));
  if (result.length > 100000) tooMany();
  return result;
}

final _numbered = RegExp(
  r'^(第[零〇一二三四五六七八九十百千万萬两兩壹贰貳叁參肆伍陆陸柒捌玖拾佰仟0-9０-９点之上下中外附番.\-]+[章节節回卷部集话話]|卷[一二三四五六七八九十百0-9０-９]+|(?:chapter|part|volume)\s+[0-9ivxlcdm]+)(.*)$',
  caseSensitive: false,
);
final _named = RegExp(
  r'^(序章|楔子|序言|前言|后记|後記|终章|終章|尾声|尾聲|番外|特典|间章|間章|幕间|幕間|prologue|epilogue)(.*)$',
  caseSensitive: false,
);
final _sentence = RegExp(r'[。！？!?；;]|(?:的时候|的時候|的时候|という|について)');

/// Exact headings remain valid alone. Attached subtitles need independent
/// context; dense speculative candidates are left as prose rather than split.
Set<int> txtHeadingLines(String text, List<TxtLine> lines) {
  final candidates = <(int, int, String)>[];
  final families = <String, int>{};
  bool blank(int i) =>
      i < 0 ||
      i >= lines.length ||
      text.substring(lines[i].start, lines[i].end).trim().isEmpty;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    // Do not regex or copy arbitrarily long lines.
    if (line.end - line.start > 110) continue;
    final value = text.substring(line.start, line.end).trim();
    if (value.isEmpty || value.length > 100 || _sentence.hasMatch(value)) {
      continue;
    }
    final numbered = _numbered.firstMatch(value);
    final match = numbered ?? _named.firstMatch(value);
    if (match == null) continue;
    final suffix = match[2]!;
    final family = numbered == null ? 'named' : 'numbered';
    final explicit = suffix.isEmpty || RegExp(r'^[\s：:、.\-]').hasMatch(suffix);
    // Reject sentence-like tails even after an explicit separator.
    if (suffix.trimRight().endsWith('.') || suffix.contains('，')) continue;
    var score = explicit ? 4 : 1;
    if (blank(i - 1) && blank(i + 1)) score += 2;
    candidates.add((i, score, family));
    families.update(family, (n) => n + 1, ifAbsent: () => 1);
  }
  final result = <int>{};
  for (final (index, score, family) in candidates) {
    if (score >= 4 ||
        score >= 3 &&
            (families[family] ?? 0) >= 2 &&
            candidates.length <= lines.length ~/ 3) {
      result.add(index);
    }
  }
  return result;
}
