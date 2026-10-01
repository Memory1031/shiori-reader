import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shiori/data/local/epub/epub_trace.dart';

typedef Json = Map<String, dynamic>;
const schemaVersion = 1;
const auditRulesVersion = '1.1.0';

final class AuditOptions {
  const AuditOptions({
    this.maxDocuments = 1024,
    this.maxEvents = 100000,
    this.maxFindings = 2000,
  });
  final int maxDocuments, maxEvents, maxFindings;
  Json toJson() => {
    'maxDocuments': maxDocuments,
    'maxEvents': maxEvents,
    'maxFindings': maxFindings,
    'maxSourceCharacters': 12 * 1024 * 1024,
    'maxCssCharacters': 8 * 1024 * 1024,
    'maxReportBytes': 8 * 1024 * 1024,
    'examplesPerFinding': 3,
    'presentations': true,
  };
  String get fingerprint => digest(jsonEncode(toJson()));
}

String digest(String text) => sha256.convert(utf8.encode(text)).toString();
String safeLabel(String text) => traceIdentifier(text);
String markdownEscape(Object? value) => safeLabel(
  '$value',
).replaceAllMapped(RegExp(r'[\\`*_{}\[\]()<>#!|]'), (m) => '\\${m[0]}');

final class AuditCheck {
  int checked = 0, failed = 0, unknown = 0;
  String get status => failed > 0
      ? 'fail'
      : unknown > 0
      ? 'unknown'
      : checked > 0
      ? 'pass'
      : 'not_run';
  Json toJson() => {
    'status': status,
    'checked': checked,
    'failed': failed,
    'unknown': unknown,
  };
}

final class FindingCollector {
  FindingCollector(this.limit);
  final int limit;
  final _groups = <String, Json>{};
  final _definitions = <String, Set<String>>{};
  final _documents = <String, Set<String>>{};
  bool truncated = false;
  List<Json> get findings {
    for (final entry in _groups.entries) {
      entry.value['declarationKeys'] = (_definitions[entry.key] ?? {}).toList();
      entry.value['documents'] = (_documents[entry.key] ?? {}).toList()..sort();
    }
    return _groups.values.toList();
  }

  void add(
    String rule,
    String document,
    String reason, {
    String category = 'css',
    String impact = 'layout',
    String confidence = 'suspected',
    String disposition = 'unknown',
    String evidence = 'source_only',
    String path = 'native',
    String? location,
    String? stylesheet,
    int? ruleIndex,
    int? declarationIndex,
    String? property,
    String? value,
    String? definitionKey,
    int count = 1,
    Json counts = const {},
    String? review,
  }) {
    final key = jsonEncode([
      rule,
      category == 'css' ? '*' : document,
      reason,
      property,
      disposition,
      evidence,
      path,
    ]);
    var group = _groups[key];
    if (group == null) {
      if (_groups.length >= limit) {
        truncated = true;
        return;
      }
      group = _groups[key] = {
        'stableKey': digest(
          jsonEncode([
            rule,
            category == 'css' ? '*' : document,
            reason,
            property,
          ]),
        ),
        'ruleId': rule,
        'category': category,
        'impact': impact,
        'confidence': confidence,
        'disposition': disposition,
        'evidence': evidence,
        'document': safeLabel(document),
        'property': property == null ? null : safeLabel(property),
        'reason': reason,
        'processingPath': path,
        'occurrences': 0,
        'declarations': 0,
        'countAccuracy': 'exact',
        'counts': counts,
        'countsMeaning':
            'representative_source_output_pair; occurrences_are_aggregated',
        'locations': <Json>[],
        'reviewReason': review ?? reason,
        'runtimeVerified': false,
      };
    }
    group['occurrences'] = (group['occurrences'] as int) + count;
    (_documents[key] ??= {}).add(safeLabel(document));
    if (definitionKey != null &&
        (_definitions[key] ??= {}).add(digest(definitionKey))) {
      group['declarations'] = (group['declarations'] as int) + 1;
    }
    final locations = group['locations'] as List<Json>;
    if (locations.length < 3) {
      final sample = <String, dynamic>{
        'document': safeLabel(document),
        'domPath': location,
        'stylesheet': stylesheet == null ? null : safeLabel(stylesheet),
        'ruleIndex': ruleIndex,
        'declarationIndex': declarationIndex,
        'line': null,
        'column': null,
        'value': value == null ? null : traceCssValue(value),
      };
      if (!locations.any((e) => jsonEncode(e) == jsonEncode(sample))) {
        locations.add(sample);
      }
    }
  }
}

