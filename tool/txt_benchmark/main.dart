import 'dart:convert';
import 'dart:io';
import 'package:shiori/data/local/txt/txt_decoder.dart';
import 'package:shiori/data/local/txt/txt_parser.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/local_books.dart';

void main(List<String> args) {
  final mib = int.parse(args[0]);
  final shape = args.length > 1 ? args[1] : 'lines';
  final size = mib * 1024 * 1024;
  // ASCII keeps exact byte sizes; CJK/emoji correctness has separate fixtures.
  final unit = shape == 'single' ? 'x' : '${'ordinary text ' * 36}\n';
  final text = (unit * (size ~/ unit.length + 1)).substring(0, size);
  final bytes = utf8.encode(text);
  final clock = Stopwatch()..start();
  final decoded = decodeTxt(bytes, TxtEncoding.utf8);
  final decodeMs = clock.elapsedMilliseconds;
  clock.reset();
  final preview = inspectTxt(bytes, null);
  final probeMs = clock.elapsedMilliseconds;
  clock.reset();
  final result = parseTxt(
    bytes,
    LocalBookIdentity.book('a' * 64),
    'synthetic.txt',
    TxtEncoding.utf8,
  );
  final parseMs = clock.elapsedMilliseconds;
  stdout.writeln(
    jsonEncode({
      'mib': mib,
      'shape': shape,
      'decodeMs': decodeMs,
      'probeMs': probeMs,
      'parseMs': parseMs,
      'peakRssBytes': ProcessInfo.maxRss,
      'chapters': result.chapters.length,
      'blocks': result.chapters.fold<int>(0, (n, c) => n + c.blocks.length),
      'decodedUnits': decoded.length,
      'candidates': preview.samples.length,
    }),
  );
}
