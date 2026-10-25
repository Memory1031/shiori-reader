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
    Iterable<String> blockKeys = const [],
    this.maxPages = 12,
    this.timeoutSeconds = 60,
    this.maxScreenshots = 1,
    this.maxEvidenceBytes = 4 * 1024 * 1024,
  }) : configurations = List.unmodifiable(configurations),
       blockKeys = List.unmodifiable({?blockKey, ...blockKeys}) {
    if (this.configurations.isEmpty ||
        this.configurations.length > 3 ||
        this.blockKeys.length > 1024 ||
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
  final List<String> blockKeys;
  bool get documentTarget => candidate.location.domPath == 'document';
  bool get located =>
      chapterKey != null && (documentTarget || blockKeys.isNotEmpty);
  final List<ProbeConfiguration> configurations;
  final int maxPages, timeoutSeconds, maxScreenshots, maxEvidenceBytes;
  Json toJson() => {
    'candidate': candidate.toJson(),
    'chapterKey': chapterKey,
    'blockKey': blockKey,
    'blockKeys': blockKeys,
    'targetResolution': located ? 'located' : 'target_unresolved',
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
      blockKeys: j['blockKeys'] == null ? const [] : stringList(j, 'blockKeys'),
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
  final resolved = <VerificationTarget>[];
  final unresolvedReasons = <String, String>{};
  for (final candidate in all) {
    if (provider != null && !candidate.methods.contains(provider)) continue;
    if ({
      'security_boundary',
      'reader_policy',
      'source_issue',
    }.contains(candidate.classification)) {
      continue;
    }
    final book = books.firstWhere(
      (b) => b['sha256'] == candidate.location.epubHash,
    );
    final sidecar = book['readingLoss'] as Json;
    final maps = objectList(sidecar, 'correspondences')
        .map(Correspondence.fromJson)
        .where(
          (m) =>
              m.sourceId == candidate.sourceId && m.status == CheckStatus.pass,
        );
    final ids = {for (final m in maps) ...m.representationIds};
    final representations = objectList(
      sidecar,
      'representations',
    ).map(RepresentationFact.fromJson).toList();
    final matches = representations.where((r) => ids.contains(r.id)).toList()
      ..sort(
        (a, b) => ((a.metadata['blockIndex'] as int?) ?? -1).compareTo(
          (b.metadata['blockIndex'] as int?) ?? -1,
        ),
      );
    final keys = matches.map((r) => r.blockKey).whereType<String>().toSet();
    final oversized = keys.length > 1024;
    // An oversized container is unresolved, never reduced to its first child.
    final representation = oversized ? null : matches.firstOrNull;
    if (oversized) {
      unresolvedReasons[candidate.id] = 'target_scope_budget';
    }
    final path = objectList(sidecar, 'displayPaths')
        .where(
          (r) =>
              r['document'] == candidate.location.document &&
              r['occurrence'] == candidate.location.occurrence,
        )
        .firstOrNull;
    resolved.add(
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
        blockKeys: oversized ? const [] : keys,
        maxPages: maxPages,
        timeoutSeconds: timeoutSeconds,
        maxScreenshots: maxScreenshots,
      ),
    );
  }
  // Resolve first, then spread each tier across books. Unresolvable scopes
  // remain explicit, without consuming multi-configuration execution budgets.
  final bookCounts = <String, int>{};
  while (selected.length < maxTargets) {
    final remaining = resolved
        .where((t) => t.located && !groups.contains(t.candidate.groupId))
        .toList();
    if (remaining.isEmpty) break;
    remaining.sort((a, b) {
      final tier = candidateTier(
        a.candidate,
      ).compareTo(candidateTier(b.candidate));
      if (tier != 0) return tier;
      int risk(VerificationTarget t) => t.candidate.rule.startsWith('image.')
          ? 0
          : t.candidate.family == LossFamily.interaction
          ? 1
          : 2;
      final riskOrder = risk(a).compareTo(risk(b));
      if (riskOrder != 0) return riskOrder;
      final spread = (bookCounts[a.candidate.location.epubHash] ?? 0).compareTo(
        bookCounts[b.candidate.location.epubHash] ?? 0,
      );
      return spread != 0 ? spread : a.candidate.id.compareTo(b.candidate.id);
    });
    final target = remaining.first;
    selected.add(target);
    groups.add(target.candidate.groupId);
    bookCounts.update(
      target.candidate.location.epubHash,
      (n) => n + 1,
      ifAbsent: () => 1,
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
            'reason':
                unresolvedReasons[c.id] ??
                (resolved.any((t) => t.candidate.id == c.id && !t.located)
                    ? 'target_unresolved'
                    : 'representative_or_budget_limit'),
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
  final exactEvidence = <String>{};
  var duplicateEvidence = 0;
  String scope(VerificationEvidence e) => jsonEncode([
    e.candidateId,
    e.sourceId,
    e.epubHash,
    e.producer,
    e.probe,
    e.environment,
    e.configuration,
    e.provider,
  ]);
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
      final content = e.toJson()..remove('artifacts');
      if (exactEvidence.add(jsonEncode(content))) {
        accepted.add(e);
      } else {
        duplicateEvidence++;
      }
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
        .where(
          (e) =>
              e.layers.values.contains(CheckStatus.fail) &&
              !(e.assertions['clippingSourceIntent'] == 'unverified' &&
                  e.assertions['geometryFailureCauses'] is List &&
                  (e.assertions['geometryFailureCauses'] as List).length == 1 &&
                  (e.assertions['geometryFailureCauses'] as List).single ==
                      'unreachable_clipping' &&
                  e.layers.entries
                      .where((l) => l.value == CheckStatus.fail)
                      .every(
                        (l) =>
                            l.key == EvidenceLayer.browserGeometry ||
                            l.key == EvidenceLayer.nativeWebView,
                      )),
        )
        .toList();
    final measured =
        c.classification != 'insufficient_evidence' &&
        matching.any(
          (e) =>
              e.complete &&
              e.assertions['candidateFeatureStatus'] == 'pass' &&
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
      'executedEvidence': accepted.map(scope).toSet().length,
      'retainedEvidence': accepted.length,
      'duplicateEvidence': duplicateEvidence,
      'completeEvidence': accepted
          .map(scope)
          .toSet()
          .where(
            (key) =>
                accepted.where((e) => scope(e) == key).every((e) => e.complete),
          )
          .length,
      'conflictingScopes': accepted
          .map(scope)
          .toSet()
          .where((key) => accepted.where((e) => scope(e) == key).length > 1)
          .length,
      'requestedTwoColumnEvidence': accepted
          .where((e) => e.assertions['requestedColumns'] == 2)
          .map(scope)
          .toSet()
          .length,
      'observedTwoColumnEvidence': accepted
          .where(
            (e) =>
                (e.assertions['observedColumns'] as List?)?.contains(2) == true,
          )
          .map(scope)
          .toSet()
          .length,
      'notRunCandidates': candidates
          .where((c) => !accepted.any((e) => e.candidateId == c.id))
          .length,
      'wholeBookCertification': false,
    },
  };
  return report;
}
