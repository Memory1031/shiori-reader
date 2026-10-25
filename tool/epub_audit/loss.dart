import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:shiori/data/local/epub/epub_trace.dart';
import 'package:shiori/domain/models/models.dart';
import 'loss_model.dart';
import 'report.dart';

String auditBlockText(ContentBlock b) => switch (b) {
  ParagraphBlock(:final text) || HeadingBlock(:final text) => text,
  _ => '',
};

/// A read-only, bounded sidecar. Neither identity nor resources are added to
/// persisted blocks. Reliable expectations come from the existing independent
/// source checks, never from emitted trace events.
final class ReadingLossCollector {
  ReadingLossCollector(this.epubHash, this.limit, {this.privateExpected});
  final String epubHash;
  final int limit;
  final Map<String, String>? privateExpected;
  final facts = <SourceFact>[],
      representations = <RepresentationFact>[],
      relations = <Correspondence>[],
      candidates = <LossCandidate>[];
  final paths = <Json>[];
  final _nodes = <String, dom.Element>{};
  final _styles = <String, Map<String, String>>{};
  final _sourceIds = <String>{}, _candidateIds = <String>{};
  final _blockIds = <String, String>{};
  final _media = <(String, String, int, String), List<String>>{};
  final _consumed = <(String, String, int, String), int>{};
  final _current = <String, (int, ChapterContent?, String)>{};
  final _contexts = <String, List<(int, ChapterContent?, String)>>{};
  bool truncated = false;
  bool representationTruncated = false;

  SourceLocation location(String path, String domPath) =>
      SourceLocation(epubHash, path, _current[path]?.$1 ?? -1, domPath);
  String shape(dom.Element? node, Map<String, String>? style) {
    var remaining = 64;
    Object tree(dom.Element n, int depth) => [
      n.localName,
      for (final k in ['colspan', 'rowspan', 'controls'])
        if (n.attributes.containsKey(k))
          [k, k == 'controls' ? true : int.tryParse(n.attributes[k]!)],
      if (depth < 4)
        for (final c in n.children)
          if (--remaining >= 0) tree(c, depth + 1),
    ];
    final keys =
        (style?.keys ?? <String>[])
            .where(
              (k) => {
                'display',
                'position',
                'writing-mode',
                'color',
                'background-color',
                'border-style',
                'border-radius',
                'width',
                'padding',
                'line-height',
                'vertical-align',
                'white-space',
                'text-align',
              }.contains(k),
            )
            .toList()
          ..sort();
    return digest(
      jsonEncode([
        node == null ? null : tree(node, 0),
        for (final k in keys) [k, traceCssValue(style![k]!)],
      ]),
    );
  }

  SourceFact? fact(
    String path,
    dom.Element? node,
    String kind,
    CheckStatus status, {
    String? text,
    Json details = const {},
    bool effective = true,
    String method = 'independent_source_subset',
    Iterable<String> uncertainties = const [],
  }) {
    final loc = location(
      path,
      node == null ? 'document' : epubTraceLocation(node),
    );
    final id = digest(jsonEncode([loc.identity, kind]));
    if (_sourceIds.contains(id)) return facts.where((f) => f.id == id).first;
    if (facts.length >= limit) {
      truncated = true;
      if (status != CheckStatus.fail) return null;
      final removable =
          facts.where((f) => f.status == CheckStatus.unknown).firstOrNull ??
          facts.where((f) => f.status == CheckStatus.pass).lastOrNull;
      if (removable == null) return null;
      facts.remove(removable);
      _sourceIds.remove(removable.id);
      privateExpected?.remove(removable.id);
      relations.removeWhere((r) => r.sourceId == removable.id);
      final removed = candidates
          .where((c) => c.sourceId == removable.id)
          .toList();
      for (final c in removed) {
        _candidateIds.remove(c.id);
        candidates.remove(c);
      }
    }
    _sourceIds.add(id);
    final result = SourceFact(
      id: id,
      location: loc,
      kind: kind,
      method: method,
      effective: effective,
      status: status,
      shape: kind != 'image'
          ? shape(node, _styles['$path:${loc.domPath}'])
          : digest(
              jsonEncode([
                shape(node, _styles['$path:${loc.domPath}']),
                if (kind == 'image') details['aspectClass'],
              ]),
            ),
      textHash: text == null ? null : digest(text),
      range: text == null
          ? null
          : AuditRange(0, text.runes.length, 'unicode_code_point'),
      details: details,
      dependencies: const [
        'production_native_cascade',
        'shared_zip_safety',
        'shared_reference_format',
      ],
      uncertainties: uncertainties,
    );
    facts.add(result);
    if (text != null) privateExpected?[id] = text;
    return result;
  }

