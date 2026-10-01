import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_trace.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'package:shiori/domain/contracts/local_content_links.dart';
import 'package:shiori/domain/models/models.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/report.dart';
import 'support/audit_fixture.dart';
import '../data/local/support/epub_fixtures.dart';

List<Json> findings(Json report, String rule) => (report['findings'] as List)
    .cast<Json>()
    .where((f) => f['ruleId'] == rule)
    .toList();
EpubParser traced(Uint8List bytes) => EpubParser(
  bytes,
  LocalBookIdentity.book('a' * 64),
  'synthetic.epub',
  includePresentations: true,
  trace: EpubTraceCollector(),
);
ParsedEpub changed(
  ParsedEpub old, {
  List<ChapterContent>? chapters,
  List<LocalContentLink>? links,
}) => ParsedEpub(
  LocalBookContent(
    detail: old.content.detail,
    catalog: old.content.catalog,
    chapters: chapters ?? old.content.chapters,
    auxiliaryChapters: old.content.auxiliaryChapters,
    navigation: old.content.navigation,
    links: links ?? old.content.links,
    readingOrder: old.content.readingOrder,
  ),
  old.media,
  old.diagnostics,
);

void main() {
  test('nontext source outside p scopes inline image output as unknown', () {
    final report = auditBytes(
      auditFixture(
        body:
            '<p>Plain.</p><div><img src="../images/星 空.png" style="height:1em"/></div>',
      ),
    );
    expect(findings(report, 'text.unexpected_output'), isEmpty);
    expect(
      findings(
        report,
        'text.coverage',
      ).any((f) => f['reason'] == 'nontext_source_outside_simple_roots'),
      true,
    );
    expect(findings(report, 'image.selected_instance_missing'), isEmpty);
  });
  test('authored NBSP and wide space blank transformations remain unknown', () {
    final report = auditBytes(
      auditFixture(body: '<p>\u3000</p><p>\u00a0</p><p>Plain.</p>'),
    );
    expect(findings(report, 'text.unexpected_output'), isEmpty);
    expect(findings(report, 'text.simple_block_mismatch'), isEmpty);
    expect((report['checks'] as Json)['text']['unknown'], greaterThan(0));
  });
  for (final body in [
    '<p><ruby>one<rt>first</rt></ruby> <ruby>two<rt>second</rt>three<rt>third</rt></ruby></p>',
    '<p><ruby>one<rt>first</rt>two<rt>second</rt></ruby></p>',
  ]) {
    test('every simple Ruby pair is checked: $body', () {
      final parser = traced(auditFixture(body: body));
      final original = parser.parse();
      final report = auditParsed(parser, original);
      expect(findings(report, 'ruby.metadata_mismatch'), isEmpty);
      final chapter = original.content.chapters.first;
      final block = chapter.blocks.first;
      final replacement = ParagraphBlock(
        text: (block as ParagraphBlock).text,
        inlineRuby: block.inlineRuby.take(block.inlineRuby.length - 1),
      );
      final altered = changed(
        original,
        chapters: [
          ChapterContent(
            key: chapter.key,
            title: chapter.title,
            blocks: [replacement, ...chapter.blocks.skip(1)],
          ),
          ...original.content.chapters.skip(1),
        ],
      );
      expect(
        findings(auditParsed(parser, altered), 'ruby.metadata_mismatch'),
        hasLength(1),
      );
    });
  }
  test('direct container text cannot silently escape coverage beside a p', () {
    final parser = traced(
      auditFixture(body: '<div>Direct visible text.</div><p>Paragraph.</p>'),
    );
    final original = parser.parse();
    final chapter = original.content.chapters.first;
    final altered = changed(
      original,
      chapters: [
        ChapterContent(
          key: chapter.key,
          title: chapter.title,
          blocks: chapter.blocks.skip(1),
        ),
        ...original.content.chapters.skip(1),
      ],
    );
    expect(
      (auditParsed(parser, altered)['checks'] as Json)['text']['unknown'],
      greaterThan(0),
    );
  });
  for (final duplicate in [true, false]) {
    test(
      'fully simple document detects ${duplicate ? 'duplicated' : 'inserted'} output',
      () {
        final parser = traced(auditFixture(body: '<p>Alpha.</p><p>Beta.</p>'));
        final original = parser.parse();
        final chapter = original.content.chapters.first;
        final extra = duplicate
            ? chapter.blocks.first
            : ParagraphBlock(text: 'Inserted output.');
        final altered = changed(
          original,
          chapters: [
            ChapterContent(
              key: chapter.key,
              title: chapter.title,
              blocks: [chapter.blocks.first, extra, ...chapter.blocks.skip(1)],
            ),
            ...original.content.chapters.skip(1),
          ],
        );
        expect(
          findings(auditParsed(parser, altered), 'text.unexpected_output'),
          hasLength(1),
        );
      },
    );
  }
  for (final note in [false, true]) {
    test(
      'two ${note ? 'footnotes' : 'links'} to one target cannot reuse a relation',
      () {
        final body = note
            ? '<p>First<a epub:type="noteref" href="#note">1</a> and second<a epub:type="noteref" href="#note">1</a>.</p><aside epub:type="footnote" id="note"><p>Same note.</p></aside>'
            : '<p><a href="b.xhtml#b">First</a> and <a href="b.xhtml#b">second</a>.</p>';
        final parser = traced(auditFixture(body: body));
        final original = parser.parse();
        final relations = original.content.links
            .where(
              (l) =>
                  l.source == original.content.chapters.first.key &&
                  l.isFootnote == note,
            )
            .toList();
        expect(relations, hasLength(2));
        expect(
          findings(
            auditParsed(parser, original),
            note ? 'footnote.output_missing' : 'link.relationship_missing',
          ),
          isEmpty,
        );
        final altered = changed(
          original,
          links: original.content.links
              .where((l) => !identical(l, relations.last))
              .toList(),
        );
        expect(
          findings(
            auditParsed(parser, altered),
            note ? 'footnote.output_missing' : 'link.relationship_missing',
          ),
          hasLength(1),
        );
      },
    );
  }
  test(
    'distinct fragments in one target block require distinct target offsets',
    () {
      final files = epubFiles(toc: false);
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<p><a href="b.xhtml#first">First</a> <a href="b.xhtml#second">Second</a></p>',
      );
      files['OPS/text/b.xhtml'] = utf8.encode(
        '<p><span id="first">Alpha</span> <span id="second">Beta</span></p>',
      );
      final parser = traced(zipFiles(files));
      final original = parser.parse();
      final relations = original.content.links
          .where((l) => l.source == original.content.chapters.first.key)
          .toList();
      expect(relations, hasLength(2));
      expect(relations[0].targetBlockKey, relations[1].targetBlockKey);
      expect(relations[0].targetOffset, isNot(relations[1].targetOffset));
      final altered = changed(
        original,
        links: original.content.links
            .map(
              (l) => identical(l, relations.last)
                  ? LocalContentLink.fromJson({
                      ...l.toJson(),
                      'targetOffset': relations.first.targetOffset,
                    })
                  : l,
            )
            .toList(),
      );
      expect(
        findings(auditParsed(parser, altered), 'link.relationship_missing'),
        hasLength(1),
      );
    },
  );
  test('identical link labels use Unicode code point source ranges', () {
    final parser = traced(
      auditFixture(
        body:
            '<p>😀 <a href="b.xhtml#b">Same</a> and <a href="b.xhtml#b"><b>Same</b></a>.</p>',
      ),
    );
    final original = parser.parse();
    expect(
      findings(auditParsed(parser, original), 'link.relationship_missing'),
      isEmpty,
    );
    final relations = original.content.links
        .where((l) => l.source == original.content.chapters.first.key)
        .toList();
    expect(relations.first.sourceOffset, 2);
    final altered = changed(
      original,
      links: original.content.links
          .map(
            (l) => identical(l, relations.last)
                ? LocalContentLink.fromJson({
                    ...l.toJson(),
                    'sourceOffset': relations.first.sourceOffset,
                  })
                : l,
          )
          .toList(),
    );
    expect(
      findings(auditParsed(parser, altered), 'link.relationship_missing'),
      hasLength(1),
    );
  });
  test('links split across complex blocks remain explicitly unknown', () {
    final parser = traced(
      auditFixture(
        body: '<div><a href="b.xhtml#b"><p>First.</p><p>Second.</p></a></div>',
      ),
    );
    final original = parser.parse();
    final altered = changed(original, links: []);
    final report = auditParsed(parser, altered);
    expect(findings(report, 'link.relationship_missing'), isEmpty);
    expect(findings(report, 'link.relationship_unobserved'), hasLength(1));
    expect((report['checks'] as Json)['links']['unknown'], greaterThan(0));
  });
  test('partial documents scope unmatched output as unknown', () {
    final parser = traced(
      auditFixture(body: '<div>Direct.</div><p>Simple.</p>'),
    );
    final original = parser.parse();
    final report = auditParsed(parser, original);
    expect(findings(report, 'text.unexpected_output'), isEmpty);
    expect(
      findings(report, 'text.coverage').any(
        (f) =>
            f['reason'] ==
            'output_blocks_without_reliable_source_correspondence',
      ),
      true,
    );
  });
  test('Ruby ranges matter even when every annotation remains present', () {
    final parser = traced(
      auditFixture(
        body: '<p>XX <ruby>one<rt>first</rt>two<rt>second</rt></ruby></p>',
      ),
    );
    final original = parser.parse();
    final chapter = original.content.chapters.first;
    final block = chapter.blocks.first as ParagraphBlock;
    final replacement = ParagraphBlock(
      text: block.text,
      inlineRuby: [
        InlineRuby(
          start: block.inlineRuby.first.start - 1,
          length: block.inlineRuby.first.length,
          annotation: block.inlineRuby.first.annotation,
        ),
        ...block.inlineRuby.skip(1),
      ],
    );
    final report = auditParsed(
      parser,
      changed(
        original,
        chapters: [
          ChapterContent(
            key: chapter.key,
            title: chapter.title,
            blocks: [replacement],
          ),
          ...original.content.chapters.skip(1),
        ],
      ),
    );
    expect(findings(report, 'ruby.metadata_mismatch'), hasLength(1));
  });
  test('unseen trace tail makes every corpus aggregate a lower bound', () {
    final f = FindingCollector(10)..add('sample', 'one.xhtml', 'candidate');
    final groups = aggregateBooks([
      {
        'sha256': 'complete',
        'aliases': ['complete'],
        'status': 'parsed',
        'auditComplete': true,
        'findings': f.findings,
      },
      {
        'sha256': 'partial',
        'aliases': ['partial'],
        'status': 'parsed',
        'auditComplete': false,
        'findings': <Json>[],
      },
    ]);
    expect(groups.single['countAccuracy'], 'lower_bound');
    expect(groups.single['declarationAccuracy'], 'lower_bound');
  });
  test(
    'fail with unknown coverage cannot prove an old observation disappeared',
    () {
      Json run(List<Json> observations, Json check) => {
        'run': {
          'schemaVersion': schemaVersion,
          'auditRulesVersion': auditRulesVersion,
          'optionsFingerprint': 'same',
        },
        'books': [
          {
            'sha256': 'same',
            'status': 'parsed',
            'auditComplete': true,
            'findings': observations,
            'checks': {'text': check},
          },
        ],
      };
      final old = FindingCollector(10)..add('text.old', 'a.xhtml', 'missing');
      final current = FindingCollector(10)
        ..add('text.new', 'b.xhtml', 'missing');
      final diff = compareReports(
        run(old.findings, {
          'status': 'fail',
          'checked': 2,
          'failed': 1,
          'unknown': 0,
        }),
        run(current.findings, {
          'status': 'fail',
          'checked': 1,
          'failed': 1,
          'unknown': 1,
        }),
      );
      final changes = (diff['changes'] as List).cast<Json>();
      expect(
        changes.singleWhere((c) => c['ruleId'] == 'text.old')['kind'],
        'unknown_due_to_coverage',
      );
      final coverage = changes.singleWhere(
        (c) => c['kind'] == 'check_coverage_changed',
      );
      expect(coverage['check'], 'text');
      expect(coverage['before']['unknown'], 0);
      expect(coverage['after']['unknown'], 1);
    },
  );
  test(
    'rejected native values do not prove effective browser cascade loss',
    () {
      final r = auditBytes(
        auditFixture(
          body: '<p>Text.</p>',
          css: 'p{font-size:2rem}p{font-size:large}',
        ),
      );
      expect(findings(r, 'css.native_value_rejected'), isNotEmpty);
      expect(
        findings(
          r,
          'css.native_value_rejected',
        ).every((f) => f['confidence'] == 'suspected'),
        true,
      );
    },
  );
  test(
    'CSS uses aggregate documents and deduplicates declaration identities',
    () {
      final f = FindingCollector(10);
      for (final document in ['a.xhtml', 'b.xhtml']) {
        f.add(
          'css.sample',
          document,
          'candidate',
          definitionKey: 'same CSS declaration',
        );
      }
      final book = {
        'sha256': 'same',
        'status': 'parsed',
        'auditComplete': true,
        'aliases': ['sample'],
        'findings': f.findings,
      };
      expect(f.findings, hasLength(1));
      expect(f.findings.single['documents'], ['a.xhtml', 'b.xhtml']);
      final group = aggregateBooks([book]).single;
      expect(group['occurrences'], 2);
      expect(group['declarations'], 1);
      expect(group['documents'], 2);
    },
  );
  test(
    'compare groups path variants and treats missing checks conservatively',
    () {
      final f = FindingCollector(10)
        ..add('text.missing', 'a.xhtml', 'missing', category: 'content')
        ..add(
          'text.missing',
          'a.xhtml',
          'missing',
          category: 'content',
          path: 'presentation',
        );
      Json run(
        List<Json> findings, {
        String code = 'one',
        Json checks = const {},
      }) => {
        'run': {
          'schemaVersion': 1,
          'auditRulesVersion': auditRulesVersion,
          'auditCodeFingerprint': code,
          'optionsFingerprint': 'same',
        },
        'books': [
          {
            'sha256': 'same',
            'status': 'parsed',
            'auditComplete': true,
            'findings': findings,
            'checks': checks,
          },
        ],
      };
      expect(
        compareReports(
          run(f.findings),
          run(f.findings, code: 'two'),
        )['comparable'],
        false,
      );
      final diff = compareReports(run(f.findings), run([f.findings.first]));
      expect((diff['changes'] as List).single['kind'], 'observation_changed');
      expect(
        (compareReports(run(f.findings), run([]))['changes'] as List)
            .single['kind'],
        'unknown_due_to_coverage',
      );
      expect(
        (compareReports(
                  run(f.findings),
                  run(
                    [],
                    checks: {
                      'text': {
                        'status': 'pass',
                        'checked': 2,
                        'failed': 0,
                        'unknown': 0,
                      },
                    },
                  ),
                )['changes']
                as List)
            .singleWhere((c) => c['ruleId'] == 'text.missing')['kind'],
        'no_longer_observed',
      );
    },
  );
  test(
    'formatted Ruby trailing source whitespace and noteref icons are transformations',
    () {
      final r = auditBytes(
        auditFixture(
          body:
              '<p>Before <ruby>base<rp>(</rp><rt>reading</rt><rp>)</rp>\n </ruby> after.</p><p>Note<a epub:type="noteref" href="#note"><img src="../images/星 空.png"/></a>.</p><aside epub:type="footnote" id="note"><p>Self authored note.</p></aside>',
        ),
      );
      expect(findings(r, 'text.simple_block_mismatch'), isEmpty);
      expect(findings(r, 'image.selected_instance_missing'), isEmpty);
      expect(findings(r, 'image.noteref_marker'), hasLength(1));
    },
  );
  test(
    'simple text, NBSP/pre/br, Ruby, standard notes and inline images have separate evidence',
    () {
      final r = auditBytes(auditFixture());
      expect(r['auditComplete'], true);
      for (final rule in [
        'text.simple_block_mismatch',
        'ruby.metadata_mismatch',
        'footnote.output_missing',
        'image.selected_instance_missing',
        'whitespace.authored_blank_missing',
      ]) {
        expect(findings(r, rule), isEmpty, reason: rule);
      }
      for (final check in ['ruby', 'footnotes', 'images', 'whitespace']) {
        expect((r['checks'] as Json)[check]['status'], 'pass', reason: check);
      }
      expect((r['checks'] as Json)['text']['unknown'], greaterThan(0));
      expect((r['checks'] as Json)['runtime']['status'], 'unknown');
    },
  );
  test(
    'deleting one simple output block is detected independently of trace',
    () {
      final p = traced(
        auditFixture(body: '<p id="one">Alpha block.</p><p>Beta block.</p>'),
      );
      final original = p.parse();
      final chapter = original.content.chapters.first;
      final replacement = ChapterContent(
        key: chapter.key,
        title: chapter.title,
        blocks: chapter.blocks.skip(1),
      );
      final r = auditParsed(
        p,
        changed(
          original,
          chapters: [replacement, ...original.content.chapters.skip(1)],
        ),
      );
      expect(findings(r, 'text.simple_block_mismatch'), hasLength(1));
      expect((r['checks'] as Json)['text']['status'], 'fail');
    },
  );
  test(
    'deleting a selected image instance despite resource presence is detected',
    () {
      final p = traced(
        auditFixture(
          body:
              '<p>Alpha.</p><img src="../images/星 空.png"/><img src="../images/星 空.png"/>',
        ),
      );
      final original = p.parse();
      final chapter = original.content.chapters.first;
      var removed = false;
      final replacement = ChapterContent(
        key: chapter.key,
        title: chapter.title,
        blocks: chapter.blocks.where((b) {
          if (!removed && b is ImageBlock) {
            removed = true;
            return false;
          }
          return true;
        }),
      );
      final r = auditParsed(
        p,
        changed(
          original,
          chapters: [replacement, ...original.content.chapters.skip(1)],
        ),
      );
      expect(findings(r, 'image.selected_instance_missing'), hasLength(1));
      expect((r['metrics'] as Json)['selectedVisibleImageInstances'], 2);
    },
  );
  test('removing a target anchor/block invalidates relations', () {
    final p = traced(
      auditFixture(body: '<p><a href="b.xhtml#b">Target</a></p>'),
    );
    final original = p.parse();
    final chapter = original.content.chapters.last;
    final replacement = ChapterContent(
      key: chapter.key,
      title: chapter.title,
      blocks: chapter.blocks.skip(1),
    );
    final r = auditParsed(
      p,
      changed(
        original,
        chapters: [original.content.chapters.first, replacement],
      ),
    );
    expect(findings(r, 'link.target_invariant'), isNotEmpty);
    expect(findings(r, 'link.fragment_unavailable'), isNotEmpty);
  });
  test(
    'nonempty spine omitted from all output is a confirmed coverage failure',
    () {
      final p = traced(auditFixture(body: '<p>Present source.</p>'));
      final original = p.parse();
      final r = auditParsed(
        p,
        changed(original, chapters: original.content.chapters.skip(1).toList()),
      );
      expect(findings(r, 'document.spine_omitted'), hasLength(1));
    },
  );
  test(
    'unmatched/print/disabled/alternate are inventory, complex conditions unknown',
    () {
      final r = auditBytes(
        auditFixture(
          body: '<p>Plain ① visual marker.</p>',
          css:
              '.absent{text-shadow:1px 1px red}@media print{p{box-shadow:1px 1px red}}@media (min-width:500px){p{position:absolute}}p::before{content:"SECRET"}',
          head:
              '<style disabled>p{transform:rotate(10deg)}</style><link rel="alternate stylesheet" href="bad.css"/>',
        ),
      );
      expect(
        findings(
          r,
          'css.native_property_candidate',
        ).where((f) => f['property'] == 'text-shadow'),
        isEmpty,
      );
      expect(findings(r, 'footnote.output_missing'), isEmpty);
      expect(findings(r, 'css.coverage'), isNotEmpty);
      expect((r['checks'] as Json)['css']['status'], 'unknown');
      expect(jsonEncode(r), isNot(contains('SECRET')));
    },
  );
  test(
    'actual cascade observes overwrite and important; keyword size is accepted',
    () {
      final r = auditBytes(
        auditFixture(
          body: '<p>Text.</p>',
          css:
              'p{font-size:large!important}p{font-size:small}p{color:red}p{color:blue}',
        ),
      );
      expect(findings(r, 'css.native_value_rejected'), isEmpty);
      expect(
        findings(
          r,
          'css.inventory',
        ).where((f) => f['reason'] == 'overridden_important'),
        isNotEmpty,
      );
      expect(
        findings(r, 'css.inventory').where((f) => f['reason'] == 'overridden'),
        isNotEmpty,
      );
    },
  );
  test('same border-radius differs for whole link and ordinary span', () {
    final r = auditBytes(
      auditFixture(
        body:
            '<p><a href="b.xhtml#b"><span class="label">Target</span></a></p><p>Ordinary <span class="label">text</span></p>',
        css: '.label{border-radius:8px;background-color:red;padding:1px}',
      ),
    );
    expect(findings(r, 'link.decoration_conditional'), isNotEmpty);
    expect(findings(r, 'link.decoration_structure_unsupported'), isNotEmpty);
  });
  test(
    'picture/srcset chooses one candidate, unused candidate is not missing',
    () {
      final r = auditBytes(
        auditFixture(
          body:
              '<p>Text.</p><picture><source srcset="../images/星%20空.png 1x"/><img src="not-selected.png" srcset="absent.png 2x"/></picture>',
        ),
      );
      expect(findings(r, 'image.unusable'), isEmpty);
      expect((r['metrics'] as Json)['selectedVisibleImageInstances'], 1);
    },
  );
  test('presentation and native fallback do not double count images', () {
    final r = auditBytes(
      auditFixture(
        body:
            '<div style="position:absolute"><p>Short text.</p><img src="../images/星 空.png"/></div>',
      ),
    );
    expect((r['metrics'] as Json)['selectedVisibleImageInstances'], 1);
    expect((r['metrics'] as Json)['nativeImageInstances'], 1);
    expect((r['metrics'] as Json)['presentationImageInstances'], 1);
    expect(findings(r, 'image.selected_instance_missing'), isEmpty);
  });
  test(
    'independent fallback, unused documents, linear=no and auxiliary link coverage',
    () {
      final files = epubFiles();
      files['OPS/book.opf'] = utf8.encode(
        '<package version="3.0"><manifest><item id="raw" href="raw.bin" media-type="application/unknown" fallback="a"/><item id="a" href="text/a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="text/b.xhtml" media-type="application/xhtml+xml"/><item id="extra" href="extra.xhtml" media-type="application/xhtml+xml"/><item id="unused" href="unused.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="raw" linear="no"/><itemref idref="b"/></spine></package>',
      );
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<p>Alpha <a href="../extra.xhtml#extra">aux</a></p>',
      );
      files['OPS/extra.xhtml'] = utf8.encode('<p id="extra">Auxiliary.</p>');
      files['OPS/unused.xhtml'] = utf8.encode('<p>Unused.</p>');
      final r = auditBytes(zipFiles(files));
      expect(findings(r, 'document.spine_omitted'), isEmpty);
      expect(findings(r, 'link.target_unavailable'), isEmpty);
      expect((r['documents'] as List).any((d) => d['auxiliary'] == true), true);
      expect(
        (r['documents'] as List).any((d) => d['processingPath'] == 'unused'),
        true,
      );
    },
  );
  test('imports use actual production path and preserve origin', () {
    final files = epubFiles();
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><head><link rel="stylesheet" href="../root.css"/></head><body><p>Text.</p></body></html>',
    );
    files['OPS/root.css'] = utf8.encode(
      '@import "import.css"; p{font-size:small}',
    );
    files['OPS/import.css'] = utf8.encode('p{font-size:large;color:red}');
    final r = auditBytes(zipFiles(files));
    expect(
      findings(r, 'css.inventory').any(
        (f) => (f['locations'] as List).any(
          (l) => l['stylesheet'] == 'OPS/import.css',
        ),
      ),
      true,
    );
  });
  test(
    'missing resource and unsupported signature differ; external URLs redacted',
    () {
      final r = auditBytes(
        auditFixture(
          body:
              '<p>PRIVATE_PROSE</p><img src="missing.png"/><img src="https://example.invalid/?token=PRIVATE_TOKEN"/>',
          css:
              'p{background-image:url(https://example.invalid/?token=PRIVATE_TOKEN)}',
        ),
      );
      final reasons = findings(
        r,
        'image.unusable',
      ).map((f) => f['reason']).toList();
      expect(reasons, contains('candidate_resource_missing'));
      expect(reasons, contains('external_image_blocked'));
      final report = jsonEncode(r);
      expect(report, isNot(contains('PRIVATE_PROSE')));
      expect(report, isNot(contains('PRIVATE_TOKEN')));
      expect(report, isNot(contains('base64')));
      expect(
        auditBytes(Uint8List.fromList([1, 2, 3]))['status'],
        'production_rejected',
      );
    },
  );
  test('trace/doc/findings budget yields explicit incomplete coverage', () {
    for (final options in [
      const AuditOptions(maxEvents: 1),
      const AuditOptions(maxDocuments: 1),
      const AuditOptions(maxFindings: 1),
    ]) {
      final r = auditBytes(auditFixture(), options: options);
      expect(r['auditComplete'], false);
      expect(r['truncationReasons'], isNotEmpty);
    }
  });
  test(
    'aggregation uses unique EPUB and distinct documents, ordered by impact',
    () {
      final f = FindingCollector(10)
        ..add(
          'text.missing',
          'a.xhtml',
          'missing',
          impact: 'content_integrity',
          confidence: 'confirmed',
          disposition: 'degraded',
        );
      f.add('shadow', 'a.xhtml', 'candidate', impact: 'decoration');
      f.add('shadow', 'b.xhtml', 'candidate', impact: 'decoration', count: 100);
      final book = {
        'sha256': 'a',
        'aliases': ['synthetic'],
        'status': 'parsed',
        'auditComplete': true,
        'findings': f.findings,
      };
      final a = aggregateBooks([book]);
      expect(a.first['ruleId'], 'text.missing');
      expect(a.last['uniqueEpubs'], 1);
      expect(a.last['documents'], 2);
    },
  );
  test(
    'comparison requires hash/rules/options and does not claim fixes under timeout',
    () {
      final f = FindingCollector(10)..add('text.missing', 'a.xhtml', 'missing');
      Json run(List<Json> books, {String rules = auditRulesVersion}) => {
        'run': {
          'schemaVersion': 1,
          'auditRulesVersion': rules,
          'optionsFingerprint': 'same',
        },
        'books': books,
      };
      final book = {
        'sha256': 'a',
        'status': 'parsed',
        'auditComplete': true,
        'findings': f.findings,
      };
      final timeout = {
        'sha256': 'a',
        'status': 'timeout',
        'auditComplete': false,
        'findings': <Json>[],
      };
      final diff = compareReports(run([book]), run([timeout]));
      expect(
        (diff['changes'] as List).any(
          (c) => c['kind'] == 'unknown_due_to_coverage',
        ),
        true,
      );
      expect(
        compareReports(run([book]), run([book], rules: '2'))['comparable'],
        false,
      );
      expect(
        compareReports(
          run([book]),
          run([
            {...book, 'sha256': 'b'},
          ]),
        )['matchedBooks'],
        0,
      );
    },
  );
}
