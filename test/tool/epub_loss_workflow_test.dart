import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import '../../tool/epub_audit/browser_probe.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/cli.dart';
import '../../tool/epub_audit/loss_model.dart';
import '../../tool/epub_audit/plan.dart';
import '../../tool/epub_audit/replay.dart';
import '../../tool/epub_audit/report.dart';
import '../../tool/epub_audit/workflow.dart';
import 'support/audit_fixture.dart';

Json browserSample({
  double right = 90,
  bool overlap = false,
  bool transparent = false,
}) => {
  'clientWidth': 100,
  'scrollWidth': 100,
  'clientHeight': 200,
  'scrollHeight': 200,
  'displacement': [0, 0],
  'fontsReady': true,
  'truncated': false,
  'rootOverflowX': 'hidden',
  'rootOverflowY': 'hidden',
  'scrollbarsHidden': true,
  'text': [
    for (var i = 0; i < (overlap ? 2 : 1); i++)
      {
        'domPath': 'html[1]/body[1]/p[${i + 1}]',
        'text': 'Private source 😀',
        'boxes': [
          {'left': 10, 'top': 10, 'right': right, 'bottom': 30},
        ],
        'color': 'rgb(0, 0, 0)',
        'background': transparent ? null : 'rgb(255, 255, 255)',
        'fontFamily': 'Private font',
        'fontSize': '20px',
        'lineHeight': '28px',
        'clip': 'hidden',
        'opacity': '1',
        'ancestorClips': <Json>[],
        'visibilityUnknown': false,
      },
  ],
  'images': [],
  'links': [
    {
      'domPath': 'a[1]',
      'rect': {'left': 10, 'top': 10, 'right': 30, 'bottom': 30},
      'address': 'https://private.invalid/secret',
    },
  ],
};
void main() {
  test('ancestor clipping is measured even inside the root viewport', () {
    final normal = browserSample();
    final text = (normal['text'] as List).single as Json;
    text['boxes'] = [
      for (var i = 0; i < 3; i++)
        {'left': 10, 'top': 10 + i * 30, 'right': 90, 'bottom': 30 + i * 30},
    ];
    text['ancestorClips'] = [];
    text['visibilityUnknown'] = false;
    expect(sanitizeBrowserMeasurement(normal)['unreachableClippedRanges'], 0);
    text['ancestorClips'] = [
      {
        'domPath': 'html[1]/body[1]/div[1]',
        'rect': {'left': 0, 'top': 0, 'right': 100, 'bottom': 38},
        'overflowX': 'hidden',
        'overflowY': 'hidden',
        'scrollLeft': 0,
        'scrollTop': 0,
        'maxScrollLeft': 0,
        'maxScrollTop': 62,
        'scrollbarsHidden': false,
      },
    ];
    expect(sanitizeBrowserMeasurement(normal)['unreachableClippedRanges'], 2);
    final clipped = sanitizeBrowserMeasurement(normal);
    expect((clipped['text'] as List).single['visibleBoxes'], hasLength(1));
    final ancestor = (text['ancestorClips'] as List).single as Json;
    ancestor['overflowY'] = 'clip';
    expect(sanitizeBrowserMeasurement(normal)['unreachableClippedRanges'], 2);
    ancestor['overflowY'] = 'auto';
    final scrollable = sanitizeBrowserMeasurement(normal);
    expect(scrollable['observedClippedRanges'], 2);
    expect(scrollable['unreachableClippedRanges'], 0);
    expect(browserGeometryStatus(scrollable), CheckStatus.pass);
    ancestor['scrollbarsHidden'] = true;
    expect(sanitizeBrowserMeasurement(normal)['unreachableClippedRanges'], 0);
    text['visibilityUnknown'] = true;
    final complex = sanitizeBrowserMeasurement(normal);
    expect(complex['unknownClippingRanges'], 1);
    expect(browserGeometryStatus(complex), CheckStatus.unknown);
    expect(jsonEncode(complex), isNot(contains('Private source')));
  });
  test('scroll reachability includes returning from a nonzero position', () {
    for (final horizontal in [false, true]) {
      for (final overflow in ['auto', 'scroll']) {
        for (final hiddenScrollbar in [false, true]) {
          for (final scroll in [0, 31, 62]) {
            final raw = browserSample();
            final text = (raw['text'] as List).single as Json;
            text['boxes'] = [
              for (var i = 0; i < 3; i++)
                {
                  'left': horizontal ? 10 + i * 30 - scroll : 10,
                  'top': horizontal ? 10 : 10 + i * 30 - scroll,
                  'right': horizontal ? 30 + i * 30 - scroll : 90,
                  'bottom': horizontal ? 30 : 30 + i * 30 - scroll,
                },
            ];
            text['ancestorClips'] = [
              {
                'rect': {
                  'left': 0,
                  'top': 0,
                  'right': horizontal ? 38 : 100,
                  'bottom': horizontal ? 200 : 38,
                },
                'overflowX': horizontal ? overflow : 'hidden',
                'overflowY': horizontal ? 'hidden' : overflow,
                'scrollLeft': horizontal ? scroll : 0,
                'scrollTop': horizontal ? 0 : scroll,
                'maxScrollLeft': horizontal ? 62 : 0,
                'maxScrollTop': horizontal ? 0 : 62,
                'scrollbarsHidden': hiddenScrollbar,
              },
            ];
            final measured = sanitizeBrowserMeasurement(raw);
            final reason = '$horizontal/$overflow/$hiddenScrollbar/$scroll';
            expect(measured['observedClippedRanges'], 2, reason: reason);
            expect(measured['unreachableClippedRanges'], 0, reason: reason);
            expect(measured['unknownClippingRanges'], 0, reason: reason);
            expect(browserGeometryStatus(measured), CheckStatus.pass);
            expect(
              (measured['text'] as List).single['visibleBoxes'],
              hasLength(1),
            );
            // A range beyond the container's entire scroll extent is a loss,
            // even though its three normal ranges are reachable.
            (text['boxes'] as List).add({
              'left': horizontal ? 120 - scroll : 10,
              'top': horizontal ? 10 : 120 - scroll,
              'right': horizontal ? 140 - scroll : 90,
              'bottom': horizontal ? 30 : 140 - scroll,
            });
            final outside = sanitizeBrowserMeasurement(raw);
            expect(outside['unreachableClippedRanges'], 1, reason: reason);
            expect(browserGeometryStatus(outside), CheckStatus.fail);
          }
        }
      }
    }
  });
  test('scroll reachability translates the viewport intersection', () {
    for (final top in [-10, 220]) {
      final raw = browserSample();
      final text = (raw['text'] as List).single as Json;
      text['boxes'] = [
        for (var i = 0; i < 3; i++)
          {
            'left': 10,
            'top': top + 10 + i * 30 - 62,
            'right': 90,
            'bottom': top + 30 + i * 30 - 62,
          },
      ];
      text['ancestorClips'] = [
        {
          'rect': {'left': 0, 'top': top, 'right': 100, 'bottom': top + 38},
          'overflowX': 'hidden',
          'overflowY': 'auto',
          'scrollLeft': 0,
          'scrollTop': 62,
          'maxScrollLeft': 0,
          'maxScrollTop': 62,
          'scrollbarsHidden': true,
        },
      ];
      final measured = sanitizeBrowserMeasurement(raw);
      expect(measured['unreachableClippedRanges'], top < 0 ? 0 : 3);
      expect(
        browserGeometryStatus(measured),
        top < 0 ? CheckStatus.pass : CheckStatus.fail,
      );
    }
  });
  test('hidden-scrollbar nested scrolling stays locally unknown', () {
    final raw = browserSample();
    final text = (raw['text'] as List).single as Json;
    text['boxes'] = [
      {'left': 10, 'top': 60, 'right': 90, 'bottom': 80},
    ];
    text['ancestorClips'] = [
      for (final overflow in ['auto', 'hidden'])
        {
          'rect': {'left': 0, 'top': 0, 'right': 100, 'bottom': 38},
          'overflowX': 'hidden',
          'overflowY': overflow,
          'scrollLeft': 0,
          'scrollTop': 0,
          'maxScrollLeft': 0,
          'maxScrollTop': 62,
          'scrollbarsHidden': true,
        },
    ];
    final measured = sanitizeBrowserMeasurement(raw);
    expect(measured['unknownClippingRanges'], 1);
    expect(measured['unreachableClippedRanges'], 0);
    expect(browserGeometryStatus(measured), CheckStatus.unknown);
  });
  for (final completedFirst in [false, true]) {
    test(
      'verify interruption stops dispatch and keeps its journal (completed first: $completedFirst)',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'shiori-loss-interrupt-',
        );
        final signals = StreamController<ProcessSignal>.broadcast(sync: true);
        try {
          final bytes = auditFixture(
            body:
                '<p style="border-radius:12px">Target A.</p><p style="border-radius:18px">Target B.</p>',
          );
          final snapshot = await produce(bytes);
          final bundle = await Directory('${root.path}/bundle').create();
          await writeBundle(snapshot, bundle);
          final book = {...auditBytes(bytes), 'sha256': snapshot.hash};
          final scan = <String, dynamic>{
            'run': {
              'schemaVersion': 2,
              'producer': snapshot.producer,
              'evaluator': await evaluatorIdentity(),
              'probe': await probeIdentity(),
              'optionsFingerprint': 'd' * 64,
              'complete': true,
            },
            'books': [book],
          };
          final plan = makePlan(scan, maxTargets: 1, maxConfigurations: 1);
          final target = VerificationTarget.fromJson(
            (plan['targets'] as List).single as Json,
          );
          final first = VerificationTarget(
            target.candidate,
            target.chapterKey,
            target.blockKey,
            [ProbeConfiguration(), ProbeConfiguration(width: 320)],
            maxScreenshots: 0,
          );
          final secondCandidate =
              objectList(book['readingLoss'] as Json, 'candidates')
                  .map(LossCandidate.fromJson)
                  .firstWhere(
                    (c) =>
                        c.location.document ==
                            target.candidate.location.document &&
                        c.location.domPath != target.candidate.location.domPath,
                  );
          final second = VerificationTarget(
            secondCandidate,
            target.chapterKey,
            null,
            [ProbeConfiguration()],
            maxScreenshots: 0,
          );
          expect(second.candidate.sourceId, isNot(first.candidate.sourceId));
          plan['targets'] = [first.toJson(), second.toJson()];
          await atomicJson('${root.path}/plan.json', plan);
          final entry = File('${root.path}/worker.dart');
          final ready = File('${root.path}/ready');
          await entry.writeAsString(
            "import 'dart:io'; Future<void> main(List<String> args) async {await File(args.single).writeAsString('ready'); await Future<void>.delayed(Duration(minutes:2));}",
          );
          var started = 0, workerExited = false;
          final result = await verifyCommand(
            {
              '--provider': 'native',
              '--plan': '${root.path}/plan.json',
              '--bundle': bundle.path,
              '--allow-root': root.path,
              '--out': '${root.path}/verification',
            },
            testOnlySignals: signals.stream,
            testOnlyFlutterProbe: (request, output, seconds) async {
              started++;
              if (started != (completedFirst ? 2 : 1)) {
                return {
                  'complete': true,
                  'reason': 'executed',
                  'observedPath': 'native',
                  'layers': <String, dynamic>{},
                  'assertions': <String, dynamic>{},
                };
              }
              final worker = boundedProcess(
                auditDartExecutable(),
                [entry.path, ready.path],
                const Duration(seconds: 10),
                testOnlySignals: signals.stream,
              );
              for (var i = 0; i < 200 && !await ready.exists(); i++) {
                await Future<void>.delayed(const Duration(milliseconds: 25));
              }
              expect(await ready.exists(), true);
              signals.add(ProcessSignal.sigint);
              final status = await worker;
              workerExited = true;
              return {
                'complete': false,
                'reason': status,
                'observedPath': 'not_run',
                'layers': <String, dynamic>{},
                'assertions': <String, dynamic>{},
              };
            },
          );
          expect(result, 130);
          expect(workerExited, true);
          expect(started, completedFirst ? 2 : 1);
          final evidence = await readEvidence('${root.path}/verification');
          expect(evidence, hasLength(completedFirst ? 2 : 1));
          expect(evidence.last.reason, 'interrupted');
          if (completedFirst) {
            expect(evidence.first.reason, 'executed');
            expect(evidence.first.complete, true);
          }
          final index = await boundedJson(
            File('${root.path}/verification/verification.json'),
          );
          expect(index['complete'], false);
          expect(index['notRun'], hasLength(completedFirst ? 1 : 2));
          expect(
            (index['notRun'] as List).every(
              (e) => e['reason'] == 'run_interrupted',
            ),
            true,
          );
        } finally {
          await signals.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
  test('cancelled scope never dispatches another replay or process', () async {
    final root = await Directory.systemTemp.createTemp(
      'shiori-loss-cancelled-',
    );
    final cancellation = ProbeCancellation(signals: const Stream.empty())
      ..cancel();
    try {
      expect(
        await boundedProcess(
          'nonexistent-worker',
          [],
          const Duration(seconds: 1),
          cancellation: cancellation,
        ),
        'interrupted',
      );
      final result = await replayOperation(
        {'action': 'capture', 'input': 'must-not-be-read'},
        root,
        cancellation: cancellation,
      );
      expect(result['status'], 'interrupted');
      expect(await File('${root.path}/replay-result.json').exists(), false);
    } finally {
      await cancellation.close();
      await root.delete(recursive: true);
    }
  });
  test(
    'browser geometry separates clipping, overlap, scrolling and unknown backgrounds',
    () {
      final normal = sanitizeBrowserMeasurement(browserSample());
      expect(normal['unreachableClippedRanges'], 0);
      expect(normal['overlappingTextRanges'], 0);
      expect(
        sanitizeBrowserMeasurement(
          browserSample(right: 140),
        )['unreachableClippedRanges'],
        1,
      );
      expect(
        sanitizeBrowserMeasurement(
          browserSample(overlap: true),
        )['overlappingTextRanges'],
        greaterThan(0),
      );
      expect(
        sanitizeBrowserMeasurement(
          browserSample(transparent: true),
        )['unknownBackgroundRanges'],
        1,
      );
      expect(jsonEncode(normal), isNot(contains('Private')));
      expect(jsonEncode(normal), isNot(contains('private.invalid')));
    },
  );
  test(
    'every CLI command rejects existing output and unknown arguments',
    () async {
      expect(await auditMain(['plan', '--unknown', 'value']), 64);
      expect(await auditMain(['verify', '--provider', 'fictional']), 64);
      expect(
        await auditMain([
          'evaluate',
          '--bundle',
          'missing',
          '--allow-root',
          'missing',
          '--out',
          'unused',
        ]),
        73,
      );
    },
  );
  test(
    'actual capture evaluate plan review round trip preserves model and regenerates Markdown',
    () async {
      final root = await Directory.systemTemp.createTemp('shiori-loss-cli-');
      try {
        final source = File('${root.path}/book.epub');
        await source.writeAsBytes(
          auditFixture(
            body: '<p style="border-radius:12px">Private source text.</p>',
          ),
        );
        expect(
          await auditMain([
            'capture',
            '--input',
            source.path,
            '--allow-root',
            root.path,
            '--out',
            '${root.path}/bundle',
          ]),
          0,
        );
        expect(
          await auditMain([
            'evaluate',
            '--bundle',
            '${root.path}/bundle',
            '--allow-root',
            root.path,
            '--out',
            '${root.path}/evaluated',
          ]),
          0,
        );
        expect(
          await auditMain([
            'plan',
            '--run',
            '${root.path}/evaluated',
            '--out',
            '${root.path}/plan',
            '--max-targets',
            '1',
            '--configurations',
            '1',
          ]),
          0,
        );
        expect(
          await auditMain([
            'review',
            '--run',
            '${root.path}/evaluated',
            '--out',
            '${root.path}/review',
          ]),
          0,
        );
        expect(
          await auditMain([
            'verify',
            '--plan',
            '${root.path}/plan/plan.json',
            '--bundle',
            '${root.path}/bundle',
            '--allow-root',
            root.path,
            '--provider',
            'webview',
            '--out',
            '${root.path}/unavailable',
          ]),
          69,
        );
        final unavailable = await readEvidence('${root.path}/unavailable');
        expect(unavailable.single.observedPath, 'not_run');
        expect(unavailable.single.reason, 'capability_unavailable');
        expect(unavailable.single.assertions, isEmpty);
        final priorScan = await boundedJson(
          File('${root.path}/evaluated/report.json'),
        );
        (priorScan['run'] as Json)['probe'] = {'fingerprint': 'f' * 64};
        await atomicJson('${root.path}/evaluated/report.json', priorScan);
        expect(
          await auditMain([
            'review',
            '--run',
            '${root.path}/evaluated',
            '--evidence',
            '${root.path}/unavailable',
            '--out',
            '${root.path}/later-probe-review',
          ]),
          0,
        );
        final laterReview = await readRun('${root.path}/later-probe-review');
        expect(laterReview['rejectedEvidence'], isEmpty);
        expect(laterReview['verification'], hasLength(1));
        expect(
          (laterReview['run'] as Json)['scanProbe']['fingerprint'],
          'f' * 64,
        );
        expect(
          (laterReview['run'] as Json)['probe']['fingerprint'],
          unavailable.single.probe,
        );
        final result = await readRun('${root.path}/review');
        final stored = await boundedJson(
          File('${root.path}/review/report.json'),
        );
        expect(
          await File('${root.path}/review/report.md').readAsString(),
          reportMarkdown(stored),
        );
        expect((result['books'] as List).single['readingLoss'], isNotNull);
        expect(jsonEncode(result), isNot(contains('Private source text.')));
        expect(
          await auditMain([
            'plan',
            '--run',
            '${root.path}/evaluated',
            '--out',
            '${root.path}/plan',
          ]),
          73,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'damaged evidence, changed environment and damaged screenshot cannot be imported',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'shiori-loss-evidence-',
      );
      try {
        final env = {'platform': 'test'}, config = ProbeConfiguration();
        final e = VerificationEvidence(
          id: 'a' * 64,
          candidateId: 'b' * 64,
          sourceId: 'c' * 64,
          epubHash: 'd' * 64,
          producer: 'e' * 64,
          probe: 'f' * 64,
          environment: digest(jsonEncode(env)),
          configuration: config.fingerprint,
          provider: 'native',
          observedPath: 'native',
          layers: {EvidenceLayer.widgetGeometry: CheckStatus.pass},
          complete: true,
          artifacts: ['page.png'],
        );
        final image = File('${root.path}/page.png');
        await image.writeAsBytes([1, 2, 3]);
        final file = File('${root.path}/evidence-00000.json');
        Future<void> publish(Json environment) async {
          await atomicJson(file.path, {
            'evidence': e.toJson(),
            'environment': environment,
            'configurationDetail': config.toJson(),
            'artifactChecksums': {
              'page.png': sha256.convert([1, 2, 3]).toString(),
            },
          });
          await File('${root.path}/evidence.jsonl').writeAsString(
            '${jsonEncode({'file': 'evidence-00000.json', 'sha256': sha256.convert(await file.readAsBytes()).toString()})}\n{"partial":',
          );
        }

        await publish(env);
        expect(await readEvidence(root.path), hasLength(1));
        await image.writeAsBytes([3, 2, 1]);
        await expectLater(readEvidence(root.path), throwsFormatException);
        await image.writeAsBytes([1, 2, 3]);
        await publish({'platform': 'other'});
        await expectLater(readEvidence(root.path), throwsFormatException);
        await publish(env);
        await file.writeAsString('{}');
        await expectLater(readEvidence(root.path), throwsFormatException);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('new bounded process timeout waits for the owned worker exit', () async {
    final root = await Directory.systemTemp.createTemp('shiori-loss-process-');
    try {
      final entry = File('${root.path}/wait.dart');
      await entry.writeAsString(
        "import 'dart:async'; Future<void> main() async {await Future<void>.delayed(Duration(minutes:2));}",
      );
      expect(
        await boundedProcess(auditDartExecutable(), [
          entry.path,
        ], const Duration(milliseconds: 100)),
        'timeout',
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
