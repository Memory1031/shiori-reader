import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shiori/data/local/book_decoder.dart';
import 'audit.dart';
import 'report.dart';

const helpText = '''EPUB Compatibility Auditor v1 (offline, read-only)
  scan --input book.epub --out NEW_DIRECTORY
  scan --paths paths.json --out NEW_DIRECTORY
  scan --input-dir DIRECTORY [--recursive] --out NEW_DIRECTORY
       [--timeout-seconds 60] [--max-documents 1024]
       [--max-events 100000] [--max-findings 2000]
       [--selection-method LOCAL_DESCRIPTION]
  compare --before RUN_DIRECTORY --after RUN_DIRECTORY --out NEW_DIRECTORY
Only explicit inputs are read. Directories are not recursive by default.
Directory links/junctions are skipped. Output must be a new directory.
Each book runs in a terminable offline worker; timeout kills and awaits it.
Reports are private local corpus data. No device/browser rendering is run.
Legacy <paths.json> <report.json> is retired: use scan --paths ... --out ... .
Old differences/policyDifferences are not migrated or reinterpreted.
''';

Future<int> auditMain(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.first == 'help') {
    stdout.write(helpText);
    return 0;
  }
  if (args.length == 2 &&
      !args.first.startsWith('--') &&
      !{'scan', 'compare'}.contains(args.first)) {
    stderr.writeln(
      'Legacy schema retired. Use scan --paths <paths.json> --out <new directory>. Existing reports remain untouched.',
    );
    return 64;
  }
  try {
    final values = <String, String>{};
    final flags = <String>{};
    for (var i = 1; i < args.length; i++) {
      final arg = args[i];
      if ({'--recursive'}.contains(arg)) {
        if (!flags.add(arg)) throw const FormatException();
      } else {
        if (!arg.startsWith('--') ||
            i + 1 >= args.length ||
            values.containsKey(arg)) {
          throw const FormatException();
        }
        values[arg] = args[++i];
      }
    }
    if (args.first == 'scan') {
      if (values.keys.any(
        (key) => !{
          '--input',
          '--paths',
          '--input-dir',
          '--out',
          '--timeout-seconds',
          '--max-documents',
          '--max-events',
          '--max-findings',
          '--selection-method',
        }.contains(key),
      )) {
        throw const FormatException();
      }
      return await scan(values, recursive: flags.contains('--recursive'));
    }
    if (args.first == 'compare') {
      if (flags.isNotEmpty ||
          values.keys.any(
            (key) => !{'--before', '--after', '--out'}.contains(key),
          )) {
        throw const FormatException();
      }
      final before = await readRun(required(values, '--before')),
          after = await readRun(required(values, '--after'));
      final output = await newOutput(required(values, '--out'));
      final diff = compareReports(before, after);
      await File(p.join(output.path, 'comparison.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(diff),
        flush: true,
      );
      await File(p.join(output.path, 'comparison.md')).writeAsString(
        '# EPUB 观察比较\n\n可直接比较：${diff['comparable']}。同内容 hash 书籍：${diff['matchedBooks'] ?? 0}。\n\n${diff['comparable'] == true ? '变化 ${(diff['changes'] as List).length} 项；消失仅表示不再观察到，覆盖下降时保持 unknown。' : 'schema/rules/options 不一致：${diff['incompatible']}；不比较修复。'}\n',
      );
      stdout.writeln('Comparison saved.');
      return diff['comparable'] == true ? 0 : 65;
    }
    throw const FormatException();
  } on FileSystemException {
    stderr.writeln(
      'Input/output unavailable or output directory already exists. No existing report was overwritten.',
    );
    return 73;
  } on FormatException {
    stderr.writeln('Invalid arguments/report. Run --help.');
    return 64;
  } catch (_) {
    stderr.writeln(
      'Audit runner failed; completed per-book files remain readable.',
    );
    return 70;
  }
}

String required(Map<String, String> values, String key) =>
    values[key] ?? (throw const FormatException());
