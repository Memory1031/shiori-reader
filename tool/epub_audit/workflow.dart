import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'cli.dart'
    show
        required,
        positiveOption,
        newOutput,
        explicitInputs,
        readRun,
        auditDartExecutable;
import 'browser_probe.dart';
import 'loss_model.dart';
import 'loss_report.dart';
import 'plan.dart';
import 'replay.dart';
import 'report.dart';

Future<String> boundedProcess(
  String executable,
  List<String> arguments,
  Duration duration, {
  Map<String, String>? environment,
  String? log,
  Stream<ProcessSignal>? testOnlySignals,
  ProbeCancellation? cancellation,
}) async {
  final runCancellation =
      cancellation ?? ProbeCancellation(signals: testOnlySignals);
  if (runCancellation.isCancelled) {
    if (cancellation == null) await runCancellation.close();
    return 'interrupted';
  }
  late final Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      environment: environment,
    );
  } catch (_) {
    if (cancellation == null) await runCancellation.close();
    rethrow;
  }
  final sink = log == null ? null : File(log).openWrite();
  var retained = 0;
  Future<void> drain(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      if (sink != null && retained + bytes.length <= 1024 * 1024) {
        sink.add(bytes);
        retained += bytes.length;
      }
    }
  }

  final stdoutDrain = drain(process.stdout),
      stderrDrain = drain(process.stderr);
  var timedOut = false;
  Future<void>? stopping;
  void stop() {
    stopping ??= stopOwnedProcess(process);
  }

  final timer = Timer(duration, () {
    timedOut = true;
    stop();
  });
  final signal = runCancellation.changes.listen((_) => stop());
  if (runCancellation.isCancelled) stop();
  try {
    final code = await process.exitCode;
    if (stopping != null) await stopping;
    await Future.wait([stdoutDrain, stderrDrain]);
    return runCancellation.isCancelled
        ? 'interrupted'
        : timedOut
        ? 'timeout'
        : code == 0
        ? 'completed'
        : 'probe_failed';
  } finally {
    timer.cancel();
    await signal.cancel();
    await sink?.close();
    if (cancellation == null) await runCancellation.close();
  }
}

Future<Json> replayOperation(
  Json request,
  Directory output, {
  int timeoutSeconds = 60,
  ProbeCancellation? cancellation,
}) async {
  final requestFile = p.join(output.path, 'replay-request.json');
  final resultFile = p.join(output.path, 'replay-result.json');
  await atomicJson(requestFile, request);
  final status = await boundedProcess(
    auditDartExecutable(),
    [
      '--disable-dart-dev',
      '--packages=${p.absolute('.dart_tool/package_config.json')}',
      p.absolute('tool/epub_audit/replay_worker.dart'),
      requestFile,
      resultFile,
    ],
    Duration(seconds: timeoutSeconds),
    cancellation: cancellation,
  );
  if (status == 'completed') {
    return boundedJson(File(resultFile), maxBytes: 8 * 1024 * 1024);
  }
  return {
    'status': status,
    'auditComplete': false,
    'checks': {},
    'findings': [],
    'readingLoss': {
      'sourceFacts': [],
      'representations': [],
      'correspondences': [],
      'candidates': [],
      'displayPaths': [],
    },
  };
}

Future<int> captureCommand(Map<String, String> v) async {
  final input = await authorizedFile(
    required(v, '--input'),
    required(v, '--allow-root'),
    maxBytes: 64 * 1024 * 1024,
  );
  final out = await newOutput(required(v, '--out'));
  final result = await replayOperation(
    {
      'action': 'capture',
      'input': input.path,
      'allowRoot': p.absolute(v['--allow-root']!),
      'bundleOut': out.path,
    },
    out,
    timeoutSeconds: positiveOption(v, '--timeout-seconds', 60, 300),
  );
  stdout.writeln('PRIVATE producer replay ${result['status']}.');
  return result['status'] == 'captured' ? 0 : 65;
}

