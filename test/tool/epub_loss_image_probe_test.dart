import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_image.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/loss_report.dart';
import '../../tool/epub_audit/native_probe.dart';
import '../../tool/epub_audit/plan.dart';
import '../../tool/epub_audit/replay.dart';
import '../../tool/epub_audit/report.dart';
import '../data/local/support/epub_fixtures.dart';
import '../data/local/support/oriented_jpeg.dart';

const svg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 80 200"><image width="80" height="200" href="../images/星 空.png"/></svg>';
Future<ProducerSnapshot> imageBook(
  WidgetTester tester,
  String body, {
  String imagePath = 'OPS/images/星 空.png',
}) async => (await tester.runAsync(() async {
  final files = epubFiles();
  files[imagePath] = fixturePng(80, 200, 2);
  files['OPS/text/a.xhtml'] = utf8.encode('<html><body>$body</body></html>');
  return produce(zipFiles(files));
}))!;
VerificationTarget imageTarget(
  ProducerSnapshot s, {
  ProbeConfiguration? config,
  String rule = 'image.authored_alignment',
}) {
  final candidate = bookCandidates(
    auditParsed(s.parser, s.parsed),
  ).firstWhere((c) => c.rule == rule);
  final chapter = s.parsed.content.chapters.first;
  return VerificationTarget(
    candidate,
    chapter.key.toJson(),
    chapter.blocks.whereType<ImageBlock>().first.blockKey,
    [config ?? ProbeConfiguration(width: 1000, height: 800)],
  );
}

