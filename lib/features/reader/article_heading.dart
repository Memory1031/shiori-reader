bool isArticleHeading(String text) {
  final numbered = RegExp(
    r'^第[0-9０-９一二三四五六七八九十百千零〇两兩]+[话話章节節幕](?:[\s　:：、.．—－-].*)?$',
  );
  final special = RegExp(
    r'^(?:序章|序幕|后记|後記|尾声|尾聲|终章|終章|幕间|幕間|プロローグ|エピローグ)(?:[\s　:：、.．—－-].*)?$',
  );
  bool recognise(String text) {
    if (text.runes.length > 100) return false;
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    // Some uploads put a short day marker on a separate line in the same block.
    if (lines.length > 2 || lines.isEmpty) return false;
    if (lines.length == 2 &&
        !RegExp(
          r'^[（(]Day\s*[0-9０-９]+[）)]$',
          caseSensitive: false,
        ).hasMatch(lines.last)) {
      return false;
    }
    var candidate = lines.first;
    const pairs = {'【': '】', '[': ']', '「': '」', '『': '』', '（': '）', '(': ')'};
    final closing = pairs[candidate.substring(0, 1)];
    if (closing != null) {
      final end = candidate.indexOf(closing, 1);
      if (end < 0) return false;
      final marker = candidate.substring(1, end).trim();
      if (!numbered.hasMatch(marker) && !special.hasMatch(marker)) return false;
      candidate = '$marker ${candidate.substring(end + 1).trim()}'.trim();
    }
    return numbered.hasMatch(candidate) || special.hasMatch(candidate);
  }

  return recognise(text);
}