Future<Json> evaluatedRun(Json book) async {
  final producer = book['producer'] as Json? ?? await producerIdentity();
  return {
    'run': {
      'schemaVersion': schemaVersion,
      'auditRulesVersion': auditRulesVersion,
      'producer': producer,
      'evaluator': await evaluatorIdentity(),
      'probe': await probeIdentity(),
      'parserVersion': producer['parserVersion'],
      'complete': true,
      'aggregateComplete': book['auditComplete'] == true,
      'totalFiles': 1,
      'uniqueEpubs': 1,
      'duplicates': 0,
      'statuses': {book['status'] as String: 1},
      'options': const AuditOptions().toJson(),
      'optionsFingerprint': const AuditOptions().fingerprint,
      'scopeType': 'explicit_private_replay',
    },
    'books': [book],
    'aggregate': aggregateBooks([book]),
    'lossSummary': summarizeLosses([book]),
  };
}

Future<void> publishRun(Directory output, Json report) async {
  final books = (report['books'] as List).cast<Json>();
  final journal = <String>[];
  for (var i = 0; i < books.length; i++) {
    final book = books[i];
    final filename = 'book-${i.toString().padLeft(5, '0')}.json';
    book['reportFile'] = filename;
    if (!await File(p.join(output.path, filename)).exists()) {
      await atomicJson(
        p.join(output.path, filename),
        book,
        maxBytes: 8 * 1024 * 1024,
      );
    }
    journal.add(
      jsonEncode({'reportFile': filename, 'aliases': book['aliases']}),
    );
  }
  if (!await File(p.join(output.path, 'books.jsonl')).exists()) {
    await File(
      p.join(output.path, 'books.jsonl'),
    ).writeAsString('${journal.join('\n')}\n', flush: true);
  }
  final summary = {
    ...report,
    'books': [
      for (final book in books)
        {
          for (final entry in book.entries)
            if (!{'readingLoss', 'findings', 'documents'}.contains(entry.key))
              entry.key: entry.value,
        },
    ],
  };
  await atomicJson(p.join(output.path, 'report.json'), summary);
  await File(
    p.join(output.path, 'report.md'),
  ).writeAsString(reportMarkdown(summary), flush: true);
}

Future<int> evaluateCommand(Map<String, String> v) async {
  await authorizedFile(
    p.join(required(v, '--bundle'), 'bundle.json'),
    required(v, '--allow-root'),
    maxBytes: 1024 * 1024,
  );
  final out = await newOutput(required(v, '--out'));
  final book = await replayOperation(
    {
      'action': 'evaluate',
      'bundle': p.absolute(v['--bundle']!),
      'allowRoot': p.absolute(v['--allow-root']!),
    },
    out,
    timeoutSeconds: positiveOption(v, '--timeout-seconds', 60, 300),
  );
  book['aliases'] = ['private-replay'];
  book['reportFile'] = 'book-00000.json';
  await atomicJson(
    p.join(out.path, 'book-00000.json'),
    book,
    maxBytes: 8 * 1024 * 1024,
  );
  await File(p.join(out.path, 'books.jsonl')).writeAsString(
    '${jsonEncode({'reportFile': 'book-00000.json'})}\n',
    flush: true,
  );
  await publishRun(out, await evaluatedRun(book));
  return book['status'] == 'parsed' ? 0 : 65;
}

Future<int> planCommand(Map<String, String> v) async {
  final report = await readRun(required(v, '--run'));
  final plan = makePlan(
    report,
    maxTargets: positiveOption(v, '--max-targets', 12, 12),
    maxConfigurations: positiveOption(v, '--configurations', 3, 3),
    maxPages: positiveOption(v, '--max-pages', 12, 64),
    timeoutSeconds: positiveOption(v, '--timeout-seconds', 60, 300),
    maxScreenshots: screenshotOption(v),
    provider: v['--provider'],
  );
  final out = await newOutput(required(v, '--out'));
  await atomicJson(p.join(out.path, 'plan.json'), plan);
  stdout.writeln(
    'Plan selected ${plan['selectedTargets']} targets; remaining candidates not_run.',
  );
  return 0;
}