  void relate(
    SourceFact? source,
    List<String> ids,
    CheckStatus status,
    String transformation, {
    String reason = 'independent_instance_match',
  }) {
    if (source == null) return;
    if (relations.length >= limit * 2) {
      truncated = true;
      return;
    }
    relations.add(
      Correspondence(source.id, ids, status, transformation, reason: reason),
    );
  }

  void document(
    String path,
    int occurrence,
    dom.Document doc,
    Map<dom.Element, Map<String, String>> styles,
    ChapterContent? chapter,
    String? presentation,
    bool Function(dom.Element) hidden, {
    required bool spine,
  }) {
    final predicted = chapter == null
        ? 'unrepresented'
        : presentation == null
        ? 'native'
        : 'presentation';
    _current[path] = (occurrence, chapter, predicted);
    (_contexts[path] ??= []).add(_current[path]!);
    for (final n in doc.querySelectorAll('*')) {
      final key = '$path:${epubTraceLocation(n)}';
      if (!_nodes.containsKey(key) && _nodes.length >= limit * 4) {
        truncated = true;
        break;
      }
      _nodes[key] = n;
      _styles[key] = styles[n] ?? const {};
    }
    paths.add({
      'document': path,
      'occurrence': occurrence,
      'chapterKey': chapter?.key.toJson(),
      'generatedNative': chapter != null,
      'generatedPresentation': presentation != null,
      'predictedPath': predicted,
      'observedPath': null,
      'fallbackReason': null,
    });
    final df = fact(
      path,
      null,
      'document',
      chapter == null ? CheckStatus.unknown : CheckStatus.pass,
      details: {
        'spine': spine,
        'generatedNative': chapter != null,
        'generatedPresentation': presentation != null,
        'predictedPath': predicted,
      },
    );
    if (chapter == null) {
      relate(df, [], CheckStatus.unknown, 'correspondence_unknown');
      return;
    }
    final chapterId = digest(jsonEncode(chapter.key.toJson()));
    final documentId = digest('$chapterId:native_document');
    if (representations.length >= limit * 2) {
      truncated = true;
      representationTruncated = true;
      relate(df, [], CheckStatus.unknown, 'representation_budget');
      return;
    }
    representations.add(
      RepresentationFact(
        id: documentId,
        chapterKey: chapter.key.toJson(),
        path: 'native',
        kind: 'native_document',
        metadata: {'blocks': chapter.blocks.length},
      ),
    );
    for (var blockIndex = 0; blockIndex < chapter.blocks.length; blockIndex++) {
      final block = chapter.blocks[blockIndex];
      if (representations.length >= limit * 2) {
        truncated = true;
        representationTruncated = true;
        break;
      }
      final text = auditBlockText(block);
      final id = digest(
        jsonEncode([chapterId, block.blockKey, blockIndex, 'native']),
      );
      _blockIds.putIfAbsent('$chapterId:${block.blockKey}', () => id);
      final refs = <String>[
        if (block is ImageBlock) block.media.mediaId.split('/').last,
        if (block is AudioBlock && block.media != null)
          block.media!.mediaId.split('/').last,
        for (final image in block.inlineImages)
          image.media.mediaId.split('/').last,
      ];
      representations.add(
        RepresentationFact(
          id: id,
          chapterKey: chapter.key.toJson(),
          blockKey: block.blockKey,
          path: 'native',
          kind: block.kind,
          textHash: text.isEmpty ? null : digest(text),
          range: text.isEmpty
              ? null
              : AuditRange(0, text.runes.length, 'unicode_code_point'),
          resources: refs,
          metadata: {
            'blockIndex': blockIndex,
            'ruby': [
              for (final r in block.inlineRuby)
                {
                  'start': r.start,
                  'length': r.length,
                  'unit': 'unicode_code_point',
                  'annotationHash': digest(r.annotation),
                },
            ],
            'stacks': block.inlineStacks.map((s) => s.toJson()).toList(),
            'box': block.box?.toJson(),
            'layout': block.layout?.toJson(),
            'fonts': block.inlineStyles
                .expand((s) => s.fonts)
                .map(
                  (f) => {
                    'familyHash': digest(f.familyName),
                    'resources': f.sources
                        .map((r) => r.mediaId.split('/').last)
                        .toList(),
                  },
                )
                .toSet()
                .toList(),
            if (block is AudioBlock) 'audioFormat': block.format?.name,
            if (block is ImageBlock) ...{
              'encodedNaturalSize': {
                'width': block.width,
                'height': block.height,
              },
              'imageSizing': block.sizing?.toJson(),
            },
            if (block is AudioBlock)
              'audioUnavailable': block.unavailable?.name,
          },
        ),
      );
      if (block is ImageBlock || block is AudioBlock) {
        final kind = block is AudioBlock ? 'audio' : 'image';
        final resource = refs.isEmpty ? 'unavailable' : refs.first;
        (_media[(path, resource, occurrence, kind)] ??= []).add(id);
      }
      for (final image in block.inlineImages) {
        if (representations.length >= limit * 2) {
          truncated = true;
          representationTruncated = true;
          break;
        }
        final resource = image.media.mediaId.split('/').last;
        final iid = digest(jsonEncode([id, 'inline_image', image.offset]));
        representations.add(
          RepresentationFact(
            id: iid,
            chapterKey: chapter.key.toJson(),
            blockKey: block.blockKey,
            path: 'native',
            kind: 'inline_image',
            range: AuditRange(image.offset, 1, 'unicode_code_point'),
            resources: [resource],
          ),
        );
        (_media[(path, resource, occurrence, 'image')] ??= []).add(iid);
      }
    }
    var presentationRetained = false;
    if (presentation != null && representations.length < limit * 2) {
      presentationRetained = true;
      representations.add(
        RepresentationFact(
          id: chapterId,
          chapterKey: chapter.key.toJson(),
          path: 'presentation',
          kind: 'inert_document',
          textHash: digest(presentation),
          metadata: {'bytes': utf8.encode(presentation).length},
        ),
      );
    } else if (presentation != null) {
      truncated = true;
      representationTruncated = true;
    }
    relate(
      df,
      [documentId, if (presentationRetained) chapterId],
      presentation != null && !presentationRetained
          ? CheckStatus.unknown
          : CheckStatus.pass,
      presentation != null && !presentationRetained
          ? 'representation_budget'
          : 'document_native_and_optional_presentation',
    );
    for (final node in doc.body?.querySelectorAll('*') ?? <dom.Element>[]) {
      if (hidden(node)) continue;
      final style = styles[node] ?? const {};
      final interesting =
          style.containsKey('font-family') ||
          style.containsKey('background-image') ||
          style.containsKey('border-radius') ||
          (style.containsKey('background-color') &&
              (style.containsKey('color') ||
                  node.querySelector('a[href]') != null));
      if (!interesting) continue;
      final f = fact(
        path,
        node,
        'authored_visual',
        CheckStatus.unknown,
        method: 'production_native_cascade',
        details: {
          'effectiveStyles': {
            for (final e in style.entries)
              if ({
                'color',
                'background-color',
                'background-image',
                'border-radius',
                'border-style',
                'width',
                'padding',
                'line-height',
                'text-align',
                'display',
                'visibility',
              }.contains(e.key))
                e.key: traceCssValue(e.value),
          },
          if (style['font-family'] != null)
            'fontDeclarationHash': digest(style['font-family']!),
        },
        uncertainties: const ['used_geometry_or_glyph_not_observed'],
      );
      if (f != null) {
        candidate(
          f,
          'visual.final_presentation',
          'authored_visual_requires_used_style',
          LossFamily.visual,
          CheckStatus.unknown,
          'decoration',
          'suspected',
          'representation_change_impact_unverified',
          [f.id],
        );
      }
    }
  }

