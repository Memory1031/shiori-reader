import 'dart:convert';
import 'loss_model.dart';
import 'loss_report.dart';
import 'report.dart';

final class ProbeConfiguration {
  ProbeConfiguration({
    this.width = 400,
    this.height = 700,
    this.fontSize = 20,
    this.columns = 1,
    this.theme = 'light',
    this.language = 'en',
  }) {
    if (width < 240 ||
        width > 1920 ||
        height < 300 ||
        height > 1600 ||
        fontSize < 14 ||
        fontSize > 32 ||
        ![1, 2].contains(columns) ||
        !['light', 'dark'].contains(theme) ||
        !['en', 'zh'].contains(language)) {
      throw const FormatException('Unsupported probe configuration');
    }
  }
  final int width, height, fontSize, columns;
  final String theme, language;
  Json toJson() => {
    'width': width,
    'height': height,
    'fontSize': fontSize,
    'columns': columns,
    'theme': theme,
    'language': language,
    'textScale': 1,
    'devicePixelRatio': 1,
  };
  String get fingerprint => digest(jsonEncode(toJson()));
  factory ProbeConfiguration.fromJson(Json j) => ProbeConfiguration(
    width: intField(j, 'width', max: 1920),
    height: intField(j, 'height', max: 1600),
    fontSize: intField(j, 'fontSize', max: 40),
    columns: intField(j, 'columns', max: 2),
    theme: stringField(j, 'theme'),
    language: stringField(j, 'language'),
  );
}

final class VerificationTarget {
  VerificationTarget(
    this.candidate,
    this.chapterKey,
    this.blockKey,
    Iterable<ProbeConfiguration> configurations, {
    this.maxPages = 12,
    this.timeoutSeconds = 60,
    this.maxScreenshots = 1,
    this.maxEvidenceBytes = 4 * 1024 * 1024,
  }) : configurations = List.unmodifiable(configurations) {
    if (this.configurations.isEmpty ||
        this.configurations.length > 3 ||
        maxPages < 1 ||
        maxPages > 64 ||
        timeoutSeconds < 1 ||
        timeoutSeconds > 300 ||
        maxScreenshots < 0 ||
        maxScreenshots > 3 ||
        maxEvidenceBytes < 1024 ||
        maxEvidenceBytes > 8 * 1024 * 1024) {
      throw const FormatException('Target budget');
    }
  }
  final LossCandidate candidate;
  final Json? chapterKey;
  final String? blockKey;
  final List<ProbeConfiguration> configurations;
  final int maxPages, timeoutSeconds, maxScreenshots, maxEvidenceBytes;
  Json toJson() => {
    'candidate': candidate.toJson(),
    'chapterKey': chapterKey,
    'blockKey': blockKey,
    'semanticUnit': 'unicode_code_point',
    'question': candidate.family == LossFamily.content
        ? 'Is the expected source instance reachable and visible?'
        : candidate.family == LossFamily.interaction
        ? 'Does actual input reach the declared target exactly once?'
        : 'Does the representation change affect geometry, readability or authored grouping?',
    'renderer': candidate.methods.first,
    'configurations': configurations.map((c) => c.toJson()).toList(),
    'context': 'complete_document_with_neighbors_and_semantic_position',
    'budget': {
      'maxPages': maxPages,
      'timeoutSeconds': timeoutSeconds,
      'maxScreenshots': maxScreenshots,
      'maxEvidenceBytes': maxEvidenceBytes,
      'maxEncodedResourcesBytes': 128 * 1024 * 1024,
      'maxModelBytes': 32 * 1024 * 1024,
    },
    'canConclude': ['observed_scope_only', 'instance_specific'],
    'cannotConclude': [
      'whole_book_correct',
      'device_runtime_from_widget',
      'audio_output_from_fake',
    ],
  };
  factory VerificationTarget.fromJson(Json j) {
    final budget = j['budget'] as Json;
    return VerificationTarget(
      LossCandidate.fromJson(j['candidate'] as Json),
      j['chapterKey'] as Json?,
      j['blockKey'] as String?,
      objectList(j, 'configurations', max: 3).map(ProbeConfiguration.fromJson),
      maxPages: intField(budget, 'maxPages', max: 64),
      timeoutSeconds: intField(budget, 'timeoutSeconds', max: 300),
      maxScreenshots: intField(budget, 'maxScreenshots', max: 3),
      maxEvidenceBytes: intField(
        budget,
        'maxEvidenceBytes',
        max: 8 * 1024 * 1024,
      ),
    );
  }
}