int screenshotOption(Map<String, String> values) {
  final n = int.tryParse(values['--screenshots'] ?? '1');
  if (n == null || n < 0 || n > 3) {
    throw const FormatException('Screenshot budget');
  }
  return n;
}

Future<Map<String, String>> authorizedInputs(Map<String, String> v) async {
  final inputs = await explicitInputs({
    for (final k in ['--input', '--paths', '--input-dir'])
      if (v[k] != null) k: v[k]!,
  }, recursive: false);
  final files = <String, String>{};
  for (final input in inputs) {
    final file = await authorizedFile(
      input,
      required(v, '--allow-root'),
      maxBytes: 128 * 1024 * 1024,
    );
    final hash = (await sha256.bind(file.openRead()).first).toString();
    files.putIfAbsent(hash, () => file.path);
  }
  return files;
}

Future<Json> flutterProbe(
  Json request,
  Directory privateRoot,
  int seconds, {
  ProbeCancellation? cancellation,
}) async {
  final requestFile = p.join(privateRoot.path, 'request.json');
  final resultFile = p.join(privateRoot.path, 'probe-result.json');
  request['result'] = resultFile;
  await atomicJson(requestFile, request, maxBytes: 1024 * 1024);
  final sdk = p.dirname(
    p.dirname(p.dirname(p.dirname(p.dirname(auditDartExecutable())))),
  );
  final flutterTool = p.join(sdk, 'bin/cache/flutter_tools.snapshot');
  final toolchain = await boundedJson(
    File(p.join(sdk, 'bin/cache/flutter.version.json')),
    maxBytes: 16384,
  );
  if (toolchain['frameworkVersion'] != '3.38.10' ||
      toolchain['dartSdkVersion'] != '3.10.9') {
    throw const FormatException('Pinned Flutter/Dart mismatch');
  }
  if (!await File(flutterTool).exists()) {
    throw const FormatException('Pinned Flutter tool unavailable');
  }
  final status = await boundedProcess(
    auditDartExecutable(),
    [
      flutterTool,
      'test',
      '--no-pub',
      '--concurrency=1',
      'test/tool/epub_loss_native_probe_test.dart',
      '--reporter',
      'expanded',
    ],
    Duration(seconds: seconds),
    environment: {'SHIORI_LOSS_REQUEST': requestFile},
    log: p.join(privateRoot.path, 'flutter-private.log'),
    cancellation: cancellation,
  );
  if (status == 'completed' && await File(resultFile).exists()) {
    return boundedJson(File(resultFile), maxBytes: 8 * 1024 * 1024);
  }
  return {
    'complete': false,
    'observedPath': 'not_run',
    'reason': status,
    'layers': {for (final e in EvidenceLayer.values) wireName(e): 'not_run'},
    'assertions': {},
  };
}

Future<int> verifyCommand(
  Map<String, String> v, {
  Stream<ProcessSignal>? testOnlySignals,
  Future<Json> Function(Json, Directory, int)? testOnlyFlutterProbe,
}) async {
  final cancellation = ProbeCancellation(signals: testOnlySignals);
  try {
    return await _verifyCommand(
      v,
      cancellation,
      testOnlyFlutterProbe: testOnlyFlutterProbe,
    );
  } finally {
    await cancellation.close();
  }
}

