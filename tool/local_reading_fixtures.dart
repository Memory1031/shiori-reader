// Self-authored offline system-picker fixtures; output is never production data.
import 'dart:convert';
import 'dart:io';
import '../test/data/local/support/epub_fixtures.dart';

void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('Pass an output directory');
  final dir = Directory(args.single)..createSync(recursive: true);
  File('${dir.path}/local005.txt').writeAsStringSync(
    '第一章 星光\n${List.generate(60, (i) => '星光正文第 $i 段。离线阅读无需网络。').join('\n')}\n第二章 日出\n日出正文，第二章验证。',
  );
  final files = epubFiles();
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><body><h1>第一章 星海</h1><p id="one">第一段正文。</p>'
    '${List.generate(60, (i) => '<p>星海正文第 $i 段。离线正文。</p>').join()}'
    '<h2 id="two">片段目标星星</h2><img src="../images/%E6%98%9F%20%E7%A9%BA.png" alt="星星"/><p>片段后的正文。</p></body></html>',
  );
  File('${dir.path}/local005.epub').writeAsBytesSync(zipFiles(files));
}