Json makePlan(
  Json report, {
  int maxTargets = 12,
  int maxConfigurations = 3,
  int maxPages = 12,
  int timeoutSeconds = 60,
  int maxScreenshots = 1,
  String? provider,
}) {
  final run = report['run'] as Json;
  if (run['schemaVersion'] != 2 ||
      run['producer'] == null ||
      run['evaluator'] == null ||
      maxTargets < 1 ||
      maxTargets > 12 ||
      maxConfigurations < 1 ||
      maxConfigurations > 3) {
    throw const FormatException('Legacy scan or plan budget');
  }
  if (provider != null &&
      !{'native', 'browser', 'webview'}.contains(provider)) {
    throw const FormatException('Unknown planned provider');
  }
  final books = (report['books'] as List).cast<Json>();
  final all = [for (final book in books) ...bookCandidates(book)];
  all.sort((a, b) {
    final n = candidateTier(a).compareTo(candidateTier(b));
    return n == 0 ? a.id.compareTo(b.id) : n;
  });
  final selected = <VerificationTarget>[];
  final groups = <String>{};
  for (final candidate in all) {
    if (provider != null && !candidate.methods.contains(provider)) continue;
    if ({
          'security_boundary',
          'reader_policy',
          'source_issue',
        }.contains(candidate.classification) ||
        groups.contains(candidate.groupId)) {
      continue;
    }
    if (selected.length >= maxTargets) break;
    groups.add(candidate.groupId);
    final book = books.firstWhere(
      (b) => b['sha256'] == candidate.location.epubHash,
    );
    final sidecar = book['readingLoss'] as Json;
    final map = objectList(sidecar, 'correspondences')
        .map(Correspondence.fromJson)
        .where((m) => m.sourceId == candidate.sourceId)
        .firstOrNull;
    final representations = objectList(
      sidecar,
      'representations',
    ).map(RepresentationFact.fromJson).toList();
    final representation = representations
        .where((r) => map?.representationIds.contains(r.id) == true)
        .firstOrNull;
    final path = objectList(sidecar, 'displayPaths')
        .where(
          (r) =>
              r['document'] == candidate.location.document &&
              r['occurrence'] == candidate.location.occurrence,
        )
        .firstOrNull;
    selected.add(
      VerificationTarget(
        candidate,
        representation?.chapterKey ?? path?['chapterKey'] as Json?,
        representation?.blockKey,
        [
          ProbeConfiguration(),
          if (maxConfigurations > 1)
            ProbeConfiguration(width: 320, fontSize: 28, theme: 'dark'),
          if (maxConfigurations > 2)
            ProbeConfiguration(width: 1200, height: 800, columns: 2),
        ],
        maxPages: maxPages,
        timeoutSeconds: timeoutSeconds,
        maxScreenshots: maxScreenshots,
      ),
    );
  }
  return {
    'schemaVersion': 2,
    'kind': 'verification_plan',
    'plannedProvider': provider,
    'producer': run['producer'],
    'evaluator': run['evaluator'],
    'optionsFingerprint': run['optionsFingerprint'],
    'scanComplete': run['complete'],
    'candidateCount': all.length,
    'selectedTargets': selected.length,
    'independentShapes': groups.length,
    'notSelected': all
        .where((c) => !selected.any((t) => t.candidate.id == c.id))
        .map(
          (c) => {
            'candidateId': c.id,
            'status': 'not_run',
            'reason': 'representative_or_budget_limit',
          },
        )
        .toList(),
    'budget': {
      'maxTargets': maxTargets,
      'maxConfigurations': maxConfigurations,
      'maxEvidenceBytes': 64 * 1024 * 1024,
      'maxPrivateReplayCacheBytes': 768 * 1024 * 1024,
      'defaultSoundOutput': false,
    },
    'targets': selected.map((t) => t.toJson()).toList(),
  };
}