Future<int> _verifyCommand(
  Map<String, String> v,
  ProbeCancellation cancellation, {
  Future<Json> Function(Json, Directory, int)? testOnlyFlutterProbe,
}) async {
  final provider = v['--provider'] ?? 'native';
  if (!{'native', 'browser', 'webview'}.contains(provider)) {
    throw const FormatException('Unknown renderer provider');
  }
  final plan = await boundedJson(
    File(required(v, '--plan')),
    maxBytes: 8 * 1024 * 1024,
  );
  if (plan['schemaVersion'] != 2 || plan['kind'] != 'verification_plan') {
    throw const FormatException('Invalid plan');
  }
  if (plan['plannedProvider'] != null && plan['plannedProvider'] != provider) {
    throw const FormatException('Planned provider mismatch');
  }
  final targets = objectList(
    plan,
    'targets',
    max: 12,
  ).map(VerificationTarget.fromJson).toList();
  final bundled = v['--bundle'];
  final files = bundled == null
      ? await authorizedInputs(v)
      : <String, String>{};
  if (bundled != null) {
    await authorizedFile(
      p.join(bundled, 'bundle.json'),
      required(v, '--allow-root'),
      maxBytes: 1024 * 1024,
    );
  }
  final font = v['--font'];
  if (font != null) {
    await authorizedFile(
      font,
      p.dirname(p.absolute(font)),
      maxBytes: 32 * 1024 * 1024,
    );
  }
  final out = await newOutput(required(v, '--out'));
  await File(p.join(out.path, 'PRIVATE.txt')).writeAsString(
    'Verification contains private replay, renderings and resource data. Never upload or commit.\n',
  );
  final privateDir = await Directory(p.join(out.path, '.private')).create();
  final producer = hashField(plan['producer'] as Json, 'fingerprint');
  final currentEvaluator = await evaluatorIdentity();
  if (hashField(plan['evaluator'] as Json, 'fingerprint') !=
      currentEvaluator['fingerprint']) {
    throw const FormatException('Plan evaluator changed; regenerate plan');
  }
  final probe = await probeIdentity();
  final runtimeProducer = await producerIdentity();
  final sdk = p.dirname(
    p.dirname(p.dirname(p.dirname(p.dirname(auditDartExecutable())))),
  );
  final toolchain = await boundedJson(
    File(p.join(sdk, 'bin/cache/flutter.version.json')),
    maxBytes: 16384,
  );
  final evidence = <VerificationEvidence>[];
  final captured = <String, String>{};
  var capturedBytes = 0;
  final journal = File(
    p.join(out.path, 'evidence.jsonl'),
  ).openWrite(mode: FileMode.append);
  var retained = 0, ordinal = 0;
  try {
    verification:
    for (final target in targets) {
      if (cancellation.isCancelled) break;
      final hash = target.candidate.location.epubHash;
      String? bundle = bundled ?? captured[hash];
      if (bundle == null &&
          files[hash] != null &&
          capturedBytes <= 512 * 1024 * 1024) {
        final dir = await Directory(
          p.join(privateDir.path, 'bundle-$hash'),
        ).create();
        final capturedResult = await replayOperation(
          {
            'action': 'capture',
            'input': files[hash],
            'allowRoot': p.absolute(v['--allow-root']!),
            'epubHash': hash,
            'bundleOut': dir.path,
          },
          dir,
          timeoutSeconds: target.timeoutSeconds,
          cancellation: cancellation,
        );
        if (capturedResult['status'] == 'interrupted') cancellation.cancel();
        if (capturedResult['status'] == 'captured' &&
            (capturedResult['producer'] as Json)['fingerprint'] == producer) {
          bundle = dir.path;
          captured[hash] = bundle;
          final manifest = await boundedJson(
            File(p.join(bundle, 'bundle.json')),
            maxBytes: 1024 * 1024,
          );
          capturedBytes += intField(
            manifest,
            'totalBytes',
            max: maxBundleBytes,
          );
        }
      }
      if (cancellation.isCancelled) break;
      if (bundle != null) {
        final manifest = await boundedJson(
          File(p.join(bundle, 'bundle.json')),
          maxBytes: 1024 * 1024,
        );
        if (manifest['epubHash'] != hash ||
            (manifest['producer'] as Json)['fingerprint'] != producer) {
          throw const FormatException(
            'Verification source or producer identity changed',
          );
        }
      }
      var targetScreenshots = 0;
      for (final config in target.configurations) {
        if (cancellation.isCancelled) break verification;
        final dir = await Directory(
          p.join(
            privateDir.path,
            'target-${ordinal.toString().padLeft(5, '0')}',
          ),
        ).create();
        final screenshot = targetScreenshots < target.maxScreenshots
            ? p.join(dir.path, 'page.png')
            : null;
        Json result;
        if (bundle == null) {
          result = {
            'complete': false,
            'reason': 'authorized_source_unavailable_or_producer_changed',
            'observedPath': 'not_run',
            'layers': {
              for (final layer in EvidenceLayer.values)
                wireName(layer): 'not_run',
            },
            'assertions': {},
          };
        } else {
          try {
            final request = <String, dynamic>{
              'bundle': bundle,
              'allowRoot': bundled == null
                  ? out.path
                  : p.absolute(v['--allow-root']!),
              'target': target.toJson(),
              'configuration': config.toJson(),
              'font': font,
              'mode': provider == 'browser' ? 'host_html' : 'native',
              'screenshot': screenshot,
            };
            if (provider == 'native') {
              result = testOnlyFlutterProbe != null
                  ? await testOnlyFlutterProbe(
                      request,
                      dir,
                      target.timeoutSeconds,
                    )
                  : await flutterProbe(
                      request,
                      dir,
                      target.timeoutSeconds,
                      cancellation: cancellation,
                    );
            } else if (provider == 'browser') {
              final htmlFile = p.join(dir.path, 'production-host.html');
              request['htmlOutput'] = htmlFile;
              final prepared = await flutterProbe(
                request,
                dir,
                target.timeoutSeconds,
                cancellation: cancellation,
              );
              if (prepared['status'] == 'host_document_prepared' &&
                  !cancellation.isCancelled) {
                result = await runBrowserProbe(
                  await File(htmlFile).readAsString(),
                  dir,
                  target,
                  config,
                  screenshot: screenshot,
                  cancellation: cancellation,
                );
              } else {
                result = prepared;
              }
            } else {
              result = await nativeWebViewProbe(
                request,
                dir,
                target.timeoutSeconds,
                cancellation: cancellation,
              );
            }
          } catch (_) {
            result = {
              'complete': false,
              'observedPath': 'not_run',
              'reason': cancellation.isCancelled
                  ? 'interrupted'
                  : 'provider_failure',
              'layers': {
                for (final layer in EvidenceLayer.values)
                  wireName(layer): 'not_run',
              },
              'assertions': {},
            };
          }
        }
        if (result['reason'] == 'interrupted') cancellation.cancel();
        final env = {
          'platform': Platform.operatingSystem,
          'dart': Platform.version,
          'flutterToolchain': toolchain['frameworkVersion'],
          'engineRevision': toolchain['engineRevision'],
          'provider': provider,
          'rendererFingerprint': runtimeProducer['renderer'],
          'fontHash': font == null
              ? null
              : sha256.convert(await File(font).readAsBytes()).toString(),
          'detail':
              result['environmentDetail'] ??
              result['providerDetail'] ??
              (provider == 'native'
                  ? 'widget_test_engine'
                  : '${provider}_unavailable'),
        };
        final e = VerificationEvidence(
          id: digest(
            jsonEncode([
              target.candidate.id,
              probe['fingerprint'],
              provider,
              digest(jsonEncode(env)),
              config.fingerprint,
              ordinal,
            ]),
          ),
          candidateId: target.candidate.id,
          sourceId: target.candidate.sourceId,
          epubHash: hash,
          producer: producer,
          probe: probe['fingerprint'] as String,
          environment: digest(jsonEncode(env)),
          configuration: config.fingerprint,
          provider: provider,
          observedPath: result['observedPath'] as String? ?? 'not_run',
          layers: {
            for (final entry in (result['layers'] as Json? ?? {}).entries)
              wireEnum(EvidenceLayer.values, entry.key): wireEnum(
                CheckStatus.values,
                entry.value,
              ),
          },
          complete: result['complete'] == true,
          assertions: Map<String, dynamic>.from(
            result['assertions'] as Map? ?? const <String, dynamic>{},
          ),
          reason: result['reason'] as String? ?? 'probe_failed',
          artifacts: screenshot != null && await File(screenshot).exists()
              ? [p.relative(screenshot, from: out.path).replaceAll('\\', '/')]
              : [],
        );
        final filename = 'evidence-${ordinal.toString().padLeft(5, '0')}.json';
        final artifactChecksums = <String, String>{};
        var artifactBytes = 0;
        for (final name in e.artifacts) {
          final file = await authorizedFile(
            p.join(out.path, name),
            out.path,
            maxBytes: target.maxEvidenceBytes,
          );
          artifactChecksums[name] = sha256
              .convert(await file.readAsBytes())
              .toString();
          artifactBytes += await file.length();
          targetScreenshots++;
        }
        final row = <String, dynamic>{
          'evidence': e.toJson(),
          'environment': env,
          'configurationDetail': config.toJson(),
          'artifactChecksums': artifactChecksums,
        };
        final rowBytes = utf8.encode(jsonEncode(row)).length + artifactBytes;
        if (rowBytes > target.maxEvidenceBytes) {
          throw const FormatException('Target evidence budget');
        }
        retained += rowBytes;
        if (retained > 64 * 1024 * 1024) {
          throw const FormatException('Run evidence budget');
        }
        await atomicJson(
          p.join(out.path, filename),
          row,
          maxBytes: target.maxEvidenceBytes,
        );
        journal.writeln(
          jsonEncode({
            'file': filename,
            'sha256': sha256
                .convert(await File(p.join(out.path, filename)).readAsBytes())
                .toString(),
          }),
        );
        await journal.flush();
        evidence.add(e);
        ordinal++;
        stdout.writeln('Verified $ordinal: $provider ${e.reason}.');
      }
    }
  } finally {
    await journal.close();
    await atomicJson(p.join(out.path, 'verification.json'), {
      'schemaVersion': 2,
      'probe': probe,
      'producer': plan['producer'],
      'evaluator': currentEvaluator,
      'complete':
          !cancellation.isCancelled &&
          evidence.length ==
              targets.fold<int>(0, (n, t) => n + t.configurations.length),
      'evidenceCount': evidence.length,
      'notSelected': plan['notSelected'],
      'interrupted': cancellation.isCancelled,
      'notRun': [
        for (final pending in [
          for (final target in targets)
            for (final config in target.configurations)
              {
                'candidateId': target.candidate.id,
                'sourceId': target.candidate.sourceId,
                'configuration': config.fingerprint,
                'provider': provider,
              },
        ].skip(ordinal))
          {
            ...pending,
            'status': 'not_run',
            'reason': cancellation.isCancelled
                ? 'run_interrupted'
                : 'run_incomplete',
          },
      ],
    });
  }
  return cancellation.isCancelled
      ? 130
      : evidence.any((e) => e.reason == 'timeout')
      ? 124
      : evidence.any((e) => e.reason == 'interrupted')
      ? 130
      : evidence.any((e) => e.reason == 'capability_unavailable')
      ? 69
      : evidence.any((e) => e.observedPath == 'not_run')
      ? 65
      : 0;
}