  void text(
    String path,
    dom.Element node,
    String expected,
    ContentBlock? matched,
    List<(int, int, String)> ruby, {
    bool collapsesOrdinarySpaces = false,
  }) {
    final status = matched == null ? CheckStatus.fail : CheckStatus.pass;
    final f = fact(
      path,
      node,
      'text',
      status,
      text: expected,
      details: {
        'collapsesOrdinarySpaces': collapsesOrdinarySpaces,
        'ruby': [
          for (final r in ruby)
            {
              'start': r.$1,
              'length': r.$2,
              'annotationHash': digest(r.$3),
              'unit': 'unicode_code_point',
            },
        ],
      },
    );
    final c = _current[path]?.$2;
    final id = c == null || matched == null
        ? null
        : _blockIds['${digest(jsonEncode(c.key.toJson()))}:${matched.blockKey}'];
    relate(f, [?id], status, matched == null ? 'missing' : 'native_text');
    if (id != null) {
      for (final visual in facts.where(
        (v) =>
            v.kind == 'authored_visual' &&
            v.location.document == path &&
            v.location.occurrence == _current[path]?.$1 &&
            (epubTraceLocation(node) == v.location.domPath ||
                epubTraceLocation(node).startsWith('${v.location.domPath}/')),
      )) {
        relate(visual, [id], CheckStatus.pass, 'container_to_native_block');
      }
    }
    if (f != null && matched == null) {
      candidate(
        f,
        'text.simple_block_mismatch',
        'normalized_simple_block_not_found_in_order',
        LossFamily.content,
        CheckStatus.fail,
        'content_integrity',
        'confirmed',
        'confirmed_loss',
        [f.id],
      );
    }
    if (f != null && matched != null && ruby.isNotEmpty) {
      final same =
          jsonEncode(ruby.map((r) => [r.$1, r.$2, digest(r.$3)]).toList()) ==
          jsonEncode(
            matched.inlineRuby
                .map((r) => [r.start, r.length, digest(r.annotation)])
                .toList(),
          );
      final rf = fact(
        path,
        node,
        'ruby',
        same ? CheckStatus.pass : CheckStatus.fail,
        details: {'groups': ruby.length},
      );
      relate(
        rf,
        [?id],
        same ? CheckStatus.pass : CheckStatus.fail,
        'ruby_annotation',
      );
      if (rf != null && !same) {
        candidate(
          rf,
          'ruby.metadata_mismatch',
          'simple_ruby_pair_ranges_or_annotations_differ',
          LossFamily.content,
          CheckStatus.fail,
          'content_integrity',
          'confirmed',
          'confirmed_loss',
          [rf.id],
        );
      }
    }
  }

