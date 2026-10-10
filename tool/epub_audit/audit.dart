import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_trace.dart';
import 'package:shiori/data/local/epub/epub_text_styles.dart';
import 'package:shiori/data/local/epub/epub_footnotes.dart';
import 'package:shiori/data/local/epub/epub_image_candidates.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'package:shiori/domain/contracts/local_content_links.dart';
import 'package:shiori/domain/models/models.dart';
import 'report.dart';
import 'source.dart';

const checkNames = [
  'documents',
  'text',
  'whitespace',
  'ruby',
  'footnotes',
  'images',
  'navigation',
  'links',
  'css',
  'structures',
  'presentation',
  'runtime',
];
Json emptyBook(String status) => {
  'status': status,
  'auditComplete': false,
  'checks': {
    for (final key in checkNames)
      key: {'status': 'not_run', 'checked': 0, 'failed': 0, 'unknown': 0},
  },
  'findings': <Json>[],
  'documents': <Json>[],
  'truncationReasons': <String>[],
};

Json auditBytes(
  Uint8List bytes, {
  AuditOptions options = const AuditOptions(),
}) {
  if (bytes.length > BookDecoder.maxEpubBytes) {
    return emptyBook('production_rejected')..['failureCategory'] = 'tooLarge';
  }
  final hash = sha256.convert(bytes).toString();
  final trace = EpubTraceCollector(capacity: options.maxEvents);
  final parser = EpubParser(
    bytes,
    LocalBookIdentity.book(hash),
    'audit.epub',
    includePresentations: true,
    trace: trace,
  );
  ParsedEpub parsed;
  try {
    parsed = parser.parse();
  } on LocalParseException catch (e) {
    return emptyBook('production_rejected')
      ..['failureCategory'] = e.problem.name;
  } on FormatException {
    return emptyBook('production_rejected')..['failureCategory'] = 'invalid';
  } catch (_) {
    return emptyBook('parser_exception')
      ..['failureCategory'] = 'unexpected_parser_exception';
  }
  return auditParsed(parser, parsed, options: options);
}

/// Test adapters may alter only the supplied output. Independent source
/// expectations must still detect omissions, even when trace says "emitted".
Json auditParsed(
  EpubParser parser,
  ParsedEpub parsed, {
  AuditOptions options = const AuditOptions(),
}) {
  final audit = _Audit(parser, parsed, options);
  try {
    audit.run();
  } on SourceBudgetExceeded {
    audit.truncations.add('source_scan_budget');
  } on LocalParseException catch (e) {
    audit.truncations.add('source_scan_${e.problem.name}');
  } on FormatException {
    audit.truncations.add('source_scan_invalid');
  } catch (_) {
    audit.truncations.add('audit_exception');
  }
  return audit.report();
}

final class _SimpleText {
  _SimpleText(this.text, this.ruby, this.links, this.hasVisibleBreak);
  final String text;
  final List<(int, int, String)> ruby;
  final Map<dom.Element, List<(int, int)>> links;
  final bool hasVisibleBreak;
}

final class _Audit {
  _Audit(this.parser, this.parsed, this.options)
    : source = SourceInventory(parser.bytes, options),
      findings = FindingCollector(options.maxFindings);
  final EpubParser parser;
  final ParsedEpub parsed;
  final AuditOptions options;
  final SourceInventory source;
  final FindingCollector findings;
  final checks = {for (final name in checkNames) name: AuditCheck()};
  final documents = <Json>[];
  final truncations = <String>[];
  final docs = <String, dom.Document>{};
  final chapterByPath = <String, ChapterContent>{};
  final paths = <String, String>{};
  final selectedResources = <String>{};
  int simpleTextBlocks = 0,
      unknownTextBlocks = 0,
      selectedImages = 0,
      nativeImages = 0,
      presentationImages = 0;
  final hiddenCssLocations = <String>{};
  final anchorIds = <String, Set<String>>{};
  final sheetFingerprints = <String, String>{};
  // Only independent, simple source ranges get a model correspondence.
  final sourceRanges = <dom.Element, (ContentBlock, int, int)>{};
  late final List<Map<String, Object?>> events =
      parser.trace?.events ?? const [];

  Json report() {
    if (parser.trace?.truncated == true) truncations.add('trace_capacity');
    if (findings.truncated) truncations.add('finding_capacity');
    if (truncations.isNotEmpty) {
      for (final name
          in (truncations.every((r) => r == 'trace_capacity')
              ? ['css', 'structures']
              : checks.keys)) {
        checks[name]!.unknown++;
      }
      for (final f in findings.findings) {
        f['countAccuracy'] = 'lower_bound';
      }
    }
    checks['runtime']!.unknown = 1;
    final result = <String, dynamic>{
      'status': truncations.contains('audit_exception')
          ? 'audit_exception'
          : 'parsed',
      'auditComplete': truncations.isEmpty,
      'checks': {for (final e in checks.entries) e.key: e.value.toJson()},
      'documents': documents,
      'findings': findings.findings,
      'truncationReasons': truncations.toSet().toList(),
      'documentPaths': {
        for (final path in paths.values.toSet())
          path: paths.values.where((p) => p == path).length,
      },
      'metrics': {
        'simpleTextBlocksChecked': simpleTextBlocks,
        'textBlocksUnknown': unknownTextBlocks,
        'selectedVisibleImageInstances': selectedImages,
        'nativeImageInstances': nativeImages,
        'presentationImageInstances': presentationImages,
        'selectedUniqueResources': selectedResources.length,
        'outputUniqueResources': parsed.media.length,
        'chapters': parsed.content.chapters.length,
        'auxiliaryChapters': parsed.content.auxiliaryChapters.length,
        'traceEvents': events.length,
        'productionDiagnostics': parsed.diagnostics.codes
            .map((e) => e.name)
            .toList(),
        'productionDiagnosticsTruncated': parsed.diagnostics.truncated,
      },
      'coverage': {
        'text':
            'Simple source/output blocks consumed in order; uncovered source text and output blocks scoped unknown; complete simple documents detect extra output',
        'images':
            'Visible selected raster instances, native/inline and presentation counted separately',
        'css':
            'Actual bounded native cascade; unknown properties are matching candidates only',
        'navigation':
            'Independent source relationships plus output chapter/block/range invariants',
        'runtime': 'not verified',
      },
    };
    if (utf8.encode(jsonEncode(result)).length > 8 * 1024 * 1024) {
      result['auditComplete'] = false;
      result['findings'] = <Json>[];
      (result['truncationReasons'] as List).add('report_bytes');
      for (final check in (result['checks'] as Json).values) {
        (check as Json)['status'] = 'unknown';
      }
    }
    return result;
  }

