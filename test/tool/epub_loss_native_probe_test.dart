import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/epub_audit/native_probe.dart';
import '../../tool/epub_audit/plan.dart';
import '../../tool/epub_audit/replay.dart';
import '../../tool/epub_audit/loss_report.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/report.dart';
import 'support/audit_fixture.dart';

void main() {
  final input = Platform.environment['SHIORI_LOSS_REQUEST'];
  if (input != null) {
    testWidgets(
      'fixed structured reading-loss probe',
      (tester) async {
        late Json request;
        late ProducerSnapshot snapshot;
        await tester.runAsync(() async {
          request = await boundedJson(File(input), maxBytes: 1024 * 1024);
          snapshot = await readBundle(
            request['bundle'] as String,
            request['allowRoot'] as String,
          );
        });
        final target = VerificationTarget.fromJson(request['target'] as Json);
        final config = ProbeConfiguration.fromJson(
          request['configuration'] as Json,
        );
        Json result;
        if (request['mode'] == 'host_html') {
          final html = await tester.runAsync(
            () => prepareBrowserDocument(snapshot, target, config),
          );
          await tester.runAsync(
            () => File(
              request['htmlOutput'] as String,
            ).writeAsString(html!, flush: true),
          );
          result = {
            'status': 'host_document_prepared',
            'producer': snapshot.producer,
          };
        } else {
          result = await runNativeProbe(
            tester,
            snapshot,
            target,
            config,
            screenshot: request['screenshot'] as String?,
            font: request['font'] as String?,
          );
        }
        await tester.runAsync(
          () => atomicJson(request['result'] as String, result),
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  } else {
    testWidgets(
      'passive diagnostics preserve complete model resources position and painted pixels',
      (tester) async {
        late ProducerSnapshot snapshot;
        late Directory root;
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp('shiori-loss-toggle-');
          snapshot = await produce(
            auditFixture(
              body:
                  '<p style="border:3px solid blue;border-radius:12px;background-color:white;color:black">Passive observation.</p><p>Tail.</p>',
            ),
          );
        });
        try {
          final before = jsonEncode(snapshot.modelJson());
          final candidate = bookCandidates(
            auditParsed(snapshot.parser, snapshot.parsed),
          ).first;
          final chapter = snapshot.parsed.content.chapters.first;
          final target = VerificationTarget(
            candidate,
            chapter.key.toJson(),
            chapter.blocks.first.blockKey,
            [ProbeConfiguration()],
          );
          final disabled = await runNativeProbe(
            tester,
            snapshot,
            target,
            target.configurations.first,
            screenshot: '${root.path}/off.png',
            testOnlyObserveLinks: false,
          );
          final enabled = await runNativeProbe(
            tester,
            snapshot,
            target,
            target.configurations.first,
            screenshot: '${root.path}/on.png',
          );
          expect(jsonEncode(snapshot.modelJson()), before);
          expect(jsonEncode(enabled), jsonEncode(disabled));
          await tester.runAsync(() async {
            expect(
              sha256.convert(await File('${root.path}/off.png').readAsBytes()),
              sha256.convert(await File('${root.path}/on.png').readAsBytes()),
            );
          });
        } finally {
          await tester.runAsync(() => root.delete(recursive: true));
        }
      },
    );
    testWidgets(
      'native probe uses production Reader and independent character identity',
      (tester) async {
        late ProducerSnapshot snapshot;
        await tester.runAsync(() async {
          snapshot = await produce(
            auditFixture(
              body:
                  '<p style="background-color:#222;color:white;border:3px solid blue;border-radius:12px">Self authored visible probe.</p><p>Tail.</p>',
            ),
          );
        });
        final report = auditParsed(snapshot.parser, snapshot.parsed);
        final candidate = bookCandidates(report).first;
        final target = VerificationTarget(
          candidate,
          snapshot.parsed.content.chapters.first.key.toJson(),
          snapshot.parsed.content.chapters.first.blocks.first.blockKey,
          [ProbeConfiguration()],
        );
        final result = await runNativeProbe(
          tester,
          snapshot,
          target,
          target.configurations.first,
        );
        expect(result['observedPath'], 'native');
        expect((result['assertions'] as Json)['characterIdentityFailures'], 0);
        expect((result['assertions'] as Json)['restoreVisible'], true);
        expect((result['layers'] as Json)['audio_decode'], 'not_run');
        expect(
          jsonEncode(result),
          isNot(contains('Self authored visible probe.')),
        );
      },
    );
  }
}