  ContentBlock? media(
    String path,
    dom.Element node,
    String kind,
    String? resource, {
    bool valid = true,
    Json details = const {},
    bool consumed = false,
  }) {
    final current = _current[path]!;
    final key = (path, resource ?? 'unavailable', current.$1, kind);
    final ids = _media[key] ?? const <String>[];
    final index = _consumed.update(key, (n) => n + 1, ifAbsent: () => 0);
    final id = index < ids.length ? ids[index] : null;
    final status = consumed
        ? CheckStatus.pass
        : id == null && representationTruncated && valid
        ? CheckStatus.unknown
        : id == null || !valid
        ? CheckStatus.fail
        : CheckStatus.pass;
    final f = fact(
      path,
      node,
      kind,
      status,
      details: {
        'resourceHash': resource,
        ...details,
        'sourceInstanceOrdinal': index,
        'consumedBySemanticAlternative': consumed,
      },
    );
    relate(
      f,
      [?id],
      status,
      consumed
          ? 'standard_note_marker'
          : id == null
          ? 'missing'
          : 'native_$kind',
    );
    if (id != null && !consumed && valid) {
      // Associate the source instance, including its DOM occurrence, with all
      // containing visual scopes. A shared media hash alone is not a target.
      final location = epubTraceLocation(node);
      for (final visual in facts.where(
        (v) =>
            v.kind == 'authored_visual' &&
            v.location.document == path &&
            v.location.occurrence == current.$1 &&
            (v.location.domPath == location ||
                location.startsWith('${v.location.domPath}/')),
      )) {
        relate(
          visual,
          [id],
          CheckStatus.pass,
          'native_media_scope',
          reason: 'association_does_not_prove_property_retention',
        );
      }
    }
    if (f != null && !consumed && status == CheckStatus.fail) {
      candidate(
        f,
        '$kind.control_or_instance_missing',
        'independent_source_instance_not_represented',
        LossFamily.content,
        CheckStatus.fail,
        'content_integrity',
        'confirmed',
        'confirmed_loss',
        [f.id],
      );
    }
    if (f != null &&
        kind == 'image' &&
        !consumed &&
        status == CheckStatus.pass &&
        (details['expectedAlignment'] != null ||
            details['aspectClass'] == 'tall_narrow')) {
      candidate(
        f,
        details['expectedAlignment'] == null
            ? 'image.geometry_observation'
            : 'image.authored_alignment',
        details['expectedAlignment'] == null
            ? 'source_image_geometry_requires_observation'
            : 'source_alignment_requires_paint_measurement',
        LossFamily.visual,
        CheckStatus.unknown,
        'layout',
        'suspected',
        'representation_change_impact_unverified',
        [f.id],
      );
    }
    final representation = representations.where((r) => r.id == id).firstOrNull;
    return current.$2?.blocks
        .where((b) => b.blockKey == representation?.blockKey)
        .firstOrNull;
  }

