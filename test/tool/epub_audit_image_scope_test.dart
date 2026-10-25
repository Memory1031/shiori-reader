import 'dart:convert';
import 'package:test/test.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/loss_model.dart';
import '../../tool/epub_audit/loss_report.dart';
import '../../tool/epub_audit/plan.dart';
import '../../tool/epub_audit/report.dart';
import 'epub_reading_loss_test.dart' show run, identified;
import 'support/audit_fixture.dart';
import '../data/local/support/epub_fixtures.dart';

const imageSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 1 1"><image width="1" height="1" href="../images/星 空.png"/></svg>';

void main() {
  test(
    'SVG source instances and containing visual scopes retain all block keys',
    () {
      final bytes = auditFixture(
        body: '<div style="border-radius:4px">$imageSvg$imageSvg</div>',
      );
      final book = identified(auditBytes(bytes), bytes);
      final sidecar = book['readingLoss'] as Json;
      final facts = (sidecar['sourceFacts'] as List).cast<Json>();
      final reps = (sidecar['representations'] as List).cast<Json>();
      final relations = (sidecar['correspondences'] as List).cast<Json>();
      final images = facts.where((f) => f['kind'] == 'image').toList();
      expect(images, hasLength(2));
      final keys = images
          .map(
            (f) => relations.firstWhere(
              (r) => r['sourceId'] == f['id'],
            )['representationIds'][0],
          )
          .map((id) => reps.firstWhere((r) => r['id'] == id)['blockKey'])
          .toSet();
      expect(
        keys,
        hasLength(2),
        reason: 'Repeated media requires distinct DOM instances',
      );
      final plan = makePlan(run(book), maxTargets: 12, provider: 'native');
      final targets = (plan['targets'] as List).cast<Json>();
      final container = targets.firstWhere(
        (t) =>
            t['candidate']['location']['domPath'] == 'html[1]/body[1]/div[1]',
      );
      expect(container['blockKeys'], unorderedEquals(keys));
      expect(container['targetResolution'], 'located');
      expect(
        targets.where(
          (t) => t['candidate']['rule'] == 'image.authored_alignment',
        ),
        isNotEmpty,
      );
    },
  );
  test(
    'unmapped non-document scopes are excluded before spending probe budget',
    () {
      final bytes = auditFixture(
        body: '<p style="border-radius:4px">Visible.</p>',
      );
      final book = identified(auditBytes(bytes), bytes);
      final sidecar = book['readingLoss'] as Json;
      sidecar['correspondences'] = <Json>[];
      final plan = makePlan(run(book), provider: 'native');
      expect(plan['selectedTargets'], 0);
      expect(
        (plan['notSelected'] as List).cast<Json>().any(
          (r) => r['reason'] == 'target_unresolved',
        ),
        true,
      );
    },
  );
  test(
    'whole-block image links are correlated without invented text offsets',
    () {
      final bytes = auditFixture(
        body:
            '<h1><a href="b.xhtml#b"><img src="../images/星 空.png"/></a></h1><p>Tail.</p>',
      );
      final b = auditBytes(bytes);
      final observations = (b['findings'] as List).cast<Json>();
      expect(
        observations.where(
          (f) => f['ruleId'] == 'link.relationship_unobserved',
        ),
        isEmpty,
      );
      final facts = ((b['readingLoss'] as Json)['sourceFacts'] as List)
          .cast<Json>();
      final link = facts.singleWhere(
        (f) =>
            f['kind'] == 'link' &&
            f['location']['document'] == 'OPS/text/a.xhtml',
      );
      expect(link['status'], 'pass');
      expect(link['details']['sourceKind'], 'block_image');
      expect(link['details']['sourceRange'], isNull);
    },
  );
  test('empty, missing and unreferenced stylesheets stay source facts', () {
    final files = epubFiles();
    files['OPS/book.opf'] = utf8.encode(
      utf8
          .decode(files['OPS/book.opf']!)
          .replaceFirst(
            '<manifest>',
            '<manifest><item id="empty" href="empty.css" media-type="text/css"/><item id="unused" href="unused.css" media-type="text/css"/><item id="missing" href="missing.css" media-type="text/css"/>',
          ),
    );
    files['OPS/empty.css'] = [];
    files['OPS/unused.css'] = [];
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><head><link rel="stylesheet" href="../empty.css"/><link rel="stylesheet" href="../missing.css"/></head><body><p>Visible.</p></body></html>',
    );
    final b = auditBytes(zipFiles(files));
    final styles = (b['stylesheets'] as List).cast<Json>();
    expect(
      styles.singleWhere((s) => s['path'] == 'OPS/empty.css')['referencedBy'],
      ['OPS/text/a.xhtml'],
    );
    expect(
      styles.singleWhere((s) => s['path'] == 'OPS/unused.css')['referencedBy'],
      isEmpty,
    );
    expect(
      styles.singleWhere((s) => s['path'] == 'OPS/missing.css')['status'],
      'missing',
    );
    expect(
      (b['findings'] as List).cast<Json>().where(
        (f) => f['ruleId'] == 'source.stylesheet_empty',
      ),
      hasLength(2),
    );
  });
  test(
    'oversized container is bounded without pretending its first child is the scope',
    () {
      final bytes = auditFixture(
        body:
            '<div style="border-radius:4px">${List.generate(1025, (i) => '<p>Unique $i.</p>').join()}</div>',
      );
      final b = identified(auditBytes(bytes), bytes);
      final plan = makePlan(run(b), provider: 'native');
      expect(
        (plan['notSelected'] as List).cast<Json>().where(
          (r) => r['reason'] == 'target_scope_budget',
        ),
        isNotEmpty,
      );
      expect(
        (plan['targets'] as List).cast<Json>().where(
          (t) =>
              t['candidate']['location']['domPath'] == 'html[1]/body[1]/div[1]',
        ),
        isEmpty,
      );
    },
  );
  test(
    'multiple-image anchors remain unknown rather than gaining a fake atomic range',
    () {
      final b = auditBytes(
        auditFixture(
          body:
              '<a href="b.xhtml#b"><img src="../images/星 空.png"/><img src="../images/星 空.png"/></a><p>Tail.</p>',
        ),
      );
      final observations = (b['findings'] as List).cast<Json>();
      expect(
        observations.where(
          (f) => f['ruleId'] == 'link.relationship_unobserved',
        ),
        isNotEmpty,
      );
      final links = ((b['readingLoss'] as Json)['sourceFacts'] as List)
          .cast<Json>()
          .where((f) => f['kind'] == 'link');
      expect(
        links.where((f) => f['details']['sourceKind'] == 'block_image'),
        isEmpty,
      );
    },
  );
  test(
    'evidence merging deduplicates identical instances and reports actual columns',
    () {
      final bytes = auditFixture(
        body: '<p style="border-radius:4px">Visible.</p>',
      );
      final b = identified(auditBytes(bytes), bytes),
          c = bookCandidates(b).first;
      final e = VerificationEvidence(
        id: 'e' * 64,
        candidateId: c.id,
        sourceId: c.sourceId,
        epubHash: c.location.epubHash,
        producer: 'a' * 64,
        probe: 'c' * 64,
        environment: 'f' * 64,
        configuration: 'd' * 64,
        provider: 'native',
        observedPath: 'native',
        layers: {EvidenceLayer.readerPath: CheckStatus.pass},
        complete: true,
        assertions: {
          'requestedColumns': 2,
          'observedColumns': [1],
          'targetVisible': true,
        },
      );
      final review = reviewLosses(run(b), [e, e]);
      expect(review['runtimeCoverage']['executedEvidence'], 1);
      expect(review['runtimeCoverage']['duplicateEvidence'], 1);
      expect(review['runtimeCoverage']['requestedTwoColumnEvidence'], 1);
      expect(review['runtimeCoverage']['observedTwoColumnEvidence'], 0);
      expect(review['run']['complete'], true);
    },
  );
}