Future<List<VerificationEvidence>> readEvidence(String directory) async {
  final root = p.absolute(directory);
  final journal = await authorizedFile(
    p.join(root, 'evidence.jsonl'),
    root,
    maxBytes: 1024 * 1024,
  );
  final evidence = <VerificationEvidence>[];
  final seen = <String>{};
  await for (final line
      in journal
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    Json row;
    try {
      row = jsonDecode(line) as Json;
    } on FormatException {
      continue;
    }
    final name = stringField(row, 'file');
    if (!RegExp(r'^evidence-\d{5}\.json$').hasMatch(name) || !seen.add(name)) {
      throw const FormatException('Evidence journal identity');
    }
    final file = await authorizedFile(
      p.join(root, name),
      root,
      maxBytes: 8 * 1024 * 1024,
    );
    if (sha256.convert(await file.readAsBytes()).toString() !=
        hashField(row, 'sha256')) {
      throw const FormatException('Evidence checksum');
    }
    final record = await boundedJson(file, maxBytes: 8 * 1024 * 1024);
    final e = VerificationEvidence.fromJson(record['evidence'] as Json);
    if (digest(jsonEncode(record['environment'])) != e.environment ||
        ProbeConfiguration.fromJson(
              record['configurationDetail'] as Json,
            ).fingerprint !=
            e.configuration) {
      throw const FormatException(
        'Evidence environment or configuration identity',
      );
    }
    final checksums = record['artifactChecksums'] as Json;
    if (checksums.length != e.artifacts.length) {
      throw const FormatException('Artifact coverage');
    }
    for (final name in e.artifacts) {
      final file = await authorizedFile(
        p.join(root, name),
        root,
        maxBytes: 8 * 1024 * 1024,
      );
      if (sha256.convert(await file.readAsBytes()).toString() !=
          hashField(checksums, name)) {
        throw const FormatException('Artifact checksum');
      }
    }
    evidence.add(e);
    if (evidence.length > 36) {
      throw const FormatException('Evidence count budget');
    }
  }
  return evidence;
}