  String pathFor(String path) => paths[path] ?? 'unused';
  void add(
    String rule,
    String path,
    String reason, {
    String category = 'content',
    String impact = 'content_integrity',
    String confidence = 'confirmed',
    String disposition = 'degraded',
    String evidence = 'output_verified',
    String? location,
    Json counts = const {},
    int count = 1,
    String? review,
  }) => findings.add(
    rule,
    path,
    reason,
    category: category,
    impact: impact,
    confidence: confidence,
    disposition: disposition,
    evidence: evidence,
    path: pathFor(path),
    location: location,
    counts: counts,
    count: count,
    review: review,
  );
  void run() {
    source.load();
    for (final c in [
      ...parsed.content.chapters,
      ...parsed.content.auxiliaryChapters,
    ]) {
      final path = parser.chapterPaths[c.key];
      if (path != null) chapterByPath.putIfAbsent(path, () => c);
    }
    final candidates = <String>{
      for (final s in source.spine) s['selectedPath'] as String,
      ...source.navigationPaths,
      for (final item in source.items.values)
        if (item['path'] != null &&
            {'application/xhtml+xml', 'text/html'}.contains(item['type']))
          item['path'] as String,
    };
    for (final path in candidates) {
      if (!source.zip.entries.containsKey(path)) {
        checks['documents']!.failed++;
        add(
          'document.missing_resource',
          path,
          'manifest_target_not_in_zip',
          disposition: 'invalid_input',
        );
        continue;
      }
      if (path.endsWith('.ncx') ||
          source.items.values.any(
            (i) => i['path'] == path && i['type'] == 'application/x-dtbncx+xml',
          )) {
        auditNcx(path);
        continue;
      }
      final doc = source.document(path);
      docs[path] = doc;
      final chapter = chapterByPath[path];
      final spine = source.spine
          .where((s) => s['selectedPath'] == path)
          .toList();
      final presentation = chapter == null
          ? null
          : parser.presentations[chapter.key.chapterId];
      final fixed = spine.any((s) => s['fixed'] == true);
      paths[path] = chapter == null
          ? (parser.skippedEmptyPaths.contains(path)
                ? 'empty_skipped'
                : source.navigationPaths.contains(path)
                ? 'navigation'
                : 'unused')
          : fixed
          ? 'fixed_image'
          : presentation == null
          ? 'native'
          : 'presentation';
      checks['documents']!.checked++;
      final sheets = epubDocumentStylesheets(
        doc,
        path,
        optionalEpubStyleReference,
        (p) =>
            source.zip.entries.containsKey(p) ? source.text(p, css: true) : '',
      ).toList();
      var inlineIndex = 0;
      for (final sheet in sheets) {
        sheetFingerprints['$path:${sheet.$1 == path ? '$path#style${inlineIndex++}' : sheet.$1}'] =
            digest(sheet.$2);
      }
      final styles = epubTextStyles(doc, sheets.map((s) => s.$2));
      anchorIds[path] = {
        for (final n in doc.querySelectorAll('[id]'))
          if (!hidden(n, styles)) n.id,
      };
      final wantedLocations = events
          .where(
            (e) =>
                e['document'] == path &&
                (e['kind'] as String).startsWith('css.'),
          )
          .map((e) => e['location'])
          .whereType<String>()
          .toSet();
      if (wantedLocations.isNotEmpty) {
        for (final node in doc.querySelectorAll('*')) {
          final location = epubTraceLocation(node);
          if (wantedLocations.contains(location) && hidden(node, styles)) {
            hiddenCssLocations.add('$path:$location');
          }
        }
      }
      final visible =
          [
                if (doc.body != null) doc.body!,
                ...doc.body?.querySelectorAll('*') ?? <dom.Element>[],
              ]
              .where((n) => !hidden(n, styles))
              .any(
                (n) =>
                    n.nodes.whereType<dom.Text>().any(
                      (t) => t.data.trim().isNotEmpty,
                    ) ||
                    {'img', 'image'}.contains(n.localName),
              );
      String coverage = 'pass';
      for (final s in spine) {
        final key = LocalBookIdentity.epubOccurrence(
          parser.book,
          path,
          s['occurrence'] as int,
        );
        if (!parsed.content.chapters.any((c) => c.key == key)) {
          if (visible && !parser.skippedEmptyPaths.contains(path)) {
            checks['documents']!.failed++;
            coverage = 'fail';
            add(
              'document.spine_omitted',
              path,
              'nonempty_selected_spine_has_no_output',
              counts: {'spineOccurrence': s['occurrence']},
            );
          } else if (visible) {
            checks['documents']!.unknown++;
            coverage = 'unknown';
            add(
              'document.skipped',
              path,
              'empty_skip_requires_structural_review',
              confidence: 'unknown',
              disposition: 'unknown',
              impact: 'audit_coverage',
            );
          }
        }
      }
      documents.add({
        'path': safeLabel(path),
        'processingPath': pathFor(path),
        'spineOccurrences': spine.length,
        'linearNo': spine.where((s) => s['linear'] == false).length,
        'fallbackOriginals': spine
            .expand((s) => (s['fallbackChain'] as List))
            .whereType<String>()
            .map(safeLabel)
            .toList(),
        'auxiliary':
            chapter != null &&
            parsed.content.auxiliaryChapters.contains(chapter),
        'navigation': source.navigationPaths.contains(path),
        'coverage': coverage,
      });
      if (source.navigationPaths.contains(path)) {
        for (final nav in doc.querySelectorAll('nav').where(isToc)) {
          for (final a in nav.querySelectorAll('a[href]')) {
            navigationTarget(path, a.attributes['href']!, epubTraceLocation(a));
          }
        }
      }
      if (chapter == null) continue;
      textAudit(path, doc, styles, chapter, presentation != null || fixed);
      imageAudit(path, doc, styles, chapter, presentation);
      structureAudit(path, doc, styles, chapter);
      sourceLinks(path, doc, styles, chapter);
      if (presentation != null) {
        checks['presentation']!.checked++;
        add(
          'presentation.generated',
          path,
          'inert_document_generated_runtime_unverified',
          category: 'presentation',
          impact: 'information',
          disposition: 'emitted_presentation',
          evidence: 'parser_decision',
          counts: {
            'bytes': utf8.encode(presentation).length,
            'sha256': digest(presentation),
          },
        );
      }
    }
    modelLinks();
    cssAudit();
    // Never infer completeness from the capped production diagnostics.
    checks['documents']!.checked += source.spine.length;
    for (final item in source.items.values.where(
      (i) => i['type'] == 'text/css' && i['path'] != null,
    )) {
      final path = item['path'] as String;
      if (!events.any(
        (e) =>
            e['kind'] == 'css.sheet' &&
            e['stylesheet'] == path &&
            e['reason'] == 'loaded',
      )) {
        add(
          'css.unloaded_inventory',
          path,
          'manifest_sheet_not_loaded',
          category: 'css',
          impact: 'information',
          disposition: 'not_applicable',
          evidence: 'source_only',
        );
      }
    }
  }

  bool subtreeExcluded(
    dom.Element node,
    Map<dom.Element, Map<String, String>> styles,
  ) {
    for (dom.Element? e = node; e != null; e = e.parent) {
      if (e.attributes.containsKey('hidden') ||
          styles[e]?['display'] == 'none' ||
          epubFootnote(e) ||
          {
            'script',
            'style',
            'head',
            'noscript',
            'iframe',
            'object',
            'embed',
            'audio',
            'video',
            'canvas',
          }.contains(e.localName)) {
        return true;
      }
    }
    return false;
  }

  bool hidden(dom.Element node, Map<dom.Element, Map<String, String>> styles) {
    if (subtreeExcluded(node, styles)) return true;
    var visibility = true;
    final lineage = <dom.Element>[];
    for (dom.Element? e = node; e != null; e = e.parent) {
      lineage.add(e);
    }
    for (final e in lineage.reversed) {
      switch (styles[e]?['visibility']) {
        case 'visible':
        case 'initial':
          visibility = true;
        case 'hidden':
        case 'collapse':
          visibility = false;
      }
    }
    return !visibility;
  }

  String? inherited(
    dom.Element node,
    Map<dom.Element, Map<String, String>> styles,
    String property,
  ) {
    for (dom.Element? e = node; e != null; e = e.parent) {
      final v = styles[e]?[property];
      if (v != null && !{'inherit', 'unset'}.contains(v)) return v;
    }
    return null;
  }

  String blockText(ContentBlock block) => switch (block) {
    ParagraphBlock(:final text) || HeadingBlock(:final text) => text,
    _ => '',
  };
  _SimpleText normalizeSimple(
    dom.Element root,
    Map<dom.Element, Map<String, String>> styles,
    Map<dom.Element, String> markers,
  ) {
    final output = StringBuffer();
    final ruby = <(int, int, String)>[];
    final links = <dom.Element, List<(int, int)>>{};
    var pre = false, hasVisibleBreak = false;
    void write(String text, dom.Element? owner) {
      if (text.isEmpty) return;
      final from = output.length;
      output.write(text);
      if (owner == null) return;
      final ranges = links[owner] ??= [];
      if (ranges.isNotEmpty && ranges.last.$2 == from) {
        final last = ranges.removeLast();
        ranges.add((last.$1, output.length));
      } else {
        ranges.add((from, output.length));
      }
    }

    void walk(dom.Node node, String mode, dom.Element? owner) {
      if (node is dom.Text) {
        if (node.parent case final parent?) {
          if (hidden(parent, styles)) return;
        }
        if ({'pre', 'pre-wrap'}.contains(mode)) pre = true;
        var text = node.data.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
        if (!{'pre', 'pre-wrap'}.contains(mode)) {
          text = text.replaceAll(
            RegExp(mode == 'pre-line' ? r'[ \t\f]+' : r'[ \t\n\f]+'),
            ' ',
          );
        }
        write(text, owner);
        return;
      }
      if (node is! dom.Element ||
          subtreeExcluded(node, styles) ||
          node.localName == 'rp' ||
          node.localName == 'rt') {
        return;
      }
      final own = styles[node]?['white-space'];
      final next = own == null || {'inherit', 'unset'}.contains(own)
          ? (node.localName == 'pre' ? 'pre' : mode)
          : own == 'initial'
          ? 'normal'
          : own;
      final visible = !hidden(node, styles);
      if (visible && markers.containsKey(node)) {
        final marker = markers[node]!;
        write(marker, node);
        return;
      }
      if (visible &&
          node.localName == 'a' &&
          node.attributes.containsKey('href')) {
        owner = node;
      }
      if (node.localName == 'br') {
        if (visible) {
          hasVisibleBreak = true;
          write('\n', owner);
        }
        return;
      }
      if (node.localName == 'ruby' &&
          simpleRuby(node) &&
          !node.querySelectorAll('rt').any((rt) => hidden(rt, styles)) &&
          !{'pre', 'pre-wrap', 'pre-line'}.contains(next)) {
        var base = <dom.Node>[];
        for (final child in node.nodes) {
          if (child is dom.Element && child.localName == 'rp') continue;
          if (child is dom.Element && child.localName == 'rt') {
            final start = output.length;
            for (final b in base) {
              walk(b, next, owner);
            }
            ruby.add((
              start,
              output.length,
              child.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
            ));
            base = [];
          } else {
            base.add(child);
          }
        }
        return; // trailing formatting whitespace after the final rt is not base
      }
      for (final child in node.nodes) {
        walk(child, next, owner);
      }
    }

    walk(root, inherited(root, styles, 'white-space') ?? 'normal', null);
    final raw = output.toString();
    var text = raw;
    if (!pre) {
      text = text.replaceAll(RegExp(r'^[ \t\r\n\f]+|[ \t\r\n\f]+$'), '');
    }
    final trim = text.isEmpty ? raw.length : raw.indexOf(text);
    (int, int)? range(int from, int to, {bool trimRuby = false}) {
      var start = (from - trim).clamp(0, text.length);
      var end = (to - trim).clamp(0, text.length);
      if (trimRuby) {
        while (start < end && text[start].trim().isEmpty) {
          start++;
        }
        while (end > start && text[end - 1].trim().isEmpty) {
          end--;
        }
      }
      if (end <= start) return null;
      return (
        text.substring(0, start).runes.length,
        text.substring(start, end).runes.length,
      );
    }

    return _SimpleText(
      text,
      [
        for (final r in ruby)
          if (range(r.$1, r.$2, trimRuby: true) case final span?)
            (span.$1, span.$2, r.$3),
      ],
      {
        for (final entry in links.entries)
          entry.key: [for (final r in entry.value) ?range(r.$1, r.$2)],
      },
      hasVisibleBreak,
    );
  }

  bool simpleRuby(dom.Element ruby) {
    if (ruby
        .querySelectorAll('*')
        .any(
          (n) => !{
            'rb',
            'rt',
            'rp',
            'span',
            'b',
            'strong',
            'i',
            'em',
            'u',
          }.contains(n.localName),
        )) {
      return false;
    }
    var base = StringBuffer(), pairs = 0;
    for (final node in ruby.nodes) {
      if (node is dom.Element && node.localName == 'rp') continue;
      if (node is dom.Element && node.localName == 'rt') {
        if (base.toString().trim().isEmpty ||
            base.toString().trim().runes.length > 64 ||
            node.text.trim().isEmpty ||
            node.text.trim().runes.length > 256) {
          return false;
        }
        base = StringBuffer();
        pairs++;
      } else {
        if (node is dom.Element && node.querySelector('rt,rp') != null) {
          return false;
        }
        base.write(node.text ?? '');
      }
    }
    return pairs > 0 && base.toString().trim().isEmpty;
  }

  void textAudit(
    String path,
    dom.Document doc,
    Map<dom.Element, Map<String, String>> styles,
    ChapterContent chapter,
    bool special,
  ) {
    final unknownBefore = unknownTextBlocks;
    final output = chapter.blocks
        .where((b) => b is ParagraphBlock || b is HeadingBlock)
        .toList();
    final matched = <int>{};
    final outputTextCounts = <String, int>{};
    for (final block in output) {
      outputTextCounts.update(
        blockText(block),
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    var cursor = 0, authoredBlanks = 0;
    final markers = <dom.Element, String>{};
    final authored = RegExp(r'⁽[⁰¹²³⁴⁵⁶⁷⁸⁹]+⁾')
        .allMatches(doc.documentElement?.text ?? '')
        .map((m) => m.group(0)!)
        .toSet();
    var noteNumber = 0;
    for (final a in doc.body!.querySelectorAll('a[href]')) {
      if (!epubNoteref(a) || hidden(a, styles)) continue;
      String marker;
      do {
        marker = epubFootnoteMarker(++noteNumber);
      } while (authored.contains(marker));
      markers[a] = marker;
    }
    final roots = doc.body!.querySelectorAll(
      'p,h1,h2,h3,h4,h5,h6,pre,li,dt,dd',
    );
    if (roots.isEmpty &&
        doc.body!.children.every(
          (n) => {
            'span',
            'a',
            'b',
            'strong',
            'i',
            'em',
            'br',
            'ruby',
            'rb',
            'rt',
            'rp',
            'sup',
            'sub',
            'small',
            'mark',
            'code',
          }.contains(n.localName),
        )) {
      roots.add(doc.body!);
    }
    // Inspect text outside the selected roots even when the document has p's.
    // Container flattening is not a reliable one-to-one block contract.
    final rootSet = roots.toSet();
    final uncovered = <dom.Element>{};
    final uncoveredStructures = <dom.Element>{};
    void coverage(dom.Node node, dom.Element owner) {
      if (node is dom.Text) {
        if (hidden(owner, styles)) return;
        if (node.data.replaceAll(RegExp(r'[ \t\r\n\f]'), '').isNotEmpty) {
          uncovered.add(owner);
        }
        return;
      }
      if (node is! dom.Element ||
          subtreeExcluded(node, styles) ||
          rootSet.contains(node) ||
          {'rt', 'rp'}.contains(node.localName)) {
        return;
      }
      if ({'img', 'image', 'picture', 'svg'}.contains(node.localName)) {
        uncoveredStructures.add(node);
        return;
      }
      if (epubNoteref(node)) {
        uncovered.add(node);
        return;
      }
      for (final child in node.nodes) {
        coverage(child, node);
      }
    }

    coverage(doc.body!, doc.body!);
    if (uncoveredStructures.isNotEmpty) {
      checks['text']!.unknown += uncoveredStructures.length;
      unknownTextBlocks += uncoveredStructures.length;
      for (final owner in uncoveredStructures) {
        add(
          'text.coverage',
          path,
          'nontext_source_outside_simple_roots',
          location: epubTraceLocation(owner),
          impact: 'audit_coverage',
          confidence: 'unknown',
          disposition: 'unknown',
          evidence: 'source_only',
        );
      }
    }
    if (uncovered.isNotEmpty) {
      checks['text']!.unknown += uncovered.length;
      unknownTextBlocks += uncovered.length;
      for (final owner in uncovered) {
        add(
          'text.coverage',
          path,
          'visible_source_text_outside_simple_roots',
          location: epubTraceLocation(owner),
          impact: 'audit_coverage',
          confidence: 'unknown',
          disposition: 'unknown',
          evidence: 'source_only',
        );
      }
    }
    for (final node in roots) {
      if (subtreeExcluded(node, styles)) continue;
      final complex =
          node.querySelectorAll('*').any((n) {
            if (hidden(n, styles)) return false;
            for (
              var parent = n.parent;
              parent != null && parent != node;
              parent = parent.parent
            ) {
              if (markers.containsKey(parent)) return false;
            }
            return !{
                  'span',
                  'a',
                  'b',
                  'strong',
                  'i',
                  'em',
                  'br',
                  'ruby',
                  'rb',
                  'rt',
                  'rp',
                  'sup',
                  'sub',
                  'small',
                  'mark',
                  'code',
                }.contains(n.localName) ||
                inherited(n, styles, 'white-space') == 'pre-line';
          }) ||
          node
              .querySelectorAll('ruby')
              .where((r) => !subtreeExcluded(r, styles))
              .any(
                (r) =>
                    !simpleRuby(r) ||
                    r
                        .querySelectorAll('rt')
                        .any(
                          (rt) =>
                              hidden(rt, styles) ||
                              rt
                                  .querySelectorAll('*')
                                  .any((n) => hidden(n, styles)),
                        ) ||
                    {
                      'pre',
                      'pre-wrap',
                      'pre-line',
                    }.contains(inherited(r, styles, 'white-space')) ||
                    node.localName == 'pre',
              );
      if (complex ||
          special ||
          inherited(node, styles, 'white-space') == 'pre-line') {
        unknownTextBlocks++;
        checks['text']!.unknown++;
        if (node.querySelector('ruby') != null) checks['ruby']!.unknown++;
        continue;
      }
      final normalized = normalizeSimple(node, styles, markers);
      final expected = normalized.text;
      if (expected.isEmpty) {
        if (normalized.hasVisibleBreak) authoredBlanks++;
        continue;
      }
      if (expected.trim().isEmpty) {
        // Whitespace-only authored text can become gap metadata. Its literal
        // text is not a supported one-to-one source/output correspondence.
        checks['text']!.unknown++;
        checks['whitespace']!.unknown++;
        unknownTextBlocks++;
        add(
          'text.coverage',
          path,
          'whitespace_only_source_block_correspondence_unknown',
          location: epubTraceLocation(node),
          impact: 'audit_coverage',
          confidence: 'unknown',
          disposition: 'unknown',
          evidence: 'source_only',
        );
        continue;
      }
      simpleTextBlocks++;
      checks['text']!.checked++;
      var found = -1;
      for (var i = cursor; i < output.length; i++) {
        if (blockText(output[i]) == expected) {
          found = i;
          break;
        }
      }
      if (found < 0) {
        checks['text']!.failed++;
        add(
          'text.simple_block_mismatch',
          path,
          'normalized_simple_block_not_found_in_order',
          location: epubTraceLocation(node),
          counts: {
            'sourceCharacters': expected.runes.length,
            'sourceSha256': digest(expected),
          },
          review:
              'Compare this simple source block with native output; source-format ASCII whitespace is normalized, NBSP/pre/br remain distinct.',
        );
      } else {
        cursor = found + 1;
        matched.add(found);
        // Repeated identical output in a partial document could belong to an
        // unmapped container. Do not attach ranges to an arbitrary occurrence.
        final reliable =
            unknownTextBlocks == unknownBefore ||
            outputTextCounts[expected] == 1;
        for (final entry in normalized.links.entries) {
          if (reliable && entry.value.length == 1) {
            final range = entry.value.single;
            sourceRanges[entry.key] = (output[found], range.$1, range.$2);
          }
        }
        if (normalized.hasVisibleBreak ||
            node.localName == 'pre' ||
            expected.contains('\u00a0')) {
          checks['whitespace']!.checked++;
        }
        final annotations = normalized.ruby;
        if (annotations.isNotEmpty || output[found].inlineRuby.isNotEmpty) {
          checks['ruby']!.checked += annotations.length;
          final out = output[found].inlineRuby
              .map((r) => (r.start, r.length, r.annotation))
              .toList();
          if (annotations.length != out.length ||
              Iterable<int>.generate(
                annotations.length,
              ).any((i) => annotations[i] != out[i])) {
            checks['ruby']!.failed++;
            add(
              'ruby.metadata_mismatch',
              path,
              'simple_ruby_pair_ranges_or_annotations_differ',
              location: epubTraceLocation(node),
              counts: {'source': annotations.length, 'parsed': out.length},
            );
          }
        }
      }
    }
    final unmatched = [
      for (var i = 0; i < output.length; i++)
        if (!matched.contains(i) && blockText(output[i]).isNotEmpty) i,
    ];
    if (unmatched.isNotEmpty) {
      if (unknownTextBlocks == unknownBefore && !special) {
        checks['text']!.checked += unmatched.length;
        checks['text']!.failed += unmatched.length;
        add(
          'text.unexpected_output',
          path,
          'output_blocks_without_simple_source_correspondence',
          counts: {
            'blocks': unmatched.length,
            'outputCharacters': unmatched.fold<int>(
              0,
              (n, i) => n + blockText(output[i]).runes.length,
            ),
          },
        );
      } else {
        checks['text']!.unknown += unmatched.length;
        unknownTextBlocks += unmatched.length;
        add(
          'text.coverage',
          path,
          'output_blocks_without_reliable_source_correspondence',
          impact: 'audit_coverage',
          confidence: 'unknown',
          disposition: 'unknown',
          evidence: 'output_verified',
          counts: {'blocks': unmatched.length},
        );
      }
    }
    if (authoredBlanks > 0) {
      checks['whitespace']!.checked++;
      final actual = chapter.blocks
          .whereType<ParagraphBlock>()
          .where((b) => b.text.isEmpty && b.authoredGapEm != null)
          .length;
      if (actual < authoredBlanks) {
        checks['whitespace']!.failed++;
        add(
          'whitespace.authored_blank_missing',
          path,
          'explicit_blank_paragraph_instances_missing',
          counts: {'source': authoredBlanks, 'parsed': actual},
        );
      }
    }
    if (unknownTextBlocks > unknownBefore) {
      add(
        'text.coverage',
        path,
        'complex_block_correspondence_unknown',
        impact: 'audit_coverage',
        confidence: 'unknown',
        disposition: 'unknown',
        evidence: 'source_only',
        counts: {'blocks': unknownTextBlocks - unknownBefore},
      );
    }
  }

  void imageAudit(
    String path,
    dom.Document doc,
    Map<dom.Element, Map<String, String>> styles,
    ChapterContent chapter,
    String? presentation,
  ) {
    final expected = <String>[];
    for (final node in doc.body!.querySelectorAll('img,image')) {
      if (hidden(node, styles)) continue;
      var convertedNoteref = false;
      for (
        var ancestor = node.parent;
        ancestor != null;
        ancestor = ancestor.parent
      ) {
        // Prose consumes the icon at a visible a[href], even if its target is
        // unavailable. Fixed images and SVG presentation anchors bypass this
        // branch. Establish consumption from source/path, not emitted markers.
        if (pathFor(path) != 'fixed_image' &&
            epubNoteref(ancestor) &&
            !hidden(ancestor, styles) &&
            ancestor.attributes.containsKey('href') &&
            !(presentation != null &&
                ancestor.namespaceUri == 'http://www.w3.org/2000/svg')) {
          convertedNoteref = true;
          break;
        }
      }
      if (convertedNoteref) {
        add(
          'image.noteref_marker',
          path,
          'image_consumed_by_standard_note_marker',
          category: 'media',
          impact: 'information',
          disposition: 'policy_override',
          evidence: 'source_and_output_relationship',
          location: epubTraceLocation(node),
        );
        continue;
      }
      String? selected;
      var missing = false, unsupported = false, external = false;
      for (final href in epubImageCandidates(node).take(128)) {
        final ref = epubReference(path, href);
        if (ref == null) {
          external = true;
          continue;
        }
        if (!source.zip.entries.containsKey(ref.$1)) {
          missing = true;
          continue;
        }
        final bytes = source.zip.read(ref.$1);
        if (epubRasterMime(bytes) == null) {
          unsupported = true;
          continue;
        }
        selected = sha256.convert(bytes).toString();
        break;
      }
      checks['images']!.checked++;
      if (selected != null) {
        expected.add(selected);
        selectedResources.add(selected);
        selectedImages++;
      } else {
        final reason = unsupported
            ? 'unsupported_raster_signature'
            : missing
            ? 'candidate_resource_missing'
            : external
            ? 'external_image_blocked'
            : 'no_eligible_candidate';
        final policy = !missing && !unsupported;
        if (!policy) checks['images']!.failed++;
        add(
          'image.unusable',
          path,
          reason,
          category: 'media',
          impact: policy ? 'information' : 'content_integrity',
          disposition: policy
              ? 'security_filtered'
              : unsupported
              ? 'unsupported'
              : 'invalid_input',
          evidence: 'source_and_parser_boundary',
          location: epubTraceLocation(node),
        );
      }
    }
    final native = <String>[];
    for (final b in chapter.blocks) {
      if (b is ImageBlock) native.add(b.media.mediaId.split('/').last);
      for (final image in b.inlineImages) {
        native.add(image.media.mediaId.split('/').last);
      }
    }
    nativeImages += native.length;
    final sourceCounts = frequencies(expected),
        nativeCounts = frequencies(native);
    for (final e in sourceCounts.entries) {
      if ((nativeCounts[e.key] ?? 0) < e.value ||
          !parsed.media.containsKey(e.key)) {
        checks['images']!.failed++;
        add(
          'image.selected_instance_missing',
          path,
          'selected_visible_raster_not_in_native_output',
          category: 'media',
          counts: {
            'sourceInstances': e.value,
            'parsedInstances': nativeCounts[e.key] ?? 0,
            'resourceSha256': e.key,
          },
          count: parsed.media.containsKey(e.key)
              ? e.value - (nativeCounts[e.key] ?? 0)
              : e.value,
        );
      }
    }
    // Compare the native representation independently of any presentation.
    // Resource presence alone cannot establish the number of image instances.
    for (final e in nativeCounts.entries) {
      final sourceCount = sourceCounts[e.key] ?? 0;
      final extra = e.value - sourceCount;
      if (extra <= 0) continue;
      checks['images']!.checked += extra;
      checks['images']!.failed += extra;
      add(
        'image.unexpected_instance',
        path,
        'native_raster_instances_without_selected_source',
        category: 'media',
        count: extra,
        counts: {
          'sourceInstances': sourceCount,
          'parsedInstances': e.value,
          'resourceSha256': e.key,
        },
      );
    }
    if (sourceCounts.length == nativeCounts.length &&
        sourceCounts.entries.every((e) => nativeCounts[e.key] == e.value) &&
        jsonEncode(expected) != jsonEncode(native)) {
      checks['images']!.failed++;
      add(
        'image.instance_order_differs',
        path,
        'selected_raster_logical_order_differs',
        category: 'media',
        counts: {'source': expected.length, 'native': native.length},
      );
    }
    if (presentation != null) {
      final embedded = <String>[];
      final generated = html.parse(presentation);
      source.boundTree<dom.Node>(generated, (n) => n.nodes);
      for (final image in generated.querySelectorAll('img')) {
        final src = image.attributes['src'] ?? '';
        if (src.startsWith('data:image/') && src.contains(';base64,')) {
          embedded.add(
            sha256.convert(base64Decode(src.split(';base64,').last)).toString(),
          );
        }
      }
      presentationImages += embedded.length;
      final embeddedCounts = frequencies(embedded);
      if (embeddedCounts.length != sourceCounts.length ||
          sourceCounts.entries.any((e) => embeddedCounts[e.key] != e.value)) {
        checks['presentation']!.unknown++;
        add(
          'image.presentation_correspondence',
          path,
          'presentation_resource_instances_need_review',
          category: 'media',
          confidence: 'suspected',
          disposition: 'unknown',
          counts: {'source': expected.length, 'presentation': embedded.length},
        );
      }
    }
  }

  Map<String, int> frequencies(Iterable<String> values) {
    final map = <String, int>{};
    for (final value in values) {
      map.update(value, (n) => n + 1, ifAbsent: () => 1);
    }
    return map;
  }

  void structureAudit(
    String path,
    dom.Document doc,
    Map<dom.Element, Map<String, String>> styles,
    ChapterContent chapter,
  ) {
    for (final node in doc.body!.querySelectorAll(
      'script,iframe,form,audio,video,svg,table',
    )) {
      final tag = node.localName!;
      checks['structures']!.checked++;
      if ({'script', 'iframe', 'audio', 'video'}.contains(tag)) {
        add(
          'dom.security_boundary',
          path,
          '${tag}_filtered',
          category: 'structure',
          impact: 'information',
          disposition: 'security_filtered',
          evidence: 'parser_decision',
          location: epubTraceLocation(node),
        );
      } else if (tag == 'form') {
        add(
          'dom.form_boundary',
          path,
          'form_interaction_not_executed',
          category: 'structure',
          impact: 'information',
          disposition: 'security_filtered',
          evidence: 'parser_decision',
          location: epubTraceLocation(node),
        );
      } else if (tag == 'table' && !hidden(node, styles)) {
        final count = chapter.blocks
            .whereType<ParagraphBlock>()
            .where((b) => b.tableRow != null)
            .length;
        add(
          'dom.table',
          path,
          count > 0
              ? 'native_rows_emitted_correspondence_partial'
              : 'table_flattened_to_text',
          category: 'structure',
          impact: 'layout',
          confidence: count > 0 ? 'suspected' : 'confirmed',
          disposition: count > 0 ? 'emitted_native' : 'degraded',
          evidence: 'output_verified',
          location: epubTraceLocation(node),
        );
      } else if (tag == 'svg') {
        add(
          'dom.svg',
          path,
          pathFor(path) == 'presentation'
              ? 'bounded_presentation_generated'
              : node.querySelector('image') != null
              ? 'raster_wrapper_native'
              : 'svg_geometry_not_verified',
          category: 'structure',
          impact: 'layout',
          confidence: node.querySelector('image') != null
              ? 'confirmed'
              : 'unknown',
          disposition: pathFor(path) == 'presentation'
              ? 'emitted_presentation'
              : node.querySelector('image') != null
              ? 'emitted_native'
              : 'unknown',
          evidence: 'parser_decision',
          location: epubTraceLocation(node),
        );
      }
    }
  }

  void sourceLinks(
    String path,
    dom.Document doc,
    Map<dom.Element, Map<String, String>> styles,
    ChapterContent chapter,
  ) {
    final available = <(String, int?, int?), List<LocalContentLink>>{};
    for (final link in parsed.content.links) {
      if (link.source != chapter.key) continue;
      (available[(
                link.sourceBlockKey,
                link.sourceOffset,
                link.sourceLength,
              )] ??=
              [])
          .add(link);
    }
    bool consume(
      (String, int?, int?) sourceRange,
      bool Function(LocalContentLink) matches,
    ) {
      final candidates = available[sourceRange] ?? [];
      for (var i = 0; i < candidates.length; i++) {
        if (matches(candidates[i])) {
          candidates.removeAt(i);
          return true;
        }
      }
      return false;
    }

    for (final a in doc.body!.querySelectorAll('a[href]')) {
      if (hidden(a, styles)) continue;
      final location = epubTraceLocation(a);
      (String, String?)? ref;
      try {
        ref = epubReference(path, a.attributes['href']!);
      } on FormatException {
        ref = null;
      }
      if (epubNoteref(a)) {
        if (ref == null) {
          checks['footnotes']!.unknown++;
          continue;
        }
        final targetDoc =
            docs[ref.$1] ??
            (source.zip.entries.containsKey(ref.$1)
                ? source.document(ref.$1)
                : null);
        final target = targetDoc
            ?.querySelectorAll('[id]')
            .where((n) => n.id == ref!.$2)
            .firstOrNull;
        final text = target != null && epubFootnote(target)
            ? epubFootnoteText(target)
            : null;
        if (text != null) {
          final range = sourceRanges[a];
          if (range == null) {
            checks['footnotes']!.unknown++;
            add(
              'footnote.relationship_unknown',
              path,
              'source_marker_range_not_reliably_mapped',
              category: 'links',
              impact: 'navigation',
              confidence: 'unknown',
              disposition: 'unknown',
              location: location,
            );
            continue;
          }
          checks['footnotes']!.checked++;
          if (!consume(
            (range.$1.blockKey, range.$2, null),
            (l) =>
                l.isFootnote &&
                l.source == chapter.key &&
                l.sourceBlockKey == range.$1.blockKey &&
                l.sourceOffset == range.$2 &&
                l.footnoteText == text,
          )) {
            checks['footnotes']!.failed++;
            add(
              'footnote.output_missing',
              path,
              'standard_note_marker_range_or_payload_missing',
              category: 'links',
              impact: 'navigation',
              location: location,
            );
          }
        } else {
          checks['footnotes']!.unknown++;
          add(
            'footnote.unavailable',
            path,
            'standard_note_target_unusable',
            category: 'links',
            impact: 'navigation',
            confidence: 'unknown',
            disposition: 'unknown',
            location: location,
          );
        }
        continue;
      }
      checks['links']!.checked++;
      if (ref == null) {
        add(
          'link.external_policy',
          path,
          'external_or_invalid_reference_not_followed',
          category: 'links',
          impact: 'information',
          disposition: 'security_filtered',
          evidence: 'parser_decision',
          location: location,
        );
        continue;
      }
      final target = chapterByPath[ref.$1] ?? parser.byPath[ref.$1];
      final exists = source.zip.entries.containsKey(ref.$1);
      final anchor = ref.$2?.isNotEmpty != true
          ? null
          : parser.fragments[ref.$1]?[ref.$2];
      if (target == null ||
          ![
            ...parsed.content.chapters,
            ...parsed.content.auxiliaryChapters,
          ].any((c) => c.key == target.key)) {
        checks['links']!.failed++;
        add(
          'link.target_unavailable',
          path,
          exists ? 'target_not_in_content_sets' : 'target_document_missing',
          category: 'links',
          impact: 'navigation',
          disposition: exists ? 'unsupported' : 'invalid_input',
          location: location,
        );
        continue;
      }
      if (ref.$2?.isNotEmpty == true &&
          (anchor == null ||
              !target.blocks.any((b) => b.blockKey == anchor.$1))) {
        checks['links']!.failed++;
        add(
          'link.fragment_unavailable',
          path,
          'fragment_has_no_emitted_block',
          category: 'links',
          impact: 'navigation',
          disposition: anchorIds[ref.$1]?.contains(ref.$2) == true
              ? 'unsupported'
              : 'invalid_input',
          confidence: anchorIds[ref.$1]?.contains(ref.$2) == true
              ? 'suspected'
              : 'confirmed',
          location: location,
        );
        continue;
      }
      final range = sourceRanges[a];
      if (range == null) {
        checks['links']!.unknown++;
        add(
          'link.relationship_unobserved',
          path,
          'valid_source_relationship_not_correlated',
          category: 'links',
          impact: 'navigation',
          confidence: 'unknown',
          disposition: 'unknown',
          location: location,
        );
      } else if (!consume(
        (range.$1.blockKey, range.$2, range.$3),
        (l) =>
            !l.isFootnote &&
            l.source == chapter.key &&
            l.sourceBlockKey == range.$1.blockKey &&
            l.sourceOffset == range.$2 &&
            l.sourceLength == range.$3 &&
            l.target == target.key &&
            l.targetBlockKey == anchor?.$1 &&
            l.targetOffset == anchor?.$2,
      )) {
        checks['links']!.failed++;
        add(
          'link.relationship_missing',
          path,
          'simple_source_range_or_target_range_missing',
          category: 'links',
          impact: 'navigation',
          location: location,
        );
      }
    }
  }

  void navigationTarget(String path, String href, String location) {
    checks['navigation']!.checked++;
    final ref = epubReference(path, href);
    final chapter = ref == null ? null : parser.byPath[ref.$1];
    final actual = chapter == null
        ? null
        : [
            ...parsed.content.chapters,
            ...parsed.content.auxiliaryChapters,
          ].where((c) => c.key == chapter.key).firstOrNull;
    final anchor = ref == null || ref.$2?.isNotEmpty != true
        ? null
        : parser.fragments[ref.$1]?[ref.$2];
    if (actual == null ||
        ref?.$2?.isNotEmpty == true &&
            (anchor == null ||
                !actual.blocks.any((b) => b.blockKey == anchor.$1))) {
      checks['navigation']!.failed++;
      add(
        'navigation.source_target_unavailable',
        path,
        actual == null
            ? 'navigation_document_target_unavailable'
            : 'navigation_fragment_unavailable',
        category: 'navigation',
        impact: 'navigation',
        disposition: 'invalid_input',
        location: location,
      );
    } else {
      bool emitted(LocalNavigationEntry e) =>
          e.chapterKey == actual.key &&
              (anchor == null || e.blockKey == anchor.$1) ||
          e.children.any(emitted);
      if (!parsed.content.navigation.any(emitted)) {
        checks['navigation']!.unknown++;
        add(
          'navigation.relationship_unobserved',
          path,
          'valid_source_target_not_correlated_with_output_navigation',
          category: 'navigation',
          impact: 'navigation',
          confidence: 'suspected',
          disposition: 'unknown',
          location: location,
        );
      }
    }
  }

  void auditNcx(String path) {
    final xml = source.xml(path);
    var i = 0;
    for (final content in xml.descendants.whereType<XmlElement>()) {
      if (content.name.local == 'content') {
        navigationTarget(
          path,
          content.getAttribute('src') ?? '',
          'ncx/content[${++i}]',
        );
      }
    }
  }

  void modelLinks() {
    final chapters = {
      for (final c in [
        ...parsed.content.chapters,
        ...parsed.content.auxiliaryChapters,
      ])
        c.key: c,
    };
    for (final link in parsed.content.links) {
      checks['links']!.checked++;
      final sourceChapter = chapters[link.source];
      final block = sourceChapter?.blocks
          .where((b) => b.blockKey == link.sourceBlockKey)
          .firstOrNull;
      final length = block == null ? 0 : blockText(block).runes.length;
      if (block == null ||
          link.sourceOffset != null &&
              link.sourceOffset! + (link.sourceLength ?? 0) > length) {
        checks['links']!.failed++;
        add(
          'link.source_invariant',
          parser.chapterPaths[link.source] ?? '',
          'source_block_or_codepoint_range_invalid',
          category: 'links',
          impact: 'navigation',
        );
      }
      final target = chapters[link.target];
      final targetBlock = target?.blocks
          .where((b) => b.blockKey == link.targetBlockKey)
          .firstOrNull;
      if (link.unavailable == null &&
          (target == null ||
              link.targetBlockKey != null &&
                  (targetBlock == null ||
                      (link.targetOffset ?? 0) >
                          blockText(targetBlock).runes.length))) {
        checks['links']!.failed++;
        add(
          'link.target_invariant',
          parser.chapterPaths[link.source] ?? '',
          'target_block_or_codepoint_offset_invalid',
          category: 'links',
          impact: 'navigation',
        );
      }
    }
    void visit(LocalNavigationEntry entry) {
      checks['navigation']!.checked++;
      final chapter = chapters[entry.chapterKey];
      if (chapter == null ||
          entry.blockKey != null &&
              !chapter.blocks.any((b) => b.blockKey == entry.blockKey)) {
        checks['navigation']!.failed++;
        add(
          'navigation.output_invariant',
          parser.chapterPaths[entry.chapterKey] ?? '',
          'output_navigation_target_missing',
          category: 'navigation',
          impact: 'navigation',
        );
      }
      for (final child in entry.children) {
        visit(child);
      }
    }

    for (final entry in parsed.content.navigation) {
      visit(entry);
    }
  }

  void cssAudit() {
    if (parser.trace == null) {
      checks['css']!.unknown++;
      return;
    }
    final blockEvents = events
        .where((e) => e['kind'] == 'block.output')
        .toList();
    final boxEvents = events.where((e) => e['kind'] == 'box.output').toList();
    for (final e in events) {
      final kind = e['kind'] as String, path = e['document'] as String;
      if (!kind.startsWith('css.') && kind != 'box.output') continue;
      checks['css']!.checked++;
      final reason = e['reason'] as String;
      String disposition = 'unknown',
          confidence = 'unknown',
          evidence = 'parser_decision',
          impact = 'audit_coverage',
          rule = 'css.coverage';
      final property = e['property'] as String?,
          value = e['value'] as String?,
          location = e['location'] as String?;
      final selected = pathFor(path);
      if (kind == 'box.output') {
        if (reason != 'nested_not_emitted') continue;
        disposition = 'degraded';
        confidence = 'confirmed';
        impact = 'layout';
        rule = 'box.nested_degraded';
        evidence = 'parser_decision';
      } else if (kind == 'css.source') {
        rule = 'css.declaration_inventory';
        disposition = 'not_applicable';
        confidence = 'confirmed';
        impact = 'information';
        evidence = 'source_only';
      } else if ({
        'unmatched',
        'print_not_applied',
        'import_print',
        'disabled',
        'alternate',
        'overridden',
        'overridden_important',
        'loaded',
      }.contains(reason)) {
        disposition = 'not_applicable';
        confidence = 'confirmed';
        impact = 'information';
        rule = 'css.inventory';
      } else if (kind == 'css.decision' &&
          reason == 'property_not_in_native_subset') {
        evidence = 'matched_candidate';
        confidence = 'suspected';
        impact =
            {
              'text-shadow',
              'box-shadow',
              'letter-spacing',
              'text-decoration',
            }.contains(property)
            ? 'decoration'
            : 'layout';
        rule = 'css.native_property_candidate';
        disposition = selected == 'presentation' ? 'unknown' : 'unsupported';
        if ({'font-family', 'line-height'}.contains(property)) {
          disposition = selected == 'presentation'
              ? 'unknown'
              : 'policy_override';
          impact = 'information';
        }
      } else if (reason == 'rejected_value') {
        rule = 'css.native_value_rejected';
        disposition = 'unsupported';
        // Rejection is observed, but unsupported syntax has no reconstructed
        // browser cascade. Its visual effect remains a matching candidate.
        confidence = 'suspected';
        impact = 'layout';
      } else if (kind == 'css.cascade') {
        rule = 'css.native_cascade';
        evidence = 'current_native_cascade';
        confidence = 'confirmed';
        impact = 'layout';
        final blockMatches = blockEvents
            .where(
              (b) =>
                  b['document'] == path &&
                  (b['location'] == location ||
                      location != null &&
                          location.startsWith('${b['location']}/')),
            )
            .toList();
        final decorated = blockMatches.any(
          (b) => (b['data'] as Map)['linkDecoration'] == true,
        );
        final boxes = boxEvents.any(
          (b) =>
              b['document'] == path &&
              b['location'] == location &&
              b['reason'] == 'emitted',
        );
        if (property == 'font-size' &&
            (location?.endsWith('body[1]') == true ||
                location?.endsWith('html[1]') == true)) {
          disposition = 'policy_override';
          impact = 'information';
        } else if (property == 'font-size' &&
            blockMatches.any(
              (b) =>
                  (b['data'] as Map)['fontSize'] == true ||
                  ((b['data'] as Map)['styleScales'] as List).any(
                    (scale) => scale is num && scale != 1,
                  ),
            )) {
          disposition = 'emitted_native';
          evidence = 'parser_and_output';
          rule = 'typography.native_metadata';
        } else if (property == 'border-radius') {
          final rounded = boxEvents.any(
            (b) =>
                b['document'] == path &&
                b['location'] == location &&
                b['reason'] == 'emitted' &&
                (b['data'] as Map?)?['radius'] == true,
          );
          impact = 'decoration';
          disposition = decorated || rounded ? 'emitted_native' : 'unsupported';
          evidence = 'parser_and_output';
          rule = rounded
              ? 'box.uniform_radius_metadata'
              : decorated
              ? 'link.decoration_conditional'
              : 'link.decoration_structure_unsupported';
        } else if (property?.startsWith('border-') == true &&
            property!.endsWith('-style') &&
            boxes &&
            {'inset', 'outset'}.contains(value)) {
          disposition = 'degraded';
          rule = 'box.border_style_approximation';
          evidence = 'parser_and_output';
        } else if (property?.startsWith('border') == true ||
            property?.startsWith('padding') == true ||
            property?.startsWith('margin') == true ||
            property == 'background-color' ||
            property == 'width' ||
            property == 'max-width') {
          disposition = boxes || decorated ? 'emitted_native' : 'unknown';
          evidence = boxes || decorated
              ? 'parser_and_output'
              : 'current_native_cascade';
          if (disposition == 'unknown') {
            confidence = 'suspected';
            rule = 'box.cascade_without_correlated_metadata';
            if (value != null &&
                RegExp(r'^0(?:px|em|rem|%)?$').hasMatch(value)) {
              disposition = 'not_applicable';
              confidence = 'confirmed';
              impact = 'information';
              rule = 'box.zero_geometry';
            } else if ({
                  'margin-top',
                  'margin-bottom',
                  'margin',
                }.contains(property) &&
                location != null &&
                RegExp(r'/p\[\d+\]$').hasMatch(location)) {
              disposition = 'policy_override';
              confidence = 'confirmed';
              impact = 'information';
              rule = 'paragraph.reader_spacing';
            } else if (blockMatches.any(
              (b) =>
                  (b['data'] as Map)['layout'] == true ||
                  (b['data'] as Map)['hanging'] == true ||
                  (b['data'] as Map)['label'] == true,
            )) {
              disposition = 'emitted_native';
              confidence = 'confirmed';
              evidence = 'parser_and_output';
              rule = 'paragraph.geometry_metadata';
            }
          }
        } else if (property == 'display' &&
                {
                  'flex',
                  'grid',
                  'inline-flex',
                  'inline-grid',
                }.contains(value) ||
            property == 'position' && {'absolute', 'fixed'}.contains(value) ||
            property == 'writing-mode' &&
                value?.startsWith('vertical') == true ||
            property == 'float' &&
                !{'none', 'initial', 'inherit', 'unset'}.contains(value)) {
          disposition = 'degraded';
          rule = 'layout.native_structure_candidate';
          confidence = 'suspected';
        } else {
          disposition = 'unknown';
          impact = 'information';
          rule = 'css.native_cascade_observed';
        }
      } else {
        checks['css']!.unknown++;
      }
      if (hiddenCssLocations.contains('$path:$location') ||
          {'unused', 'navigation', 'empty_skipped'}.contains(selected)) {
        disposition = 'not_applicable';
        confidence = 'confirmed';
        impact = 'information';
        rule = 'css.non_reading_content_inventory';
      }
      if (property == 'font-size' &&
          selected != 'presentation' &&
          (location?.endsWith('body[1]') == true ||
              location?.endsWith('html[1]') == true)) {
        disposition = 'policy_override';
        confidence = 'confirmed';
        impact = 'information';
        rule = 'typography.reader_root_policy';
      }
      if (selected == 'presentation' &&
          {'unsupported', 'degraded'}.contains(disposition)) {
        disposition = 'unknown';
        confidence = 'suspected';
        rule = 'css.presentation_runtime_unverified';
      }
      if (disposition == 'unknown' && impact != 'information') {
        checks['css']!.unknown++;
      }
      if ({'unsupported', 'degraded'}.contains(disposition)) {
        if (confidence == 'confirmed') {
          checks['css']!.failed++;
        } else {
          checks['css']!.unknown++;
        }
      }
      findings.add(
        rule,
        path,
        reason,
        category: 'css',
        impact: impact,
        confidence: confidence,
        disposition: disposition,
        evidence: evidence,
        path: selected,
        location: location,
        stylesheet: e['stylesheet'] as String?,
        ruleIndex: e['ruleIndex'] as int?,
        declarationIndex: e['declarationIndex'] as int?,
        property: property,
        value: value,
        definitionKey: property == null
            ? null
            : jsonEncode([
                sheetFingerprints['$path:${e['stylesheet']}'] ??
                    '${e['stylesheet']}:$location',
                e['ruleIndex'],
                e['declarationIndex'],
                property,
                value,
              ]),
        review: rule == 'link.decoration_conditional'
            ? 'Native decoration metadata emitted; over-height runtime fallback and pixels are not verified.'
            : rule,
      );
    }
  }
}