void main() {
  testWidgets(
    'oriented JPEG SVG gets a measured alignment expectation without rotating bytes',
    (tester) async {
      final snapshot = (await tester.runAsync(() async {
        final files = epubFiles();
        files['OPS/images/oriented.jpg'] = jpegWithSegments([
          orientationSegment(8),
        ]);
        files['OPS/text/a.xhtml'] = utf8.encode(
          '<html><body><p>Before.</p>'
          '<svg width="100%" height="100%" viewBox="0 0 200 80">'
          '<image width="200" height="80" href="../images/oriented.jpg"/>'
          '</svg><p>After.</p></body></html>',
        );
        return produce(zipFiles(files));
      }))!;
      final target = imageTarget(
        snapshot,
        config: ProbeConfiguration(width: 1600, height: 350),
      );
      final result = await runNativeProbe(
        tester,
        snapshot,
        target,
        target.configurations.first,
      );
      final a = result['assertions'] as Json;
      expect(a['candidateFeatureStatus'], 'pass');
      final image = (a['decodedImages'] as List).cast<Json>().firstWhere(
        (i) => i['candidateScope'] == true,
      );
      expect(image['encodedNaturalSize'], {'width': 80, 'height': 200});
      expect(image['modelNaturalSize'], {'width': 80, 'height': 200});
      expect(image['displayNaturalSize'], {'width': 200, 'height': 80});
      expect(image['alignmentBasis'], 'source_single_raster_svg_meet');
      expect(image['alignmentStatus'], 'pass');
      expect(image['decodedWidth'], greaterThan(image['decodedHeight']));
    },
  );
  testWidgets(
    'standalone flow image policy is measured and wrong alignment fails',
    (tester) async {
      final s = await imageBook(
        tester,
        '<div><p><img src="../images/flow.png"/></p></div>',
        imagePath: 'OPS/images/flow.png',
      );
      final target = imageTarget(
        s,
        rule: 'image.reader_default_alignment',
        config: ProbeConfiguration(width: 1600, height: 350, columns: 2),
      );
      final result = await runNativeProbe(
        tester,
        s,
        target,
        target.configurations.first,
      );
      final a = result['assertions'] as Json;
      expect(a['candidateFeatureStatus'], 'pass');
      final image = (a['decodedImages'] as List).cast<Json>().firstWhere(
        (i) => i['candidateScope'] == true,
      );
      expect(image['alignmentBasis'], 'reader_single_image_document_default');
      expect(image['role'], 'flow');
      expect(image['displayNaturalSize'], {'width': 80, 'height': 200});
      final damaged = await runNativeProbe(
        tester,
        s,
        target,
        target.configurations.first,
        testOnlyTamper: (tester) async {
          final align = find
              .descendant(
                of: find.byType(ReaderImage).first,
                matching: find.byType(Align),
              )
              .first;
          tester.renderObject<RenderPositionedBox>(align).alignment =
              Alignment.centerLeft;
          await tester.pump();
        },
      );
      expect(damaged['assertions']['candidateFeatureStatus'], 'fail');
    },
  );
  testWidgets(
    'image probe measures painted pixels and detects misalignment inside viewport',
    (tester) async {
      final s = await imageBook(tester, '<p>Before.</p>$svg<p>After.</p>');
      final target = imageTarget(s);
      final normal = await runNativeProbe(
        tester,
        s,
        target,
        target.configurations.first,
      );
      final a = normal['assertions'] as Json;
      expect(a['candidateFeatureStatus'], 'pass');
      final image = (a['decodedImages'] as List).cast<Json>().firstWhere(
        (i) => i['candidateScope'] == true,
      );
      expect(image['encodedNaturalSize'], {'width': 80, 'height': 200});
      expect(image, contains('decodedWidth'));
      expect(image, isNot(contains('naturalWidth')));
      expect(image['paintRect'], isNotNull);
      final damaged = await runNativeProbe(
        tester,
        s,
        target,
        target.configurations.first,
        testOnlyTamper: (tester) async {
          final align = find
              .descendant(
                of: find.byType(ReaderImage).first,
                matching: find.byType(Align),
              )
              .first;
          tester.renderObject<RenderPositionedBox>(align).alignment =
              Alignment.centerLeft;
          await tester.pump();
        },
      );
      expect(damaged['assertions']['candidateFeatureStatus'], 'fail');
      expect(damaged['assertions']['geometryFailures'], greaterThan(0));
    },
  );
  testWidgets(
    'unresolved target returns without constructing or walking Reader',
    (tester) async {
      final s = await imageBook(tester, '<p>Before.</p>$svg');
      final known = imageTarget(s);
      final unresolved = VerificationTarget(
        known.candidate,
        known.chapterKey,
        null,
        known.configurations,
      );
      final result = await runNativeProbe(
        tester,
        s,
        unresolved,
        unresolved.configurations.first,
        testOnlyTamper: (_) async =>
            throw StateError('must not start a page walk'),
      );
      expect(result['reason'], 'target_unresolved');
      expect(result['assertions']['targetLocated'], false);
      expect(result['assertions']['pages'], isEmpty);
    },
  );
  testWidgets(
    'page budget exhaustion is separate from located and visible target',
    (tester) async {
      final s = await imageBook(
        tester,
        '<p style="border-radius:4px">${'Long content. ' * 1500}</p>',
      );
      final c = bookCandidates(auditParsed(s.parser, s.parsed)).first;
      final chapter = s.parsed.content.chapters.first;
      final target = VerificationTarget(
        c,
        chapter.key.toJson(),
        chapter.blocks.first.blockKey,
        [ProbeConfiguration()],
        maxPages: 1,
      );
      final result = await runNativeProbe(
        tester,
        s,
        target,
        target.configurations.first,
      );
      expect(result['reason'], 'page_budget_exhausted');
      expect(result['assertions']['targetLocated'], true);
      expect(result['assertions']['targetVisible'], true);
      expect(result['assertions']['reachedDocumentEnd'], false);
    },
  );
  testWidgets(
    'requested double columns do not certify image-only double-column coverage',
    (tester) async {
      final s = await imageBook(tester, svg);
      final target = imageTarget(
        s,
        config: ProbeConfiguration(width: 1600, height: 1000, columns: 2),
      );
      final result = await runNativeProbe(
        tester,
        s,
        target,
        target.configurations.first,
      );
      expect(result['assertions']['requestedColumns'], 2);
      expect(result['assertions']['observedColumns'], [1]);
      expect(result['assertions']['candidateFeatureStatus'], 'pass');
    },
  );
  testWidgets(
    'atomic image link checks preview, actual menu navigation and return separately',
    (tester) async {
      final s = await imageBook(
        tester,
        '<h1><a href="b.xhtml#b">$svg</a></h1><p>After.</p>',
      );
      final target = imageTarget(s);
      final result = await runNativeProbe(
        tester,
        s,
        target,
        target.configurations.first,
      );
      final a = result['assertions'] as Json;
      final check = (a['imageLinkChecks'] as List).single as Json;
      expect(check['directImageClick'], 'preview_opened_by_reader_policy');
      expect(check['alternativeEntry'], 'target_reached');
      expect(check['returnToSource'], 'pass');
      expect(a['inputChecks'], greaterThanOrEqualTo(3));
      expect(a['inputFailures'], 0);
    },
  );
}