  void unknown(String path, dom.Element node, String reason) {
    final f = fact(
      path,
      node,
      'complex_expression',
      CheckStatus.unknown,
      effective: false,
      uncertainties: [reason],
    );
    relate(
      f,
      [],
      CheckStatus.unknown,
      'correspondence_unknown',
      reason: reason,
    );
  }

  void relationship(
    String path,
    dom.Element node,
    ContentBlock block,
    int? offset,
    int? length,
    bool passed, {
    required bool footnote,
  }) {
    final f = fact(
      path,
      node,
      footnote ? 'footnote' : 'link',
      passed ? CheckStatus.pass : CheckStatus.fail,
      details: {
        'sourceKind': offset == null ? 'block_image' : 'text_range',
        'sourceRange': offset == null
            ? null
            : AuditRange(offset, length ?? 1, 'unicode_code_point').toJson(),
      },
    );
    final chapter = _current[path]?.$2;
    final id = chapter == null
        ? null
        : _blockIds['${digest(jsonEncode(chapter.key.toJson()))}:${block.blockKey}'];
    relate(
      f,
      [?id],
      passed ? CheckStatus.pass : CheckStatus.fail,
      footnote
          ? 'standard_note_marker_and_payload'
          : offset == null
          ? 'native_block_image_link'
          : 'native_link_range',
    );
    if (f != null && !passed) {
      candidate(
        f,
        footnote ? 'footnote.output_missing' : 'link.relationship_missing',
        footnote
            ? 'standard_note_marker_range_or_payload_missing'
            : 'simple_source_range_or_target_range_missing',
        LossFamily.interaction,
        CheckStatus.fail,
        'navigation',
        'confirmed',
        'confirmed_loss',
        [f.id],
      );
    }
  }

