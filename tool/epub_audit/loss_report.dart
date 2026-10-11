import 'dart:convert';
import 'loss_model.dart';
import 'report.dart';

Iterable<LossCandidate> bookCandidates(Json book) =>
    ((book['readingLoss'] as Json?)?['candidates'] as List? ?? [])
        .cast<Json>()
        .map(LossCandidate.fromJson);

int candidateTier(LossCandidate c) => switch (c.classification) {
  'confirmed_loss' => 0,
  'suspected_high_impact' => 1,
  'representation_change_impact_unverified' => 2,
  'insufficient_evidence' => 3,
  _ => 4,
};

Json summarizeLosses(Iterable<Json> books) {
  final groups = <String, Json>{};
  final hashes = <String>{};
  final documents = <String>{};
  final instances = <String>{};
  var lowerBound = false;
  for (final book in books) {
    final hash = book['sha256'] as String?;
    if (hash == null || !hashes.add(hash)) continue;
    lowerBound |=
        book['auditComplete'] != true ||
        book['status'] == 'parsed' && book['readingLoss'] == null ||
        ((book['readingLoss'] as Json?)?['coverage']
                as Json?)?['factsComplete'] ==
            false;
    for (final c in bookCandidates(book)) {
      final doc = '$hash:${c.location.document}:${c.location.occurrence}';
      documents.add(doc);
      if (!instances.add(c.id)) continue;
      if (!groups.containsKey(c.groupId) && groups.length >= 10000) {
        lowerBound = true;
        continue;
      }
      final group = groups.putIfAbsent(
        c.groupId,
        () => {
          'groupId': c.groupId,
          'family': wireName(c.family),
          'rule': c.rule,
          'reason': c.reason,
          'tier': candidateTier(c),
          'classification': c.classification,
          'impact': c.impact,
          'predictedPath': c.predictedPath,
          'epubHashes': <String>[],
          'documents': <String>[],
          'candidateIds': <String>[],
          'examples': <Json>[],
          'countAccuracy': 'observed_instances',
        },
      );
      if (!(group['epubHashes'] as List).contains(hash)) {
        (group['epubHashes'] as List).add(hash);
      }
      if (!(group['documents'] as List).contains(doc)) {
        (group['documents'] as List).add(doc);
      }
      (group['candidateIds'] as List).add(c.id);
      if ((group['examples'] as List).length < 3) {
        (group['examples'] as List).add({
          'candidateId': c.id,
          'location': c.location.toJson(),
        });
      }
      if (c.countAccuracy != 'exact') group['countAccuracy'] = 'lower_bound';
    }
  }
  final rows = groups.values.toList()
    ..sort((a, b) {
      var n = (a['tier'] as int).compareTo(b['tier'] as int);
      if (n == 0) {
        n = (b['epubHashes'] as List).length.compareTo(
          (a['epubHashes'] as List).length,
        );
      }
      return n == 0
          ? (a['groupId'] as String).compareTo(b['groupId'] as String)
          : n;
    });
  if (lowerBound) {
    for (final row in rows) {
      row['countAccuracy'] = 'lower_bound';
    }
  }
  return {
    'uniqueEpubs': hashes.length,
    'documents': documents.length,
    'candidateInstances': instances.length,
    'independentShapes': rows.length,
    'countAccuracy': lowerBound ? 'lower_bound' : 'bounded_observed_scope',
    'groups': rows,
    'wholeBookCertification': false,
  };
}