int priorityTier(Json f) {
  if (f['confidence'] == 'confirmed' &&
      {'content_integrity', 'navigation'}.contains(f['impact']) &&
      {'unsupported', 'invalid_input', 'degraded'}.contains(f['disposition'])) {
    return 0;
  }
  if (f['confidence'] == 'confirmed' &&
      f['impact'] == 'layout' &&
      {'degraded', 'unsupported'}.contains(f['disposition'])) {
    return 1;
  }
  if (f['impact'] == 'layout' ||
      f['impact'] == 'content_integrity' ||
      f['impact'] == 'navigation') {
    return 2;
  }
  if (f['impact'] == 'decoration') return 3;
  return 4;
}

List<Json> aggregateBooks(Iterable<Json> books) {
  final observedBooks = books.toList();
  final groups = <String, Json>{};
  final docs = <String, Set<String>>{},
      hashes = <String, Set<String>>{},
      definitions = <String, Set<String>>{};
  for (final book in observedBooks) {
    final hash = book['sha256'] as String?;
    if (hash == null || book['status'] != 'parsed') continue;
    for (final f in (book['findings'] as List).cast<Json>()) {
      final key = jsonEncode([
        f['ruleId'],
        f['property'],
        f['reason'],
        f['confidence'],
        f['disposition'],
        f['evidence'],
      ]);
      final g = groups.putIfAbsent(
        key,
        () => {
          for (final field in [
            'ruleId',
            'property',
            'reason',
            'confidence',
            'disposition',
            'evidence',
            'impact',
          ])
            field: f[field],
          'priorityTier': priorityTier(f),
          'uniqueEpubs': 0,
          'documents': 0,
          'occurrences': 0,
          'declarations': 0,
          'countAccuracy': 'exact',
          'paths': <String, int>{},
          'examples': <Json>[],
        },
      );
      (hashes[key] ??= {}).add(hash);
      for (final document in (f['documents'] as List? ?? [f['document']])) {
        (docs[key] ??= {}).add('$hash:$document');
      }
      g['uniqueEpubs'] = hashes[key]!.length;
      g['documents'] = docs[key]!.length;
      g['occurrences'] = (g['occurrences'] as int) + (f['occurrences'] as int);
      // Repeated chapter uses of the same sheet declaration are counted once.
      for (final definition in (f['declarationKeys'] as List? ?? [])) {
        if ((definitions[key] ??= {}).add('$hash:$definition')) {
          g['declarations'] = (g['declarations'] as int) + 1;
        }
      }
      if (g['declarationAccuracy'] != 'lower_bound') {
        g['declarationAccuracy'] = book['auditComplete'] == true
            ? 'exact_in_observed_scope'
            : 'lower_bound';
      }
      if (book['auditComplete'] != true || f['countAccuracy'] != 'exact') {
        g['countAccuracy'] = 'lower_bound';
      }
      final paths = g['paths'] as Map<String, int>;
      paths.update(
        f['processingPath'] as String,
        (n) => n + (f['occurrences'] as int),
        ifAbsent: () => f['occurrences'] as int,
      );
      final examples = g['examples'] as List<Json>;
      if (examples.length < 3 &&
          !examples.any(
            (e) => e['sha256'] == hash && e['document'] == f['document'],
          )) {
        examples.add({
          'sha256': hash,
          'alias': (book['aliases'] as List).first,
          'document': f['document'],
          'locations': f['locations'],
        });
      }
    }
  }
  // An unseen tail can contain any rule, including one absent from the
  // truncated book's current findings. Exactness cannot be inferred per group.
  if (observedBooks.any(
    (b) => b['status'] == 'parsed' && b['auditComplete'] != true,
  )) {
    for (final group in groups.values) {
      group['countAccuracy'] = 'lower_bound';
      group['declarationAccuracy'] = 'lower_bound';
    }
  }
  return groups.values.toList()..sort((a, b) {
    var c = (a['priorityTier'] as int).compareTo(b['priorityTier'] as int);
    if (c == 0) {
      c = (b['uniqueEpubs'] as int).compareTo(a['uniqueEpubs'] as int);
    }
    if (c == 0) c = (b['documents'] as int).compareTo(a['documents'] as int);
    return c == 0 ? jsonEncode(a).compareTo(jsonEncode(b)) : c;
  });
}