  void candidate(
    SourceFact fact,
    String rule,
    String reason,
    LossFamily family,
    CheckStatus status,
    String impact,
    String confidence,
    String classification,
    List<String> evidence, {
    int instances = 1,
    String accuracy = 'exact',
  }) {
    final path = _current[fact.location.document]?.$3 ?? 'unrepresented';
    final id = digest(jsonEncode([fact.id, rule, reason]));
    if (!_candidateIds.add(id)) return;
    if (candidates.length >= limit ~/ 2) {
      truncated = true;
      if (status != CheckStatus.fail) return;
      final removable = candidates
          .where((c) => c.status != CheckStatus.fail)
          .lastOrNull;
      if (removable == null) return;
      _candidateIds.remove(removable.id);
      candidates.remove(removable);
    }
    candidates.add(
      LossCandidate(
        id: id,
        sourceId: fact.id,
        groupId: digest(jsonEncode([fact.shape, rule, reason, path])),
        location: fact.location,
        family: family,
        rule: rule,
        reason: reason,
        impact: impact,
        confidence: confidence,
        status: status,
        predictedPath: path,
        classification: classification,
        evidenceRefs: evidence,
        uncertainties: fact.uncertainties,
        methods: path == 'presentation' ? ['browser', 'webview'] : ['native'],
        instances: instances,
        countAccuracy: accuracy,
      ),
    );
  }

  void observations(Iterable<Json> observations) {
    final ordered = observations.toList()
      ..sort((a, b) {
        int tier(Json f) =>
            f['confidence'] == 'confirmed' &&
                {'content_integrity', 'navigation'}.contains(f['impact'])
            ? 0
            : 1;
        return tier(a).compareTo(tier(b));
      });
    for (final observation in ordered) {
      final disposition = observation['disposition'];
      if (observation['confidence'] == 'confirmed' &&
          {
            'emitted_native',
            'emitted_presentation',
            'not_applicable',
          }.contains(disposition)) {
        continue;
      }
      final locations = (observation['locations'] as List? ?? []).cast<Json>();
      for (final loc in locations) {
        final path = loc['document'] as String;
        if (!_current.containsKey(path)) continue;
        for (final context in _contexts[path]!) {
          _current[path] = context;
          if (candidates.any(
            (c) =>
                c.rule == observation['ruleId'] &&
                c.location.document == path &&
                c.location.occurrence == context.$1 &&
                c.location.domPath == loc['domPath'],
          )) {
            continue;
          }
          final node = _nodes['$path:${loc['domPath']}'];
          // Aggregate observations cannot invent unrecorded instance locations.
          final f = fact(
            path,
            node,
            'observation:${observation['ruleId']}:${observation['property'] ?? ''}',
            observation['confidence'] == 'confirmed' &&
                    {
                      'content_integrity',
                      'navigation',
                    }.contains(observation['impact']) &&
                    !{
                      'invalid_input',
                      'security_filtered',
                      'policy_override',
                    }.contains(disposition)
                ? CheckStatus.fail
                : CheckStatus.unknown,
            effective: observation['evidence'] != 'source_only',
            method: observation['evidence'] == 'source_only'
                ? 'declaration_presence_only'
                : 'parser_decision_and_model',
            details: {
              'property': observation['property'],
              'stylesheet': loc['stylesheet'],
              'ruleIndex': loc['ruleIndex'],
              'declarationIndex': loc['declarationIndex'],
              'value': loc['value'],
              'counts': observation['counts'],
            },
            uncertainties: observation['confidence'] == 'confirmed'
                ? []
                : ['correspondence_or_effectiveness_unknown'],
          );
          if (f == null) continue;
          final mapped = <String>{};
          for (final text in facts.where(
            (s) =>
                {'text', 'image', 'audio', 'link'}.contains(s.kind) &&
                s.location.document == path &&
                s.location.occurrence == context.$1 &&
                (s.location.domPath == f.location.domPath ||
                    s.location.domPath.startsWith('${f.location.domPath}/') ||
                    f.location.domPath.startsWith('${s.location.domPath}/')),
          )) {
            for (final relation in relations.where(
              (r) => r.sourceId == text.id && r.status == CheckStatus.pass,
            )) {
              mapped.addAll(relation.representationIds);
            }
          }
          relate(
            f,
            mapped.toList(),
            mapped.isEmpty ? CheckStatus.unknown : CheckStatus.pass,
            'observed_property_to_native_scope',
            reason: 'association_does_not_prove_property_retention',
          );
          final info = {
            'policy_override',
            'security_filtered',
          }.contains(disposition);
          final impact = observation['impact'] as String;
          final confidence = observation['confidence'] as String;
          // A confirmed cascade proves the winning declaration exists, not
          // that its native representation lost anything. Keep its fact and
          // scope association above without spending a verification target.
          if (impact == 'information' &&
              !info &&
              disposition != 'invalid_input') {
            continue;
          }
          final family = {'content_integrity', 'navigation'}.contains(impact)
              ? impact == 'navigation'
                    ? LossFamily.interaction
                    : LossFamily.content
              : observation['category'] == 'structure'
              ? LossFamily.structure
              : LossFamily.visual;
          final classification = info
              ? disposition == 'security_filtered'
                    ? 'security_boundary'
                    : 'reader_policy'
              : disposition == 'invalid_input'
              ? 'source_issue'
              : confidence == 'confirmed' &&
                    {'content_integrity', 'navigation'}.contains(impact)
              ? 'confirmed_loss'
              : confidence == 'confirmed'
              ? 'representation_change_impact_unverified'
              : confidence == 'unknown'
              ? 'insufficient_evidence'
              : {'content_integrity', 'navigation'}.contains(impact)
              ? 'suspected_high_impact'
              : observation['evidence'] == 'source_only'
              ? 'insufficient_evidence'
              : 'representation_change_impact_unverified';
          candidate(
            f,
            observation['ruleId'] as String,
            observation['reason'] as String,
            family,
            info
                ? CheckStatus.pass
                : classification == 'confirmed_loss'
                ? CheckStatus.fail
                : CheckStatus.unknown,
            impact,
            confidence,
            classification,
            [f.id, observation['stableKey'] as String],
            instances: 1,
            accuracy:
                locations.length > 1 || observation['countAccuracy'] != 'exact'
                ? 'lower_bound'
                : 'aggregate_observation_not_instance_exact',
          );
        }
      }
    }
  }

