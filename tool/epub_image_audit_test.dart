// Explicit host Flutter codec check; never part of the ordinary test suite.
// EPUB_AUDIT_INPUT=<paths.json> EPUB_AUDIT_OUTPUT=<output.json> flutter test tool/epub_image_audit_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/models/models.dart';

void main() {
  test(
    'explicit local EPUB images decode on the host',
    () async {
      final input = Platform.environment['EPUB_AUDIT_INPUT'];
      final output = Platform.environment['EPUB_AUDIT_OUTPUT'];
      if (input == null || output == null) {
        throw ArgumentError('Explicit audit paths required');
      }
      final paths = (jsonDecode(await File(input).readAsString()) as List)
          .cast<String>();
      final seen = <String>{}, failed = <String>{};
      final books = <Map<String, Object?>>[];
      for (final path in paths) {
        final bytes = await File(path).readAsBytes();
        final hash = sha256.convert(bytes).toString();
        final row = <String, Object?>{'sha256': hash};
        books.add(row);
        ParsedEpub parsed;
        try {
          parsed = EpubParser(
            bytes,
            NovelKey(sourceId: SourceId('local'), novelId: hash),
            'audit.epub',
            includePresentations: true,
          ).parse();
        } catch (_) {
          row['status'] = 'notParsed';
          continue;
        }
        var failures = 0;
        for (final image in parsed.media.entries) {
          if (seen.add(image.key)) {
            ui.Codec? codec;
            try {
              codec = await ui.instantiateImageCodec(
                image.value,
                targetWidth: 32,
              );
              final frame = await codec.getNextFrame();
              frame.image.dispose();
            } catch (_) {
              failed.add(image.key);
            } finally {
              codec?.dispose();
            }
          }
          if (failed.contains(image.key)) failures++;
        }
        row.addAll({
          'status': 'parsed',
          'images': parsed.media.length,
          'decodeFailures': failures,
        });
      }
      await File(output).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'scope':
              'Host Flutter first-frame decode at width 32; not device visual QA',
          'uniqueImages': seen.length,
          'failedImageHashes': failed.toList(),
          'samples': books,
        }),
      );
      expect(failed, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