int positiveOption(
  Map<String, String> values,
  String key,
  int fallback,
  int max,
) {
  final n = int.tryParse(values[key] ?? '$fallback');
  if (n == null || n < 1 || n > max) throw const FormatException();
  return n;
}

Future<Directory> newOutput(String path) async {
  final dir = Directory(p.absolute(path));
  if (await FileSystemEntity.type(dir.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw const FileSystemException('Output exists');
  }
  var ancestor = dir.parent;
  while (!await ancestor.exists()) {
    final next = ancestor.parent;
    if (next.path == ancestor.path) {
      throw const FileSystemException('No parent');
    }
    ancestor = next;
  }
  if (!p.equals(
    p.normalize(await ancestor.resolveSymbolicLinks()),
    p.normalize(ancestor.absolute.path),
  )) {
    throw const FileSystemException('Output ancestor is a link');
  }
  return dir.create(recursive: true);
}

Future<List<String>> explicitInputs(
  Map<String, String> values, {
  required bool recursive,
}) async {
  if (['--input', '--paths', '--input-dir'].where(values.containsKey).length !=
      1) {
    throw const FormatException();
  }
  if (recursive && !values.containsKey('--input-dir')) {
    throw const FormatException();
  }
  final inputs = <String>[];
  if (values['--input'] case final input?) {
    inputs.add(p.absolute(input));
  } else if (values['--paths'] case final path?) {
    final file = File(path);
    if (await file.length() > 1024 * 1024) throw const FormatException();
    final list = jsonDecode(await file.readAsString());
    if (list is! List || list.length > 10000 || list.any((e) => e is! String)) {
      throw const FormatException();
    }
    inputs.addAll(list.cast<String>().map((e) => p.absolute(e)));
  } else {
    final root = Directory(p.absolute(values['--input-dir']!));
    final canonical = await root.resolveSymbolicLinks();
    if (!p.equals(p.normalize(root.path), p.normalize(canonical))) {
      throw const FileSystemException('Directory link');
    }
    var visited = 0;
    Future<void> walk(Directory dir, [int depth = 0]) async {
      if (depth > 64) throw const FormatException();
      await for (final entity in dir.list(followLinks: false)) {
        if (++visited > 100000) throw const FormatException();
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file &&
            p.extension(entity.path).toLowerCase() == '.epub') {
          inputs.add(p.absolute(entity.path));
        } else if (recursive && type == FileSystemEntityType.directory) {
          final child = Directory(entity.path);
          final resolved = await child.resolveSymbolicLinks();
          if (p.equals(
                p.normalize(resolved),
                p.normalize(child.absolute.path),
              ) &&
              p.isWithin(canonical, resolved)) {
            await walk(child, depth + 1);
          }
        }
        if (inputs.length > 10000) throw const FormatException();
      }
    }

    await walk(root);
  }
  return inputs..sort();
}

Future<String> runIsolated(
  String executable,
  List<String> arguments,
  Duration timeout, {
  void Function(Process?)? onProcess,
  Future<void>? interrupted,
}) async {
  final process = await Process.start(executable, arguments);
  onProcess?.call(process);
  final out = process.stdout.drain<void>(), err = process.stderr.drain<void>();
  var timedOut = false, wasInterrupted = false;
  final timer = Timer(timeout, () {
    timedOut = true;
    process.kill();
  });
  interrupted?.then((_) {
    wasInterrupted = true;
    process.kill();
  });
  final code = await process.exitCode;
  timer.cancel();
  await Future.wait([out, err]);
  onProcess?.call(null);
  return wasInterrupted
      ? 'interrupted'
      : timedOut
      ? 'timeout'
      : code == 0
      ? 'completed'
      : 'worker_crash';
}

String auditDartExecutable() {
  final pinned = p.absolute(
    '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}',
  );
  if (File(pinned).existsSync()) return pinned;
  if (p.basenameWithoutExtension(Platform.resolvedExecutable) == 'dart') {
    return Platform.resolvedExecutable;
  }
  throw const FormatException('Pinned Dart runtime unavailable');
}

