import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'audit.dart';
import 'report.dart';

Future<void> main(List<String> args) async {
  if (args.length != 6) {
    exitCode = 64;
    return;
  }
  final file = File(args[0]);
  final watch = Stopwatch()..start();
  Json result;
  try {
    final options = AuditOptions(
      maxDocuments: int.parse(args[3]),
      maxEvents: int.parse(args[4]),
      maxFindings: int.parse(args[5]),
    );
    if (await file.length() > BookDecoder.maxEpubBytes) {
      result = emptyBook('production_rejected')
        ..['failureCategory'] = 'tooLarge';
    } else {
      final builder = BytesBuilder(copy: false);
      var tooLarge = false;
      await for (final chunk in file.openRead()) {
        if (builder.length + chunk.length > BookDecoder.maxEpubBytes) {
          tooLarge = true;
          break;
        }
        builder.add(chunk);
      }
      if (tooLarge) {
        result = emptyBook('production_rejected')
          ..['failureCategory'] = 'tooLarge';
      } else {
        final bytes = builder.takeBytes();
        if (sha256.convert(bytes).toString() != args[2]) {
          result = emptyBook('input_changed')
            ..['failureCategory'] = 'input_changed_after_inventory';
        } else {
          result = auditBytes(bytes, options: options);
        }
      }
    }
  } on FileSystemException {
    result = emptyBook('input_read_failure');
  } catch (_) {
    result = emptyBook('audit_exception');
  }
  result['elapsedMs'] = watch.elapsedMilliseconds;
  await File(args[1]).writeAsString(jsonEncode(result), flush: true);
}