String lossMarkdown(Json report) {
  final run = report['run'] as Json;
  final summary =
      report['lossSummary'] as Json? ??
      summarizeLosses((report['books'] as List).cast<Json>());
  final lines = <String>[
    '# EPUB 阅读损失审计',
    '',
    '静态事实、候选、运行证据与开发判断分别记录。范围完整不代表全书兼容。普通报告不含正文；private bundle 和截图含私人材料。',
    '',
    'schema ${run['schemaVersion']}；rules ${run['auditRulesVersion']}；parser ${run['parserVersion']}。',
    '输入 ${run['totalFiles'] ?? 0}；唯一 EPUB ${run['uniqueEpubs'] ?? summary['uniqueEpubs']}；扫描完成 ${run['complete']}；规则覆盖 ${run['aggregateComplete'] ?? true}。',
    '状态：${markdownEscape(jsonEncode(run['statuses'] ?? {}))}。',
    '',
    '## 已确认用户影响',
    '',
    '内容／导航的静态合同矛盾可确认；装饰／结构处理事实需结合真实页面验证。原生播放解码、设备 WebView 与 widget 测量分别计证据，不相互升格。',
    '',
    '## 最值得验证的独立结构',
    '',
    '独立形状 ${summary['independentShapes']}；候选实例 ${summary['candidateInstances']}；文档 occurrence ${summary['documents']}；精度 ${summary['countAccuracy']}。',
    '',
    '| 分档 | 形状与处理 | 书籍 | 实例 | 定位 |',
    '| --- | --- | ---: | ---: | --- |',
  ];
  for (final row in (summary['groups'] as List).cast<Json>().take(5)) {
    final example = (row['examples'] as List).first as Json;
    final loc = SourceLocation.fromJson(example['location'] as Json);
    lines.add(
      '| ${row['tier']} | ${markdownEscape(row['rule'])} / ${markdownEscape(row['reason'])} | ${(row['epubHashes'] as List).length} | ${(row['candidateIds'] as List).length} | ${markdownEscape(loc.document)} occurrence ${loc.occurrence} ${markdownEscape(loc.domPath)} |',
    );
  }
  lines.addAll(['', '## 开发判断', '']);
  final decisions = (report['decisions'] as List? ?? []).cast<Json>();
  if (decisions.isEmpty) {
    lines.add('尚未汇总运行证据；当前候选进入验证队列，不按警告数量生成开发计划。使用 plan → verify → review。');
  } else {
    for (final decision in decisions.take(5)) {
      lines.add(
        '- ${markdownEscape(decision['kind'])}：${markdownEscape(decision['reason'])}；候选 `${decision['candidateId']}`。',
      );
    }
  }
  lines.addAll([
    '',
    '## 代表页面与证据入口',
    '',
    '逐本事实：[books.jsonl](books.jsonl)；完整机器结果：[report.json](report.json)。',
    if (report['evidenceIndex'] is String)
      '独立验证：[verification.json](<${Uri.encodeFull(report['evidenceIndex'] as String).replaceAll('<', '%3C').replaceAll('>', '%3E')}>)。',
    '未选中和预算未覆盖项保持 not_run，不计入成功分母。运行证据只适用于该源实例、producer、probe 和环境。',
    '',
    '## 版本比较',
    '',
    'producer／evaluator／probe／environment 分别核对。同 producer 的规则变化是 assessment_changed；旧候选消失只有具备同实例正向证据才可记 resolved_with_evidence。',
    '',
    '## 覆盖与原始观察',
    '',
    '有效 CSS 依赖 production_native_cascade，未冒充独立浏览器 computed style。复杂转换、字体字形归属、透明／图片背景保持局部 unknown。',
    '原有检查及 observations 保存在逐本 JSON；schema1 可读为 legacy，缺少关联或运行证据时不可补造。',
    '',
  ]);
  return '${lines.join('\n')}\n';
}

