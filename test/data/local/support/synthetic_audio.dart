import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'epub_fixtures.dart';

Uint8List syntheticWav({int seconds = 1}) {
  const rate = 8000;
  final samples = rate * seconds;
  final result = Uint8List(44 + samples * 2), data = ByteData(44 + samples * 2);
  void word(int at, String text) {
    result.setRange(at, at + text.length, ascii.encode(text));
  }

  word(0, 'RIFF');
  word(8, 'WAVE');
  word(12, 'fmt ');
  word(36, 'data');
  data.setUint32(4, result.length - 8, Endian.little);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(
      44 + i * 2,
      (math.sin(2 * math.pi * 440 * i / rate) * 4000).round(),
      Endian.little,
    );
  }
  result.setRange(4, 8, data.buffer.asUint8List().sublist(4, 8));
  result.setRange(16, 36, data.buffer.asUint8List().sublist(16, 36));
  result.setRange(40, result.length, data.buffer.asUint8List().sublist(40));
  return result;
}

Uint8List audioEpubBytes(
  String body, {
  Map<String, List<int>> resources = const {},
}) {
  final files = epubFiles();
  final opf = utf8.decode(files['OPS/book.opf']!);
  files['OPS/book.opf'] = utf8.encode(
    opf.replaceFirst(
      '</manifest>',
      '<item id="sound" href="audio/test.wav" media-type="audio/wav"/></manifest>',
    ),
  );
  files['OPS/audio/test.wav'] = syntheticWav();
  files.addAll(resources);
  files['OPS/text/a.xhtml'] = utf8.encode('<html><body>$body</body></html>');
  return zipFiles(files);
}

ParsedEpub audioEpub(
  String body, {
  Map<String, List<int>> resources = const {},
}) => EpubParser(
  audioEpubBytes(body, resources: resources),
  LocalBookIdentity.book('a' * 64),
  'synthetic.epub',
).parse();
