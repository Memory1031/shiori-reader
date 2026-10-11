import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import '../../tool/epub_audit/browser_probe.dart';
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