Json compareLossReports(Json before, Json after) {
  final a = before['run'] as Json, b = after['run'] as Json;
  final oldBooks = {
    for (final book in (before['books'] as List).cast<Json>())
      if (book['sha256'] != null) book['sha256'] as String: book,
  };
  final newBooks = {
    for (final book in (after['books'] as List).cast<Json>())
      if (book['sha256'] != null) book['sha256'] as String: book,
  };
  String? identity(Json run, String name) =>
      (run[name] as Json?)?['fingerprint'] as String?;
  final sameProducer =
      identity(a, 'producer') != null &&
      identity(a, 'producer') == identity(b, 'producer');
  final sameEvaluator =
      identity(a, 'evaluator') != null &&
      identity(a, 'evaluator') == identity(b, 'evaluator');
  final compatibleSchema = a['schemaVersion'] == 2 && b['schemaVersion'] == 2;
  final sameOptions = a['optionsFingerprint'] == b['optionsFingerprint'];
  final incompatible = <String>[
    if (!compatibleSchema) 'schema_requires_rescan_or_replay',
    if (!sameOptions) 'options',
    if (!sameProducer && !sameEvaluator) 'producer_and_evaluator_changed',
  ];
  final comparable =
      compatibleSchema && sameOptions && (sameProducer || sameEvaluator);
  final changes = <Json>[];
  var matched = 0;
  for (final hash in {...oldBooks.keys, ...newBooks.keys}) {
    final x = oldBooks[hash], y = newBooks[hash];
    if (x == null || y == null) {
      changes.add({
        'epubHash': hash,
        'kind': 'coverage_changed',
        'reason': 'input_scope_changed',
      });
      continue;
    }
    matched++;
    if (x['auditComplete'] != y['auditComplete'] ||
        x['status'] != y['status'] ||
        jsonEncode(x['checks']) != jsonEncode(y['checks'])) {
      changes.add({
        'epubHash': hash,
        'kind': 'coverage_changed',
        'before': x['checks'],
        'after': y['checks'],
      });
    }
    if (!comparable) {
      changes.add({
        'epubHash': hash,
        'kind': 'not_comparable',
        'reason': incompatible,
      });
      continue;
    }
    final old = {for (final c in bookCandidates(x)) c.id: c};
    final current = {for (final c in bookCandidates(y)) c.id: c};
    final facts = {
      for (final f
          in (((y['readingLoss'] as Json?)?['sourceFacts'] as List?) ?? [])
              .cast<Json>()
              .map(SourceFact.fromJson))
        f.id: f,
    };
    final mappings =
        (((y['readingLoss'] as Json?)?['correspondences'] as List?) ?? [])
            .cast<Json>()
            .map(Correspondence.fromJson)
            .toList();
    final oldSignatures = representationSignatures(x),
        newSignatures = representationSignatures(y);
    final candidateSources = {
      ...old.values.map((c) => c.sourceId),
      ...current.values.map((c) => c.sourceId),
    };
    for (final sourceId in {...oldSignatures.keys, ...newSignatures.keys}) {
      if (candidateSources.contains(sourceId) ||
          oldSignatures[sourceId] == newSignatures[sourceId]) {
        continue;
      }
      changes.add({
        'epubHash': hash,
        'sourceId': sourceId,
        'kind': !sameEvaluator
            ? 'assessment_changed'
            : oldSignatures[sourceId] == null || newSignatures[sourceId] == null
            ? 'unknown_due_to_coverage'
            : 'representation_changed',
        'dimension': 'mapped_output',
        'beforeHash': oldSignatures[sourceId],
        'afterHash': newSignatures[sourceId],
      });
    }
    for (final id in {...old.keys, ...current.keys}) {
      final left = old[id], right = current[id];
      if (left != null &&
          right != null &&
          jsonEncode(left.toJson()) == jsonEncode(right.toJson())) {
        continue;
      }
      String kind;
      final refs = <String>[];
      if (!sameEvaluator) {
        kind = 'assessment_changed';
      } else if (left == null) {
        kind = right!.status == CheckStatus.fail
            ? 'new_loss'
            : 'representation_changed';
      } else if (right == null) {
        final fact = facts[left.sourceId];
        final positive =
            fact != null &&
            fact.status == CheckStatus.pass &&
            mappings.any(
              (m) =>
                  m.sourceId == left.sourceId &&
                  m.status == CheckStatus.pass &&
                  m.representationIds.isNotEmpty,
            ) &&
            y['auditComplete'] == true &&
            y['status'] == 'parsed';
        kind = positive && left.status == CheckStatus.fail
            ? 'resolved_with_evidence'
            : 'unknown_due_to_coverage';
        if (positive) refs.add(fact.id);
      } else {
        kind = 'representation_changed';
      }
      changes.add({
        'epubHash': hash,
        'candidateId': id,
        'sourceId': (left ?? right)!.sourceId,
        'kind': kind,
        'beforeStatus': left == null ? null : wireName(left.status),
        'afterStatus': right == null ? null : wireName(right.status),
        'evidenceRefs': refs,
      });
    }
  }
  final oldEvidence = {
    for (final row in ((before['verification'] as List?) ?? []).cast<Json>())
      '${row['candidateId']}:${row['configuration']}:${row['provider']}':
          VerificationEvidence.fromJson(row),
  };
  for (final row in ((after['verification'] as List?) ?? []).cast<Json>()) {
    final right = VerificationEvidence.fromJson(row);
    final left =
        oldEvidence['${right.candidateId}:${right.configuration}:${right.provider}'];
    if (left == null) continue;
    if (left.probe != right.probe || left.environment != right.environment) {
      changes.add({
        'candidateId': right.candidateId,
        'dimension': 'runtime',
        'kind': 'not_comparable',
        'reason': 'probe_or_environment_changed',
      });
      continue;
    }
    for (final layer in EvidenceLayer.values) {
      if (left.layers[layer] == right.layers[layer]) continue;
      changes.add({
        'candidateId': right.candidateId,
        'dimension': wireName(layer),
        'kind': !sameEvaluator
            ? 'assessment_changed'
            : right.layers[layer] == CheckStatus.fail
            ? 'new_loss'
            : left.layers[layer] == CheckStatus.fail &&
                  right.layers[layer] == CheckStatus.pass &&
                  right.complete &&
                  right.assertions['candidateFeatureStatus'] != 'unknown' &&
                  right.assertions['targetVisible'] == true
            ? 'resolved_with_evidence'
            : 'unknown_due_to_coverage',
        'evidenceRefs': [left.id, right.id],
      });
    }
  }
  return {
    'schemaVersion': 2,
    'comparable': comparable,
    'incompatible': incompatible,
    'mode': sameProducer
        ? sameEvaluator
              ? 'same_producer_evaluator'
              : 'evaluator_change'
        : 'producer_change',
    'sameProducer': sameProducer,
    'sameEvaluator': sameEvaluator,
    'matchedBooks': matched,
    'unmatchedBefore': oldBooks.length - matched,
    'unmatchedAfter': newBooks.length - matched,
    'rendererComparison':
        'Runtime dimensions require identical probe/environment; replay by current renderer is not old renderer execution.',
    'recoveryCommands': !compatibleSchema
        ? [
            'fvm dart run tool/epub_compatibility_audit.dart scan --paths EXPLICIT_PATHS_JSON --out NEW_RUN',
            'fvm dart run tool/epub_compatibility_audit.dart evaluate --bundle EXPLICIT_PRIVATE_BUNDLE --allow-root ALLOWED_ROOT --out NEW_RUN',
          ]
        : [],
    'changes': changes,
    'interpretation':
        'No compatibility percentage. Positive evidence is instance-specific.',
  };
}

Map<String, String> representationSignatures(Json book) {
  final sidecar = book['readingLoss'] as Json?;
  if (sidecar == null || sidecar['representations'] == null) return {};
  final reps = {
    for (final r in objectList(
      sidecar,
      'representations',
    ).map(RepresentationFact.fromJson))
      r.id: r,
  };
  final result = <String, List<Object>>{};
  for (final mapping in objectList(
    sidecar,
    'correspondences',
  ).map(Correspondence.fromJson)) {
    for (final id in mapping.representationIds) {
      final rep = reps[id];
      if (rep == null) continue;
      (result[mapping.sourceId] ??= []).add([
        rep.path,
        rep.kind,
        rep.textHash,
        rep.range?.toJson(),
        rep.resources,
        rep.metadata,
        wireName(mapping.status),
        mapping.transformation,
      ]);
    }
  }
  return {
    for (final entry in result.entries)
      entry.key: digest(jsonEncode(entry.value)),
  };
}