Future<int> reviewCommand(Map<String, String> v) async {
  final scan = await readRun(required(v, '--run'));
  if ((scan['run'] as Json)['schemaVersion'] != 2) {
    throw const FormatException('Legacy report needs rescan');
  }
  final evidence = v['--evidence'] == null
      ? <VerificationEvidence>[]
      : await readEvidence(v['--evidence']!);
  final manual = v['--manual'] == null
      ? <Json>[]
      : objectList(
          await boundedJson(File(v['--manual']!)),
          'reviews',
          max: 2000,
        );
  // Static scanning does not execute a probe. Review pins the independently
  // executed evidence to this probe, retaining the scan-time identity.
  final scanRun = scan['run'] as Json;
  final reviewed = reviewLosses(
    {
      ...scan,
      'run': {
        ...scanRun,
        'scanProbe': scanRun['probe'],
        'probe': await probeIdentity(),
      },
    },
    evidence,
    manual: manual,
  );
  final out = await newOutput(required(v, '--out'));
  if (v['--evidence'] != null) {
    reviewed['evidenceIndex'] = p
        .relative(
          p.join(p.absolute(v['--evidence']!), 'verification.json'),
          from: out.path,
        )
        .replaceAll('\\', '/');
  }
  await publishRun(out, reviewed);
  stdout.writeln(
    'Review recommends ${(reviewed['recommendations'] as List).length} bounded items.',
  );
  return 0;
}