String reportMarkdown(Json report) {
  final run = report['run'] as Json;
  final lines = <String>[
    '# EPUB 兼容审计',
    '',
    '报告为私人藏书信息，仅保存在本机。检查 parser 输出与有界源清单；未进行设备呈现或逐页视觉验收。',
    '',
    'schemaVersion: ${run['schemaVersion']}；auditRulesVersion: ${run['auditRulesVersion']}；parserVersion: ${run['parserVersion']}。',
    '运行完整：${run['complete']}；文件：${run['totalFiles']}；唯一 EPUB：${run['uniqueEpubs']}；重复：${run['duplicates']}；聚合完整：${run['aggregateComplete'] ?? true}。',
    '状态：`${jsonEncode(run['statuses'])}`；审计完整书数：${run['auditCompleteBooks']}。',
    '',
    '层级按确认的内容/导航问题、确认的布局降级、需复核候选、装饰、策略/覆盖信息排序。同层按唯一 EPUB 数、文档数排序。数量是本次观察范围，未知/失败不计作兼容通过。',
    '',
    '| 层级 | 规则/原因 | 属性 | 唯一 EPUB | 文档 | 实例 | 置信度 | 处理 |',
    '| --- | --- | --- | ---: | ---: | ---: | --- | --- |',
  ];
  for (final g in (report['aggregate'] as List).cast<Json>()) {
    lines.add(
      '| ${g['priorityTier']} | ${markdownEscape(g['ruleId'])} / ${markdownEscape(g['reason'])} | ${markdownEscape(g['property'] ?? '')} | ${g['uniqueEpubs']} | ${g['documents']} | ${g['occurrences']} (${g['countAccuracy']}) | ${g['confidence']} | ${g['disposition']} |',
    );
    for (final example in (g['examples'] as List).cast<Json>()) {
      lines.add(
        '代表：${markdownEscape(example['alias'])} / ${markdownEscape(example['document'])}；`${markdownEscape(jsonEncode(example['locations']))}`。',
      );
    }
  }
  lines.addAll(['', '## 逐本检查', '']);
  for (final b in (report['books'] as List).cast<Json>()) {
    lines.addAll([
      '### ${markdownEscape((b['aliases'] as List).join(' / '))}',
      '',
      '${b['status']}；审计完整：${b['auditComplete']}；hash：`${b['sha256']}`。',
      '',
      '检查：`${jsonEncode(b['checks'])}`。',
      '',
    ]);
    for (final f in (b['findings'] as List? ?? []).cast<Json>().take(12)) {
      lines.add(
        '- ${markdownEscape(f['document'])}：${markdownEscape(f['ruleId'])} / ${markdownEscape(f['reason'])}；${f['confidence']}，${f['disposition']}，${f['evidence']}。定位 `${markdownEscape(jsonEncode(f['locations']))}`。',
      );
    }
    if ((b['findings'] as List? ?? []).length > 12) {
      lines.add('- 本节只列前 12 组；完整分组与检查范围见逐本 JSON。');
    }
  }
  lines.addAll([
    '',
    '## 覆盖边界',
    '',
    '文本仅对可建立独立对应的简单段落逐块检查；Ruby、标准脚注、图片、空白和关系分别核对。复杂转换明确为 unknown。CSS 以实际 native cascade/决定和输出为证据；未知属性仅为匹配候选，不还原完整 cascade。特殊呈现只验证生成与资源，不验证浏览器 used style。未覆盖变量、伪元素生成内容、完整 SVG/CSS、字体、布局像素与分页。',
    '',
    '旧 differences / policyDifferences / presentationImageDifferences 已弃用，旧数量不与新报告比较。新报告独立 schema，JSON 是事实来源。',
  ]);
  return '${lines.join('\n')}\n';
}

