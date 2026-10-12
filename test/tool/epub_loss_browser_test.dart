import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/browser_probe.dart';
import '../../tool/epub_audit/cli.dart' show auditDartExecutable;
import '../../tool/epub_audit/loss_report.dart';
import '../../tool/epub_audit/plan.dart';
import 'support/audit_fixture.dart';

VerificationTarget browserTarget() {
  final book = auditBytes(
    auditFixture(
      body:
          '<div id="frame"><p style="border-radius:12px">VISIBLE LINE<br/>SECOND LINE<br/>THIRD LINE</p></div>',
    ),
  );
  return VerificationTarget(bookCandidates(book).first, null, null, [
    ProbeConfiguration(),
  ], timeoutSeconds: 20);
}

void main() {
  test(
    'failed browser launch reports its exit and cleans its profile',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'shiori-browser-exit-',
      );
      try {
        final target = browserTarget();
        await expectLater(
          runBrowserProbe(
            '<html><body>Self authored.</body></html>',
            root,
            target,
            target.configurations.single,
            // Dart rejects the browser flags and exits without a debug endpoint.
            testOnlyExecutable: auditDartExecutable(),
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'startup exit',
              contains('Browser exited before endpoint (code '),
            ),
          ),
        );
        expect(await Directory('${root.path}/browser-profile').exists(), false);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('actual Chromium detects only runtime-injected ancestor clipping', () async {
    final root = await Directory.systemTemp.createTemp('shiori-loss-browser-');
    try {
      const html =
          '<html><head><style>body{margin:0;background:white;color:black}p{margin:0;font:20px/28px sans-serif}</style></head>'
          '<body><div id="frame"><p>VISIBLE LINE<br>SECOND LINE<br>THIRD LINE</p></div></body></html>';
      final target = browserTarget(), config = target.configurations.single;
      final beforeRoot = await Directory('${root.path}/before').create();
      final afterRoot = await Directory('${root.path}/after').create();
      final before = await runBrowserProbe(
        html,
        beforeRoot,
        target,
        config,
        screenshot: '${beforeRoot.path}/page.png',
      );
      if (installedChromium() == null) {
        expect(before['reason'], 'capability_unavailable');
        return;
      }
      final after = await runBrowserProbe(
        html,
        afterRoot,
        target,
        config,
        screenshot: '${afterRoot.path}/page.png',
        testOnlyBeforeInspection:
            "document.getElementById('frame').style.cssText='height:28px;overflow:hidden'",
      );
      expect(before['layers']['browser_geometry'], 'pass');
      expect(before['assertions']['unreachableClippedRanges'], 0);
      expect(after['layers']['browser_geometry'], 'fail');
      expect(after['assertions']['unreachableClippedRanges'], 2);
      expect(after['assertions']['observedClippedRanges'], 2);
      expect(after['assertions']['clippingSourceIntent'], 'unverified');
      expect(after['assertions']['unknownClippingRanges'], 0);
      final evidence = Platform.environment['SHIORI_LOSS_REVIEW_EVIDENCE'];
      if (evidence != null) {
        await Directory(evidence).create(recursive: true);
        for (final row in [
          ('before', before, beforeRoot),
          ('after', after, afterRoot),
        ]) {
          await File(
            '$evidence/${row.$1}.json',
          ).writeAsString(jsonEncode(row.$2));
          await File('${row.$3.path}/page.png').copy('$evidence/${row.$1}.png');
        }
      }
    } finally {
      await root.delete(recursive: true);
    }
  });
  for (final scrollbar in ['auto', 'none']) {
    for (final scroll in [0, 28, 56]) {
      test('actual Chromium scrolls back ($scrollbar, $scroll)', () async {
        final root = await Directory.systemTemp.createTemp(
          'shiori-loss-scroll-',
        );
        try {
          const html =
              '<!doctype html><html><head><style>body{margin:0;background:white;color:black}p{margin:0;font:20px/28px sans-serif}</style></head>'
              '<body><div id="frame"><p>VISIBLE LINE<br>SECOND LINE<br>THIRD LINE</p></div></body></html>';
          final target = browserTarget();

          final name = '$scrollbar-$scroll';
          final directory = await Directory('${root.path}/$name').create();
          final measured = await runBrowserProbe(
            html,
            directory,
            target,
            target.configurations.single,
            screenshot: '${directory.path}/page.png',
            // Set the real browser container position before measuring; this
            // is host test setup, not an assertion of wheel/touch routing.
            testOnlyBeforeInspection:
                "{const f=document.getElementById('frame');f.style.cssText='width:240px;height:28px;overflow:auto;scrollbar-width:$scrollbar';f.scrollTop=$scroll;}",
          );
          if (installedChromium() == null) {
            expect(measured['reason'], 'capability_unavailable');
            return;
          }
          final assertions = measured['assertions'];
          final ancestor = assertions['text'][0]['ancestorClips'][0];
          expect(ancestor['scrollTop'], scroll, reason: name);
          expect(ancestor['maxScrollTop'], 56, reason: name);
          expect(
            ancestor['scrollbarsHidden'],
            scrollbar == 'none',
            reason: name,
          );
          expect(assertions['observedClippedRanges'], 2, reason: name);
          expect(assertions['unreachableClippedRanges'], 0, reason: name);
          expect(assertions['unknownClippingRanges'], 0, reason: name);
          expect(measured['layers']['browser_geometry'], 'pass', reason: name);
          final evidence = Platform.environment['SHIORI_LOSS_REVIEW_EVIDENCE'];
          if (evidence != null) {
            await Directory(evidence).create(recursive: true);
            await File(
              '$evidence/$name.json',
            ).writeAsString(jsonEncode(measured));
            await File(
              '${directory.path}/page.png',
            ).copy('$evidence/$name.png');
          }
        } finally {
          await root.delete(recursive: true);
        }
      });
    }
  }
  test(
    'actual browser cancellation waits for owned process and cleans profile',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'shiori-loss-browser-cancel-',
      );
      final signals = StreamController<ProcessSignal>.broadcast(sync: true);
      final cancellation = ProbeCancellation(signals: signals.stream);
      try {
        var started = false;
        final target = browserTarget();
        final result = await runBrowserProbe(
          '<html><body>Self authored.</body></html>',
          root,
          target,
          target.configurations.single,
          cancellation: cancellation,
          testOnlyOnStarted: () {
            started = true;
            signals.add(ProcessSignal.sigint);
          },
        );
        if (installedChromium() == null) {
          expect(result['reason'], 'capability_unavailable');
        } else {
          expect(started, true);
          expect(result['reason'], 'interrupted');
          expect(
            await Directory('${root.path}/browser-profile').exists(),
            false,
          );
        }
        final notStarted = await runBrowserProbe(
          '',
          root,
          target,
          target.configurations.single,
          cancellation: cancellation,
          testOnlyOnStarted: () => fail('Cancelled run dispatched browser'),
        );
        if (started) expect(notStarted['reason'], 'interrupted');
      } finally {
        await cancellation.close();
        await signals.close();
        await root.delete(recursive: true);
      }
    },
  );
}