Future<Json> nativeWebViewProbe(
  Json request,
  Directory output,
  int seconds, {
  ProbeCancellation? cancellation,
}) async {
  // The explicit host entry is executable independently. A prebuilt diagnostic
  // executable can be supplied via this tool-only environment; never an app
  // installed in the user's regular library. No dependency is installed here.
  final executable = Platform.environment['SHIORI_LOSS_WEBVIEW_HOST'];
  if (executable == null || !await File(executable).exists()) {
    return {
      'complete': false,
      'observedPath': 'not_run',
      'reason': 'capability_unavailable',
      'layers': {for (final e in EvidenceLayer.values) wireName(e): 'not_run'},
      'assertions': {},
    };
  }
  final identityFile = File('$executable.identity.json');
  if (!await identityFile.exists()) {
    throw const FormatException('Diagnostic host identity missing');
  }
  final identity = await boundedJson(identityFile, maxBytes: 1024 * 1024);
  final producer = await producerIdentity(), probe = await probeIdentity();
  if (identity['producer'] != producer['fingerprint'] ||
      identity['probe'] != probe['fingerprint'] ||
      identity['executableHash'] !=
          sha256.convert(await File(executable).readAsBytes()).toString()) {
    throw const FormatException('Diagnostic host code identity changed');
  }
  final requestFile = p.join(output.path, 'webview-request.json'),
      resultFile = p.join(output.path, 'webview-result.json');
  request['result'] = resultFile;
  request['privateRoot'] = output.path;
  await atomicJson(requestFile, request, maxBytes: 1024 * 1024);
  final status = await boundedProcess(
    executable,
    [requestFile],
    Duration(seconds: seconds),
    log: p.join(output.path, 'webview-private.log'),
    cancellation: cancellation,
  );
  if (status != 'completed' || !await File(resultFile).exists()) {
    return {
      'complete': false,
      'observedPath': 'not_run',
      'reason': status,
      'layers': {},
      'assertions': {},
    };
  }
  return boundedJson(File(resultFile), maxBytes: 8 * 1024 * 1024);
}