Json reviewLosses(
  Json scan,
  Iterable<VerificationEvidence> evidence, {
  List<Json> manual = const [],
}) {
  final run = scan['run'] as Json;
  final producer = hashField(run['producer'] as Json, 'fingerprint');
  final accepted = <VerificationEvidence>[];
  final rejected = <Json>[];
  final candidates = [
    for (final b in (scan['books'] as List).cast<Json>()) ...bookCandidates(b),
  ];
  final decisions = <ReviewDecision>[];
  for (final e in evidence) {
    final candidate = candidates
        .where((c) => c.id == e.candidateId)
        .firstOrNull;
    if (candidate == null ||
        e.producer != producer ||
        e.sourceId != candidate.sourceId ||
        e.epubHash != candidate.location.epubHash ||
        e.probe != (run['probe'] as Json?)?['fingerprint']) {
      rejected.add({
        'evidenceId': e.id,
        'reason': 'identity_or_scope_mismatch',
      });
    } else {
      accepted.add(e);
    }
  }
  final sorted = [...candidates]
    ..sort((a, b) {
      final n = candidateTier(a).compareTo(candidateTier(b));
      return n == 0 ? a.id.compareTo(b.id) : n;
    });
  for (final c in sorted) {
    final matching = accepted.where((e) => e.candidateId == c.id).toList();
    final failed = matching
        .where((e) => e.layers.values.contains(CheckStatus.fail))
        .toList();
    final measured =
        c.classification != 'insufficient_evidence' &&
        matching.any(
          (e) =>
              e.complete &&
              (e.assertions['targetVisible'] == true ||
                  e.observedPath == 'presentation' &&
                      e.assertions['truncated'] == false) &&
              [
                EvidenceLayer.widgetGeometry,
                EvidenceLayer.browserGeometry,
                EvidenceLayer.nativeWebView,
              ].any((layer) => e.layers[layer] == CheckStatus.pass),
        );
    final kind = switch (c.classification) {
      'reader_policy' || 'security_boundary' => DecisionKind.acceptedPolicy,
      'source_issue' => DecisionKind.sourceIssue,
      'confirmed_loss' => DecisionKind.recommendFix,
      _ =>
        failed.isNotEmpty
            ? DecisionKind.recommendFix
            : measured
            ? DecisionKind.defer
            : c.classification == 'insufficient_evidence'
            ? DecisionKind.insufficientEvidence
            : DecisionKind.verifyNext,
    };
    final reason = switch (kind) {
      DecisionKind.recommendFix =>
        failed.isEmpty
            ? 'independent_content_or_navigation_contract_failed; root_cause_not_assumed'
            : 'executed_probe_assertion_failed; inspect_evidence_before_implementation',
      DecisionKind.acceptedPolicy =>
        'explicit_reader_policy_or_security_boundary; do_not_restore_unsafe_content',
      DecisionKind.sourceIssue =>
        'source_reference_or_resource_problem; do_not_guess_destination_from_title',
      DecisionKind.defer =>
        'observed_representation_remains_readable_in_this_configuration; group_not_certified',
      DecisionKind.insufficientEvidence =>
        'source_effectiveness_or_correspondence_unresolved',
      DecisionKind.verifyNext =>
        'representation_change_confirmed_or_suspected; user_impact_not_measured',
    };
    decisions.add(
      ReviewDecision(
        c.id,
        kind,
        reason,
        [c.sourceId, ...matching.map((e) => e.id)],
        producer: producer,
        environment: matching.firstOrNull?.environment,
      ),
    );
  }
  final manualRows = <Json>[];
  if (manual.length > 2000) throw const FormatException('Manual review budget');
  for (final row in manual) {
    final id = hashField(row, 'candidateId');
    final type = stringField(row, 'reviewerType');
    if (!['human', 'agent'].contains(type) ||
        !candidates.any((c) => c.id == id) ||
        row['producer'] != producer) {
      throw const FormatException('Manual review scope');
    }
    wireEnum(DecisionKind.values, row['kind']);
    manualRows.add({
      'candidateId': id,
      'reviewerType': type,
      'kind': row['kind'],
      'reason': stringField(row, 'reason', limit: 1024),
      'producer': producer,
      'scope': stringField(row, 'scope'),
      'evidenceRefs': stringList(row, 'evidenceRefs'),
      'affectsRuntimeStatus': false,
    });
  }
  final report = <String, dynamic>{
    ...scan,
    'kind': 'reading_loss_review',
    'lossSummary': summarizeLosses((scan['books'] as List).cast<Json>()),
    'verification': accepted.map((e) => e.toJson()).toList(),
    'rejectedEvidence': rejected,
    'manualReviews': manualRows,
    'decisions': decisions.map((d) => d.toJson()).toList(),
    'recommendations': decisions
        .where((d) => d.kind == DecisionKind.recommendFix)
        .take(5)
        .map((d) => d.toJson())
        .toList(),
    'runtimeCoverage': {
      'executedEvidence': accepted.length,
      'completeEvidence': accepted.where((e) => e.complete).length,
      'notRunCandidates': candidates
          .where((c) => !accepted.any((e) => e.candidateId == c.id))
          .length,
      'wholeBookCertification': false,
    },
  };
  return report;
}