Json compareReports(Json before, Json after) {
  Map<String, Json> indexed(Json book) {
    final groups = <String, List<Json>>{};
    for (final f in (book['findings'] as List? ?? []).cast<Json>()) {
      (groups[f['stableKey'] as String] ??= []).add(f);
    }
    return {
      for (final entry in groups.entries)
        entry.key: {
          ...entry.value.first,
          'occurrences': entry.value.fold<int>(
            0,
            (n, f) => n + (f['occurrences'] as int),
          ),
          'documents':
              entry.value
                  .expand((f) => (f['documents'] as List? ?? [f['document']]))
                  .toSet()
                  .toList()
                ..sort(),
          'observations':
              (entry.value
                  .map(
                    (f) => jsonEncode([
                      f['disposition'],
                      f['processingPath'],
                      f['evidence'],
                      f['confidence'],
                      f['occurrences'],
                    ]),
                  )
                  .toList()
                ..sort()),
        },
    };
  }

  final a = before['run'] as Json, b = after['run'] as Json;
  final incompatible = [
    for (final key in [
      'schemaVersion',
      'auditRulesVersion',
      'auditCodeFingerprint',
      'optionsFingerprint',
    ])
      if (a[key] != b[key]) key,
  ];
  if (incompatible.isNotEmpty) {
    return {
      'comparable': false,
      'incompatible': incompatible,
      'changes': <Json>[],
    };
  }
  final old = {
    for (final book in (before['books'] as List).cast<Json>())
      if (book['sha256'] != null) book['sha256']: book,
  };
  final changes = <Json>[];
  var matched = 0;
  for (final book in (after['books'] as List).cast<Json>()) {
    final previous = old[book['sha256']];
    if (previous == null) continue;
    matched++;
    if (previous['status'] != book['status'] ||
        previous['auditComplete'] != book['auditComplete']) {
      changes.add({
        'sha256': book['sha256'],
        'kind': 'coverage_or_status_changed',
        'before': previous['status'],
        'after': book['status'],
        'auditComplete': book['auditComplete'],
      });
    }
    final oldFindings = indexed(previous), newFindings = indexed(book);
    final oldChecks = (previous['checks'] as Json?) ?? {};
    final newChecks = (book['checks'] as Json?) ?? {};
    Json coverage(dynamic check) => {
      for (final field in ['status', 'checked', 'failed', 'unknown'])
        field: (check as Json?)?[field],
    };
    for (final key in {...oldChecks.keys, ...newChecks.keys}) {
      final oldCoverage = coverage(oldChecks[key]),
          newCoverage = coverage(newChecks[key]);
      if (jsonEncode(oldCoverage) != jsonEncode(newCoverage)) {
        changes.add({
          'sha256': book['sha256'],
          'kind': 'check_coverage_changed',
          'check': key,
          'before': oldCoverage,
          'after': newCoverage,
        });
      }
    }
    for (final key in {...oldFindings.keys, ...newFindings.keys}) {
      final x = oldFindings[key], y = newFindings[key];
      String? kind;
      if (x == null) {
        kind = 'new_observation';
      } else if (y == null) {
        final prefix = (x['ruleId'] as String).split('.').first;
        final checkKeys = switch (prefix) {
          'text' => ['text'],
          'whitespace' => ['whitespace'],
          'ruby' => ['ruby'],
          'footnote' => ['footnotes'],
          'document' => ['documents'],
          _ => switch (x['category']) {
            'content' => ['text', 'ruby', 'footnotes'],
            'media' => ['images'],
            'navigation' => ['navigation', 'links'],
            'coverage' => ['documents'],
            'structure' => ['structures'],
            _ => [x['category']],
          },
        };
        final checks = (book['checks'] as Json?) ?? {};
        final checked = checkKeys.every((key) {
          final check = checks[key] as Json?;
          return check != null &&
              {'pass', 'fail'}.contains(check['status']) &&
              check['unknown'] == 0 &&
              check['checked'] is int &&
              (check['checked'] as int) > 0 &&
              check['failed'] is int;
        });
        kind =
            book['auditComplete'] == true &&
                book['status'] == 'parsed' &&
                checked
            ? 'no_longer_observed'
            : 'unknown_due_to_coverage';
      } else if (jsonEncode(x['observations']) !=
              jsonEncode(y['observations']) ||
          x['occurrences'] != y['occurrences'] ||
          x['processingPath'] != y['processingPath'] ||
          x['disposition'] != y['disposition'] ||
          jsonEncode(x['documents']) != jsonEncode(y['documents'])) {
        kind = 'observation_changed';
      }
      if (kind != null) {
        changes.add({
          'sha256': book['sha256'],
          'kind': kind,
          'ruleId': (x ?? y)!['ruleId'],
          'document': (x ?? y)!['document'],
          'stableKey': key,
          'beforeCount': x?['occurrences'],
          'afterCount': y?['occurrences'],
        });
      }
    }
  }
  return {
    'comparable': true,
    'matchedBooks': matched,
    'unmatchedBefore': old.length - matched,
    'unmatchedAfter': (after['books'] as List).length - matched,
    'changes': changes,
    'interpretation':
        'Observations only; disappearance is not a claim of a runtime fix.',
  };
}
