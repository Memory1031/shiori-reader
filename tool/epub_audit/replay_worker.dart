import 'dart:convert';
import 'dart:io';
import 'audit.dart';
import 'replay.dart';
import 'report.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    exitCode = 64;
    return;
  }
  Json result;
  try {
    final request = await boundedJson(File(args[0]), maxBytes: 1024 * 1024);
    if (request['action'] == 'capture') {
      final input = await authorizedFile(
        request['input'] as String,
        request['allowRoot'] as String,
        maxBytes: 64 * 1024 * 1024,
      );
      final snapshot = await produce(await input.readAsBytes());
      if (request['epubHash'] != null && snapshot.hash != request['epubHash']) {
        throw const FormatException('Input changed');
      }
      await writeBundle(snapshot, Directory(request['bundleOut'] as String));
      result = {
        'status': 'captured',
        'epubHash': snapshot.hash,
        'producer': snapshot.producer,
      };
    } else if (request['action'] == 'evaluate') {
      final snapshot = await readBundle(
        request['bundle'] as String,
        request['allowRoot'] as String,
      );
      result = auditParsed(snapshot.parser, snapshot.parsed)
        ..['sha256'] = snapshot.hash
        ..['producer'] = snapshot.producer;
    } else {
      throw const FormatException('Unknown replay action');
    }
  } catch (_) {
    result = emptyBook('replay_rejected')
      ..['failureCategory'] =
          'invalid_input_identity_budget_or_production_rejection';
    exitCode = 65;
  }
  await File(args[1]).writeAsString(jsonEncode(result), flush: true);
}