Future<int> scan(Map<String, String> values, {required bool recursive}) async {
  final inputs = await explicitInputs(values, recursive: recursive);
  final options = AuditOptions(
    maxDocuments: positiveOption(values, '--max-documents', 1024, 4096),
    maxEvents: positiveOption(values, '--max-events', 100000, 200000),
    maxFindings: positiveOption(values, '--max-findings', 2000, 10000),
  );
  final seconds = positiveOption(values, '--timeout-seconds', 60, 3600);
  final output = await newOutput(required(values, '--out'));
  final watch = Stopwatch()..start();
  final sha = await Process.run('git', ['rev-parse', 'HEAD']);
  final dirty = await Process.run('git', ['status', '--porcelain=v1']);
  final auditFiles = [
    'tool/epub_compatibility_audit.dart',
    'tool/epub_audit/audit.dart',
    'tool/epub_audit/cli.dart',
    'tool/epub_audit/source.dart',
    'tool/epub_audit/report.dart',
    'tool/epub_audit/worker.dart',
    'lib/data/local/epub/epub_trace.dart',
  ];
  final auditFingerprint = digest(
    jsonEncode([
      for (final file in auditFiles) await File(file).readAsString(),
    ]),
  );
  final run = <String, dynamic>{
    'schemaVersion': schemaVersion,
    'auditRulesVersion': auditRulesVersion,
    'auditCodeFingerprint': auditFingerprint,
    'gitSha': sha.exitCode == 0 ? (sha.stdout as String).trim() : null,
    'dirty': dirty.exitCode == 0
        ? (dirty.stdout as String).trim().isNotEmpty
        : null,
    'parserVersion': BookDecoder.parserVersion,
    'toolchain': safeLabel(Platform.version),
    'scopeType': values.containsKey('--input')
        ? 'single'
        : values.containsKey('--paths')
        ? 'paths'
        : 'directory',
    'recursive': recursive,
    'options': options.toJson(),
    'optionsFingerprint': digest(jsonEncode([options.toJson(), seconds])),
    'timeoutSeconds': seconds,
    'workerMode': 'pinned_dart_vm_process',
    'maxRetainedResultBytes': 64 * 1024 * 1024,
    'aggregateComplete': true,
    'selectionMethod': safeLabel(
      values['--selection-method'] ??
          'All explicitly supplied inputs in ordinal path order',
    ),
    'startedAt': DateTime.now().toUtc().toIso8601String(),
    'complete': false,
    'interrupted': false,
    'totalFiles': inputs.length,
    'uniqueEpubs': 0,
    'duplicates': 0,
    'statuses': <String, int>{},
    'auditCompleteBooks': 0,
    'unchecked': <String>[],
  };
  final results = <Json>[], byHash = <String, Json>{};
  var retainedBytes = 0;
  String alias(String file) => values.containsKey('--input-dir')
      ? safeLabel(p.relative(file, from: p.absolute(values['--input-dir']!)))
      : safeLabel(
          values.containsKey('--paths')
              ? '${inputs.indexOf(file).toString().padLeft(5, '0')}: ${p.basename(file)}'
              : p.basename(file),
        );
  run['unchecked'] = inputs.map(alias).toList();
  Future<void> persist() async {
    final summaryBooks = [
      for (final b in results)
        {
          for (final e in b.entries)
            if (!{'findings', 'documents'}.contains(e.key)) e.key: e.value,
        },
    ];
    final report = {
      'run': run,
      'books': summaryBooks,
      'aggregate': aggregateBooks(results),
    };
    if (run['aggregateComplete'] != true) {
      for (final g in report['aggregate'] as List<Json>) {
        g['countAccuracy'] = 'lower_bound';
      }
    }
    if ((report['aggregate'] as List).length > 10000) {
      report['aggregate'] = (report['aggregate'] as List).take(10000).toList();
      run['aggregateComplete'] = false;
      run['aggregateTruncation'] = 'aggregate_group_budget';
    }
    final temp = File(p.join(output.path, 'report.tmp'));
    var serialized = const JsonEncoder.withIndent('  ').convert(report);
    if (utf8.encode(serialized).length > 32 * 1024 * 1024) {
      report['aggregate'] = <Json>[];
      run['aggregateComplete'] = false;
      run['aggregateTruncation'] = 'summary_bytes';
      serialized = jsonEncode(report);
    }
    await temp.writeAsString(serialized, flush: true);
    final target = File(p.join(output.path, 'report.json'));
    await temp.rename(target.path);
    await File(
      p.join(output.path, 'report.md'),
    ).writeAsString(reportMarkdown(report), flush: true);
  }

  await persist();
  var stopped = false;
  final interrupt = Completer<void>();
  StreamSubscription<ProcessSignal>? signal;
  try {
    signal = ProcessSignal.sigint.watch().listen((_) {
      stopped = true;
      if (!interrupt.isCompleted) interrupt.complete();
    });
  } on SignalException {
    /* JSONL survives hard interruption. */
  }
  final journal = File(
    p.join(output.path, 'books.jsonl'),
  ).openWrite(mode: FileMode.append);
  try {
    final inventory = <Json>[];
    for (final input in inputs) {
      if (stopped) break;
      final row = <String, dynamic>{'alias': alias(input)};
      try {
        final file = File(input);
        row['bytes'] = await file.length();
        final length = row['bytes'] as int;
        // Hashing streams identity bytes; parser payload reads remain <=64MiB.
        if (length <= 128 * 1024 * 1024) {
          var read = 0;
          final stream = file.openRead(0, length).map((chunk) {
            read += chunk.length;
            return chunk;
          });
          row['sha256'] = (await sha256.bind(stream).first).toString();
          if (read != length || await file.length() != length) {
            throw const FileSystemException('Input changed');
          }
        } else {
          row['identityUnknown'] = true;
        }
        row['readable'] = true;
      } on FileSystemException {
        row['readable'] = false;
      }
      inventory.add(row);
    }
    await File(p.join(output.path, 'inventory.json')).writeAsString(
      jsonEncode({
        'files': inventory,
        'selectionMethod': run['selectionMethod'],
        'enumerationComplete': inventory.length == inputs.length,
      }),
      flush: true,
    );
    final worker = auditDartExecutable();
    final workerArguments = [
      '--disable-dart-dev',
      '--packages=${p.absolute('.dart_tool/package_config.json')}',
      p.absolute('tool/epub_audit/worker.dart'),
    ];
    for (var i = 0; i < inventory.length; i++) {
      if (stopped) break;
      final row = inventory[i], hash = row['sha256'] as String?;
      final duplicate = hash == null ? null : byHash[hash];
      if (duplicate != null) {
        (duplicate['aliases'] as List).add(row['alias']);
        journal.writeln(
          jsonEncode({
            'sha256': hash,
            'alias': row['alias'],
            'status': 'duplicate',
            'reportFile': duplicate['reportFile'],
          }),
        );
        await journal.flush();
        run['duplicates'] = (run['duplicates'] as int) + 1;
        (run['unchecked'] as List).remove(row['alias']);
        continue;
      }
      Json result;
      final filename = 'book-${i.toString().padLeft(5, '0')}.json';
      final working = p.join(output.path, 'worker-result.json');
      if (row['readable'] != true) {
        result = emptyBook('input_read_failure');
      } else if ((row['bytes'] as int) > BookDecoder.maxEpubBytes) {
        result = emptyBook('production_rejected')
          ..['failureCategory'] = 'tooLarge';
      } else {
        final status = await runIsolated(
          worker,
          [
            ...workerArguments,
            inputs[i],
            working,
            hash!,
            '${options.maxDocuments}',
            '${options.maxEvents}',
            '${options.maxFindings}',
          ],
          Duration(seconds: seconds),
          interrupted: interrupt.future,
        );
        if (status == 'completed' &&
            await File(working).exists() &&
            await File(working).length() <= 8 * 1024 * 1024) {
          result = jsonDecode(await File(working).readAsString()) as Json;
        } else {
          result = emptyBook(
            status == 'completed' ? 'worker_invalid_report' : status,
          );
        }
        if (await File(working).exists()) await File(working).delete();
      }
      result.addAll({
        'sha256': hash,
        'bytes': row['bytes'],
        'aliases': [row['alias']],
        'reportFile': filename,
      });
      results.add(result);
      if (hash != null) byHash[hash] = result;
      await File(
        p.join(output.path, filename),
      ).writeAsString(jsonEncode(result), flush: true);
      retainedBytes += utf8.encode(jsonEncode(result)).length;
      result.remove('documents');
      if (retainedBytes > 64 * 1024 * 1024) {
        result['findings'] = <Json>[];
        run['aggregateComplete'] = false;
        run['aggregateTruncation'] = 'retained_result_budget';
      }
      journal.writeln(
        jsonEncode({
          'sha256': hash,
          'aliases': result['aliases'],
          'status': result['status'],
          'reportFile': filename,
        }),
      );
      await journal.flush();
      (run['statuses'] as Map<String, int>).update(
        result['status'] as String,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      if (result['auditComplete'] == true) {
        run['auditCompleteBooks'] = (run['auditCompleteBooks'] as int) + 1;
      }
      (run['unchecked'] as List).remove(row['alias']);
      stdout.writeln(
        '${i + 1}/${inventory.length} ${result['status']} ${row['alias']}',
      );
    }
    run['uniqueEpubs'] = byHash.length;
    run['identityUnknownFiles'] = inventory
        .where((r) => r['readable'] == true && r['sha256'] == null)
        .length;
    run['complete'] = !stopped && (run['unchecked'] as List).isEmpty;
    return stopped ? 130 : 0;
  } finally {
    await signal?.cancel();
    await journal.close();
    run['uniqueEpubs'] = byHash.length;
    run['interrupted'] = stopped;
    run['elapsedMs'] = watch.elapsedMilliseconds;
    run['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    await persist();
  }
}

Future<Json> readRun(String path) async {
  final dir = Directory(path);
  final summary = File(p.join(dir.path, 'report.json'));
  if (await summary.length() > 32 * 1024 * 1024) throw const FormatException();
  final report = jsonDecode(await summary.readAsString()) as Json;
  final run = report['run'] as Json;
  if (run['schemaVersion'] != schemaVersion) {
    return {...report, 'books': <Json>[]};
  }
  final books = <Json>[];
  final journal = File(p.join(dir.path, 'books.jsonl'));
  final files = <String>{};
  final aliases = <String, Set<String>>{};
  if (await journal.exists()) {
    await for (final line
        in journal
            .openRead()
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      try {
        final row = jsonDecode(line) as Json;
        final filename = row['reportFile'] as String;
        files.add(filename);
        final names = aliases[filename] ??= <String>{};
        names.addAll((row['aliases'] as List? ?? []).cast<String>());
        if (row['status'] == 'duplicate') names.add(row['alias'] as String);
      } on FormatException {
        /* Interrupted trailing line. */
      }
    }
  } else {
    for (final b in (report['books'] as List).cast<Json>()) {
      files.add(b['reportFile'] as String);
    }
  }
  for (final filename in files) {
    if (!RegExp(r'^book-\d{5}\.json$').hasMatch(filename)) {
      throw const FormatException();
    }
    final file = File(p.join(dir.path, filename));
    if (await file.length() > 8 * 1024 * 1024) throw const FormatException();
    final book = jsonDecode(await file.readAsString()) as Json;
    if (aliases[filename]?.isNotEmpty == true) {
      book['aliases'] = {
        ...(book['aliases'] as List? ?? []),
        ...aliases[filename]!,
      }.toList();
    }
    books.add(book);
  }
  report['books'] = books;
  return report;
}
