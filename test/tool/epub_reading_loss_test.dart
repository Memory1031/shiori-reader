import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:crypto/crypto.dart';
import 'package:shiori/domain/models/models.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/loss_model.dart';
import '../../tool/epub_audit/loss_report.dart';
import '../../tool/epub_audit/plan.dart';
import '../../tool/epub_audit/replay.dart';
import '../../tool/epub_audit/report.dart';
import 'support/audit_fixture.dart';
import 'epub_audit_test.dart' show changed;

Json run(Json book, {String producer = 'a', String evaluator = 'b'}) => {
  'run': {
    'schemaVersion': 2,
    'auditRulesVersion': '2.0.0',
    'parserVersion': 27,
    'producer': {'fingerprint': producer * 64},
    'evaluator': {'fingerprint': evaluator * 64},
    'probe': {'fingerprint': 'c' * 64},
    'optionsFingerprint': 'd' * 64,
    'complete': true,
  },
  'books': [book],
  'aggregate': aggregateBooks([book]),
  'lossSummary': summarizeLosses([book]),
};
Json identified(Json book, List<int> bytes) => {
  ...book,
  'sha256': sha256.convert(bytes).toString(),
  'aliases': ['synthetic'],
};

void main() {
  test(
    'sidecar exhaustion preserves real failures and cannot invent missing media',
    () {
      final bytes = auditFixture(
        body:
            '<p style="border-radius:12px">One.</p><p style="border-radius:12px">Two.</p><p>Three.</p><img src="../images/星 空.png"/>',
      );
      final parser = fixtureParser(bytes),
          parsed = parser.parse(),
          chapter = parsed.content.chapters.first;
      final limited = auditParsed(
        parser,
        parsed,
        options: const AuditOptions(maxFindings: 2),
      );
      expect(
        bookCandidates(limited).any(
          (c) => c.family == LossFamily.content && c.status == CheckStatus.fail,
        ),
        false,
      );
      final fault = changed(
        parsed,
        chapters: [
          ChapterContent(
            key: chapter.key,
            title: chapter.title,
            blocks: chapter.blocks.where(
              (b) => b is! ParagraphBlock || b.text != 'Three.',
            ),
          ),
          ...parsed.content.chapters.skip(1),
        ],
      );
      final report = auditParsed(
        parser,
        fault,
        options: const AuditOptions(maxFindings: 2),
      );
      expect(
        bookCandidates(report).any(
          (c) =>
              c.rule == 'text.simple_block_mismatch' &&
              c.status == CheckStatus.fail,
        ),
        true,
      );
      expect(
        (report['readingLoss'] as Json)['coverage']['factsComplete'],
        false,
      );
    },
  );
  test(
    'source, representation and correspondence preserve repeated occurrences and privacy',
    () {
      final bytes = baselineFixtures()['mixed']!;
      final parser = fixtureParser(bytes), parsed = parser.parse();
      final book = auditParsed(parser, parsed),
          sidecar = book['readingLoss'] as Json;
      final facts = objectList(
        sidecar,
        'sourceFacts',
      ).map(SourceFact.fromJson).toList();
      final instances = facts
          .where((f) => f.kind == 'document' && f.location.occurrence >= 0)
          .toList();
      expect(instances.length, parsed.content.chapters.length);
      expect(instances.map((f) => f.id).toSet().length, instances.length);
      final reps = objectList(
        sidecar,
        'representations',
      ).map(RepresentationFact.fromJson).map((r) => r.id).toSet();
      for (final row in objectList(
        sidecar,
        'correspondences',
      ).map(Correspondence.fromJson)) {
        expect(row.representationIds.every(reps.contains), true);
      }
      expect(jsonEncode(sidecar), isNot(contains('Synthetic heading')));
    },
  );
  test(
    'independent text expectations detect equal-length substitution and repeated media output',
    () {
      final bytes = auditFixture(
        body:
            '<p>ABCD😀Z</p><img src="../images/星 空.png"/><img src="../images/星 空.png"/>',
      );
      final parser = fixtureParser(bytes),
          parsed = parser.parse(),
          chapter = parsed.content.chapters.first;
      final fault = changed(
        parsed,
        chapters: [
          ChapterContent(
            key: chapter.key,
            title: chapter.title,
            blocks: [
              ParagraphBlock(text: 'ABXD😀Z'),
              ...chapter.blocks.skip(1),
              chapter.blocks.whereType<ImageBlock>().first,
            ],
          ),
          ...parsed.content.chapters.skip(1),
        ],
      );
      final audited = auditParsed(parser, fault);
      expect(
        bookCandidates(audited).any(
          (c) =>
              c.rule == 'text.simple_block_mismatch' &&
              c.status == CheckStatus.fail,
        ),
        true,
      );
      expect(
        bookCandidates(
          audited,
        ).any((c) => c.rule == 'image.unexpected_instance'),
        true,
      );
      final good = auditParsed(parser, parsed);
      final images = objectList(
        good['readingLoss'] as Json,
        'sourceFacts',
      ).map(SourceFact.fromJson).where((f) => f.kind == 'image');
      expect(images.length, 2);
      expect(images.every((f) => f.status == CheckStatus.pass), true);
    },
  );
  test('source range units and unknown enum are validated', () {
    expect(
      () =>
          AuditRange.fromJson({'start': 0, 'length': 1, 'unit': 'byte_guess'}),
      throwsFormatException,
    );
    expect(() => wireEnum(CheckStatus.values, 'green'), throwsFormatException);
    expect(
      () => SourceLocation.fromJson({
        'epubHash': 'a' * 64,
        'document': '../outside.xhtml',
        'occurrence': 0,
        'domPath': 'p[1]',
      }),
      throwsFormatException,
    );
    expect(() => ProbeConfiguration(fontSize: 13), throwsFormatException);
  });
  test('trace disabled still detects independent missing text', () {
    final bytes = auditFixture(body: '<p>Source independent.</p><p>Tail.</p>');
    final parser = fixtureParser(bytes),
        parsed = parser.parse(),
        chapter = parsed.content.chapters.first;
    final fault = changed(
      parsed,
      chapters: [
        ChapterContent(
          key: chapter.key,
          title: chapter.title,
          blocks: chapter.blocks.skip(1),
        ),
        ...parsed.content.chapters.skip(1),
      ],
    );
    expect(parser.trace, isNull);
    expect(
      bookCandidates(
        auditParsed(parser, fault),
      ).any((c) => c.status == CheckStatus.fail),
      true,
    );
  });
  test(
    'group counts deduplicate books but retain distinct instances and scoped budgets',
    () {
      final bytes = auditFixture(
        body:
            '<p style="border-radius:12px;background-color:#222;color:white">One.</p><p style="border-radius:12px;background-color:#222;color:white">Two.</p>',
      );
      final book = identified(auditBytes(bytes), bytes);
      final summary = summarizeLosses([book, book]);
      expect(summary['uniqueEpubs'], 1);
      expect(summary['candidateInstances'], greaterThan(1));
      final plan = makePlan(run(book), maxTargets: 1, maxConfigurations: 2);
      expect(plan['selectedTargets'], 1);
      expect(plan['independentShapes'], 1);
      expect((plan['notSelected'] as List).isNotEmpty, true);
      final target = VerificationTarget.fromJson(
        (plan['targets'] as List).first as Json,
      );
      expect(target.configurations, hasLength(2));
      expect(
        target.toJson()['context'],
        'complete_document_with_neighbors_and_semantic_position',
      );
      final lower = {
        ...book,
        'readingLoss': {
          ...book['readingLoss'] as Json,
          'coverage': {'factsComplete': false},
        },
      };
      expect(summarizeLosses([lower])['countAccuracy'], 'lower_bound');
    },
  );
  test(
    'rule changes cannot be reported as producer improvement; disappearing findings need positive evidence',
    () {
      final bytes = auditFixture(body: '<p>Expected.</p><p>Tail.</p>');
      final parser = fixtureParser(bytes),
          parsed = parser.parse(),
          chapter = parsed.content.chapters.first;
      final bad = identified(
        auditParsed(
          parser,
          changed(
            parsed,
            chapters: [
              ChapterContent(
                key: chapter.key,
                title: chapter.title,
                blocks: chapter.blocks.skip(1),
              ),
              ...parsed.content.chapters.skip(1),
            ],
          ),
        ),
        bytes,
      );
      final good = identified(auditParsed(parser, parsed), bytes);
      final rules = compareLossReports(run(bad), run(good, evaluator: 'e'));
      expect(
        (rules['changes'] as List).cast<Json>().any(
          (c) => c['kind'] == 'assessment_changed',
        ),
        true,
      );
      expect(
        (rules['changes'] as List).cast<Json>().any(
          (c) => c['kind'] == 'resolved_with_evidence',
        ),
        false,
      );
      final producer = compareLossReports(run(bad), run(good, producer: 'f'));
      expect(
        (producer['changes'] as List).cast<Json>().any(
          (c) => c['kind'] == 'resolved_with_evidence',
        ),
        true,
      );
      final noFacts = {
        ...good,
        'readingLoss': {
          'sourceFacts': [],
          'correspondences': [],
          'candidates': [],
        },
      };
      expect(
        (compareLossReports(run(bad), run(noFacts, producer: 'f'))['changes']
                as List)
            .cast<Json>()
            .where((c) => c['candidateId'] != null)
            .every((c) => c['kind'] == 'unknown_due_to_coverage'),
        true,
      );
    },
  );
  test('legacy schema cannot invent mappings or runtime proof', () {
    final bytes = auditFixture(), book = identified(auditBytes(bytes), bytes);
    final legacy = {
      'run': {'schemaVersion': 1, 'optionsFingerprint': 'd' * 64},
      'books': [book],
    };
    expect(compareLossReports(legacy, run(book))['comparable'], false);
  });
  test(
    'review rejects mismatched probe, retains agent decisions without runtime upgrade',
    () {
      final bytes = auditFixture(
        body: '<p style="border-radius:12px">Visible.</p>',
      );
      final book = identified(auditBytes(bytes), bytes),
          c = bookCandidates(book).first;
      final e = VerificationEvidence(
        id: 'f' * 64,
        candidateId: c.id,
        sourceId: c.sourceId,
        epubHash: c.location.epubHash,
        producer: 'a' * 64,
        probe: 'e' * 64,
        environment: 'b' * 64,
        configuration: 'd' * 64,
        provider: 'browser',
        observedPath: 'presentation',
        layers: {EvidenceLayer.browserGeometry: CheckStatus.pass},
        complete: true,
      );
      final result = reviewLosses(
        run(book),
        [e],
        manual: [
          {
            'candidateId': c.id,
            'reviewerType': 'agent',
            'kind': 'defer',
            'reason': 'manual observation',
            'producer': 'a' * 64,
            'scope': 'single_instance',
            'evidenceRefs': [c.sourceId],
          },
        ],
      );
      expect(result['verification'], isEmpty);
      expect(result['rejectedEvidence'], hasLength(1));
      expect(
        (result['manualReviews'] as List).first['affectsRuntimeStatus'],
        false,
      );
    },
  );
  test(
    'private replay preserves captured output without invoking current parser and rejects damaged bytes',
    () async {
      final root = await Directory.systemTemp.createTemp('shiori-loss-replay-');
      try {
        final snapshot = await produce(auditFixture());
        final bundle = await Directory('${root.path}/bundle').create();
        await writeBundle(snapshot, bundle);
        final replay = await readBundle(bundle.path, root.path);
        expect(
          jsonEncode(replay.modelJson()),
          jsonEncode(snapshot.modelJson()),
        );
        final before = auditParsed(snapshot.parser, snapshot.parsed),
            after = auditParsed(replay.parser, replay.parsed);
        expect(jsonEncode(after), jsonEncode(before));
        await File('${bundle.path}/source.epub').writeAsBytes([1, 2]);
        await expectLater(
          readBundle(bundle.path, root.path),
          throwsFormatException,
        );
        await expectLater(
          authorizedFile(
            '${root.parent.path}/outside.epub',
            root.path,
            maxBytes: 10,
          ),
          throwsFormatException,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('sidecar bounds leave prior checks intact', () {
    final bytes = auditFixture(body: '<p>One.</p><p>Two.</p><p>Three.</p>');
    final full = auditBytes(bytes),
        limited = auditBytes(
          bytes,
          options: const AuditOptions(maxFindings: 1),
        );
    expect(
      (limited['readingLoss'] as Json)['coverage']['factsComplete'],
      false,
    );
    expect(
      (limited['checks'] as Json)['text']['failed'],
      (full['checks'] as Json)['text']['failed'],
    );
    final sidecar = limited['readingLoss'] as Json;
    expect(
      (sidecar['representations'] as List).length,
      lessThanOrEqualTo(sidecar['coverage']['maxRepresentations']),
    );
  });
}
