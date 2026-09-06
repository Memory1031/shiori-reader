import 'dart:convert';
import 'dart:io';

import 'package:shiori_source_probe/source_probe.dart';

Future<void> main(List<String> args) async {
  try {
    var live = false;
    var limit = 30;
    String? reportPath;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--live':
          live = true;
        case '--max-requests':
          require(i + 1 < args.length, 'invalid_arguments');
          limit = int.tryParse(args[++i]) ?? 0;
        case '--report':
          require(i + 1 < args.length, 'invalid_arguments');
          reportPath = args[++i];
        case '--help':
          stdout.writeln(
            'dart run bin/source_probe.dart [--live] '
            '[--max-requests 1..30] [--report path.json]\n'
            'Default: offline fixtures only, zero HTTP. Live: fixed book 31607, '
            'serial requests, no retries, stop on denial or budget exhaustion.',
          );
          return;
        default:
          throw const ProbeFailure('invalid_arguments');
      }
    }
    File? output;
    if (reportPath != null) {
      output = File(reportPath);
      // Reject an existing destination before any opt-in HTTP request.
      require(
        FileSystemEntity.typeSync(reportPath) == FileSystemEntityType.notFound,
        'report_already_exists',
      );
      output.parent.createSync(recursive: true);
    }
    final report = await Probe(
      fixtures: Directory.fromUri(
        Platform.script.resolve('../../../test/fixtures/lightnovel/'),
      ),
      transport: BudgetTransport(live: live, limit: limit),
    ).run();
    final encoded = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
    stdout.write(encoded);
    if (output != null) {
      require(!output.existsSync(), 'report_already_exists');
      output.writeAsStringSync(encoded);
    }
    exitCode = report['status'] == 'PASS' ? 0 : 1;
  } catch (error) {
    stderr.writeln(
      jsonEncode({
        'status': 'FAIL',
        'failureCode': error is ProbeFailure
            ? error.code
            : 'local_operation_failed',
        'rawErrorRetained': false,
      }),
    );
    exitCode = 2;
  }
}