  void unexplained(Iterable<Json> events) {
    for (final event in events) {
      final reason = event['reason'] as String? ?? '';
      final decision = event['decision'] as String? ?? '';
      if (!RegExp(
        r'drop|reject|flatten|unsupported|not_emitted|degrad',
      ).hasMatch('$reason $decision')) {
        continue;
      }
      final path = event['document'] as String?;
      final domPath = event['location'] as String?;
      if (path == null || domPath == null || !_contexts.containsKey(path)) {
        continue;
      }
      for (final context in _contexts[path]!) {
        _current[path] = context;
        if (candidates.any(
          (c) =>
              c.location.document == path &&
              c.location.occurrence == context.$1 &&
              c.location.domPath == domPath,
        )) {
          continue;
        }
        final node = _nodes['$path:$domPath'];
        if (node == null) continue;
        final f = fact(
          path,
          node,
          'unexplained_decision',
          CheckStatus.unknown,
          effective: false,
          method: 'parser_decision_only',
          details: {'decision': decision, 'reason': reason},
          uncertainties: [
            'independent_effectiveness_and_correspondence_unresolved',
          ],
        );
        if (f != null) {
          candidate(
            f,
            'loss.unexplained_decision',
            reason,
            LossFamily.structure,
            CheckStatus.unknown,
            'structure',
            'unknown',
            'insufficient_evidence',
            [f.id],
          );
        }
      }
    }
  }

  Json toJson() => {
    'sourceFacts': facts.map((f) => f.toJson()).toList(),
    'representations': representations.map((f) => f.toJson()).toList(),
    'correspondences': relations.map((f) => f.toJson()).toList(),
    'candidates': candidates.map((f) => f.toJson()).toList(),
    'displayPaths': paths,
    'coverage': {
      'factsComplete': !truncated,
      'correspondenceComplete': !truncated,
      'candidateCountAccuracy': truncated
          ? 'lower_bound'
          : 'bounded_observed_scope',
      'runtime': {
        for (final layer in EvidenceLayer.values) wireName(layer): 'not_run',
      },
      'maxFacts': limit,
      'maxRepresentations': limit * 2,
      'maxCandidates': limit ~/ 2,
      'wholeBookCertification': false,
    },
  };
}
