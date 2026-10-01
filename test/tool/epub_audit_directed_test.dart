import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:shiori/domain/models/models.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/report.dart';
import '../data/local/support/epub_fixtures.dart';
import 'epub_audit_test.dart' show changed, findings, traced;
import 'support/audit_fixture.dart';

Uint8List imageFixture(String body) {
  final files = epubFiles(toc: false);
  for (var i = 0; i < 3; i++) {
    final gif = base64Decode(
      'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
    );
    gif[13] = 60 * (i + 1); // Different valid one-pixel palette colours.
    files['OPS/images/${['a', 'b', 'c'][i]}.gif'] = gif;
  }
  files['OPS/text/a.xhtml'] = utf8.encode('<html><body>$body</body></html>');
  files['OPS/text/b.xhtml'] = utf8.encode(
    '<p>Other chapter.</p><img src="../images/c.gif"/>',
  );
  return zipFiles(files);
}

Json book(String hash, List<Json> observations, {bool complete = true}) => {
  'sha256': hash,
  'aliases': [hash],
  'status': 'parsed',
  'auditComplete': complete,
  'findings': observations,
};

void main() {
  group('visibility correspondence', () {
    for (final body in [
      '<p style="visibility:hidden">Hidden<span style="visibility:visible">Visible</span></p><p>Tail</p>',
      '<p style="visibility:collapse">Hidden<span style="visibility:inherit">Hidden<b style="visibility:initial">Visible</b></span></p><p>Tail</p>',
    ]) {
      test('hidden root still checks restored visible text: $body', () {
        final parser = traced(auditFixture(body: body));
        final original = parser.parse();
        expect(
          original.content.chapters.first.blocks
              .whereType<ParagraphBlock>()
              .map((b) => b.text),
          ['Visible', 'Tail'],
        );
        final report = auditParsed(parser, original);
        expect(findings(report, 'text.unexpected_output'), isEmpty);
        expect(findings(report, 'text.simple_block_mismatch'), isEmpty);
        expect(report['checks']['text']['status'], 'pass');
        expect(report['checks']['text']['unknown'], 0);
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
          findings(auditParsed(parser, altered), 'text.simple_block_mismatch'),
          hasLength(1),
        );
      });
    }
    test(
      'hidden inline text excluded while visible descendant and link ranges survive',
      () {
        final parser = traced(
          auditFixture(
            body:
                '<p>😀Before<span style="visibility:hidden">Hidden<b style="visibility:visible"><a href="b.xhtml#b">Visible</a></b></span>After</p>',
          ),
        );
        final original = parser.parse();
        expect(
          (original.content.chapters.first.blocks.first as ParagraphBlock).text,
          '😀BeforeVisibleAfter',
        );
        expect(original.content.links.single.sourceOffset, 7);
        expect(original.content.links.single.sourceLength, 7);
        final report = auditParsed(parser, original);
        expect(report['checks']['text']['status'], 'pass');
        expect(report['checks']['text']['unknown'], 0);
        expect(findings(report, 'link.relationship_missing'), isEmpty);
        expect(findings(report, 'link.relationship_unobserved'), isEmpty);
        final altered = changed(original, links: []);
        expect(
          findings(auditParsed(parser, altered), 'link.relationship_missing'),
          hasLength(1),
        );
      },
    );
    for (final attribute in ['style="display:none"', 'hidden']) {
      test(
        '$attribute excludes the entire subtree despite visible descendants',
        () {
          final parser = traced(
            auditFixture(
              body:
                  '<p $attribute>Hidden<span style="visibility:visible">Excluded</span></p><p>Tail</p>',
            ),
          );
          final original = parser.parse();
          expect(
            original.content.chapters.first.blocks
                .whereType<ParagraphBlock>()
                .map((b) => b.text),
            ['Tail'],
          );
          final report = auditParsed(parser, original);
          expect(report['checks']['text']['status'], 'pass');
          expect(report['checks']['text']['unknown'], 0);
        },
      );
    }
  });

  group('bidirectional image instances', () {
    const pair = '<img src="../images/a.gif"/><img src="../images/b.gif"/>';
    test('correct A B and a legal repeated A are preserved', () {
      for (final body in [pair, '<img src="../images/a.gif"/>$pair']) {
        final parser = traced(imageFixture(body));
        final original = parser.parse();
        final report = auditParsed(parser, original);
        expect(report['checks']['images']['status'], 'pass');
        expect(report['checks']['images']['unknown'], 0);
        expect(
          report['metrics']['selectedVisibleImageInstances'],
          body == pair ? 3 : 4,
        );
        expect(report['metrics']['nativeImageInstances'], body == pair ? 3 : 4);
        expect(report['metrics']['selectedUniqueResources'], 3);
      }
    });
    for (final extraResource in [false, true]) {
      test(
        'detects ${extraResource ? 'another resource' : 'duplicate ImageBlock'} without changing the resource table',
        () {
          final parser = traced(imageFixture(pair));
          final original = parser.parse();
          final chapter = original.content.chapters.first;
          final extra = extraResource
              ? original.content.chapters.last.blocks
                    .whereType<ImageBlock>()
                    .single
              : chapter.blocks.first;
          final altered = changed(
            original,
            chapters: [
              ChapterContent(
                key: chapter.key,
                title: chapter.title,
                blocks: [
                  chapter.blocks.first,
                  extra,
                  ...chapter.blocks.skip(1),
                ],
              ),
              ...original.content.chapters.skip(1),
            ],
          );
          expect(identical(altered.media, original.media), true);
          final report = auditParsed(parser, altered);
          final failure = findings(report, 'image.unexpected_instance').single;
          expect(failure['occurrences'], 1);
          expect(failure['counts']['sourceInstances'], extraResource ? 0 : 1);
          expect(failure['counts']['parsedInstances'], extraResource ? 1 : 2);
          expect(
            failure['counts']['resourceSha256'],
            matches(RegExp(r'^[a-f0-9]{64}$')),
          );
          expect(report['checks']['images']['status'], 'fail');
          expect(report['checks']['images']['failed'], 1);
          expect(report['checks']['images']['unknown'], 0);
        },
      );
    }
    test('no source images still rejects an unmatched output image', () {
      final parser = traced(imageFixture('<p>Plain.</p>'));
      final original = parser.parse();
      final chapter = original.content.chapters.first;
      final extra = original.content.chapters.last.blocks
          .whereType<ImageBlock>()
          .single;
      final report = auditParsed(
        parser,
        changed(
          original,
          chapters: [
            ChapterContent(
              key: chapter.key,
              title: chapter.title,
              blocks: [...chapter.blocks, extra],
            ),
            ...original.content.chapters.skip(1),
          ],
        ),
      );
      expect(
        findings(
          report,
          'image.unexpected_instance',
        ).single['counts']['sourceInstances'],
        0,
      );
      expect(report['checks']['images']['status'], 'fail');
    });
    for (final extraResource in [false, true]) {
      test(
        'detects an extra ${extraResource ? 'foreign' : 'duplicate'} inline image',
        () {
          final parser = traced(
            imageFixture(
              '<p>😀<img src="../images/a.gif" style="height:1em"/>Tail</p>',
            ),
          );
          final original = parser.parse();
          final chapter = original.content.chapters.first;
          final paragraph = chapter.blocks.first as ParagraphBlock;
          final oldImage = paragraph.inlineImages.single;
          final media = extraResource
              ? original.content.chapters.last.blocks
                    .whereType<ImageBlock>()
                    .single
                    .media
              : oldImage.media;
          final extra = ParagraphBlock(
            text: '${paragraph.text}\uFFFC',
            inlineImages: [
              oldImage,
              InlineImage(
                offset: paragraph.text.runes.length,
                media: media,
                widthEm: 1,
                heightEm: 1,
              ),
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
                  blocks: [extra],
                ),
                ...original.content.chapters.skip(1),
              ],
            ),
          );
          expect(
            findings(report, 'image.unexpected_instance').single['occurrences'],
            1,
          );
          expect(report['checks']['images']['status'], 'fail');
          expect(report['checks']['images']['unknown'], 0);
        },
      );
    }
    test('missing and same-count reordered images still fail', () {
      final parser = traced(imageFixture(pair));
      final original = parser.parse();
      final chapter = original.content.chapters.first;
      for (final reverse in [false, true]) {
        final report = auditParsed(
          parser,
          changed(
            original,
            chapters: [
              ChapterContent(
                key: chapter.key,
                title: chapter.title,
                blocks: reverse
                    ? chapter.blocks.reversed
                    : chapter.blocks.skip(1),
              ),
              ...original.content.chapters.skip(1),
            ],
          ),
        );
        expect(
          findings(
            report,
            reverse
                ? 'image.instance_order_differs'
                : 'image.selected_instance_missing',
          ),
          hasLength(1),
        );
        expect(report['checks']['images']['status'], 'fail');
      }
    });
    test('SVG raster wrapper is one source and one native representation', () {
      final report = auditBytes(
        imageFixture(
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><image href="../images/a.gif" width="1" height="1"/></svg>',
        ),
      );
      expect(report['checks']['images']['status'], 'pass');
      expect(report['metrics']['selectedVisibleImageInstances'], 2);
      expect(report['metrics']['nativeImageInstances'], 2);
      expect(findings(report, 'image.unexpected_instance'), isEmpty);
    });
  });

  group('support observations and candidate tiers', () {
    List<Json> observations() {
      final f = FindingCollector(20);
      for (final property in ['font-size', 'margin-left']) {
        for (final document in ['a.xhtml', 'b.xhtml']) {
          f.add(
            'preserved.$property',
            document,
            'metadata_preserved',
            property: property,
            category: 'css',
            impact: 'layout',
            confidence: 'confirmed',
            disposition: 'emitted_native',
            evidence: 'parser_and_output',
          );
        }
      }
      f.add(
        'box.degraded',
        'a.xhtml',
        'approximation',
        impact: 'layout',
        confidence: 'confirmed',
        disposition: 'degraded',
      );
      f.add(
        'text.missing',
        'a.xhtml',
        'missing',
        impact: 'content_integrity',
        confidence: 'confirmed',
        disposition: 'degraded',
      );
      f.add(
        'box.uncorrelated',
        'a.xhtml',
        'not_correlated',
        impact: 'layout',
        confidence: 'suspected',
        disposition: 'unknown',
        evidence: 'current_native_cascade',
      );
      f.add(
        'object.output',
        'a.xhtml',
        'property_unverified',
        impact: 'layout',
        confidence: 'unknown',
        disposition: 'emitted_native',
        evidence: 'parser_decision',
      );
      for (final disposition in [
        'policy_override',
        'security_filtered',
        'not_applicable',
      ]) {
        f.add(
          'policy.$disposition',
          'a.xhtml',
          'policy',
          impact: 'layout',
          confidence: 'confirmed',
          disposition: disposition,
        );
      }
      return f.findings;
    }

    test(
      'confirmed support moves to information while degradation and uncertainty remain candidates',
      () {
        final aggregate = aggregateBooks([book('one', observations())]);
        for (final group in aggregate) {
          final rule = group['ruleId'] as String;
          if (rule.startsWith('preserved.') || rule.startsWith('policy.')) {
            expect(group['priorityTier'], 4, reason: rule);
          } else if (rule == 'box.degraded') {
            expect(group['priorityTier'], 1);
          } else if (rule == 'text.missing') {
            expect(group['priorityTier'], 0);
          } else {
            expect(group['priorityTier'], 2, reason: rule);
          }
        }
        expect(aggregate.first['ruleId'], 'text.missing');
      },
    );
    test(
      'classification preserves all counts and lower bounds and renders the same JSON tiers',
      () {
        final source = observations();
        final books = [
          book('one', source),
          book('two', source),
          book('partial', [], complete: false),
        ];
        final aggregate = aggregateBooks(books);
        expect(aggregate, hasLength(source.length));
        for (final group in aggregate) {
          final original = source.singleWhere(
            (f) => f['ruleId'] == group['ruleId'],
          );
          expect(group['uniqueEpubs'], 2);
          expect(
            group['documents'],
            (original['documents'] as List).length * 2,
          );
          expect(group['occurrences'], original['occurrences'] * 2);
          expect(group['countAccuracy'], 'lower_bound');
          expect(group['declarationAccuracy'], 'lower_bound');
          expect(original['runtimeVerified'], false);
        }
        final markdown = reportMarkdown({
          'run': {
            'schemaVersion': schemaVersion,
            'auditRulesVersion': auditRulesVersion,
            'parserVersion': 19,
            'complete': true,
            'totalFiles': 3,
            'uniqueEpubs': 3,
            'duplicates': 0,
            'statuses': {'parsed': 3},
            'auditCompleteBooks': 2,
          },
          'aggregate': aggregate,
          'books': [],
        });
        for (final group in aggregate) {
          expect(
            markdown,
            contains(
              '| ${group['priorityTier']} | ${markdownEscape(group['ruleId'] as String)} /',
            ),
          );
        }
        expect(
          aggregate
              .where((g) => (g['ruleId'] as String).startsWith('preserved.'))
              .every((g) => g['priorityTier'] == 4),
          true,
        );
      },
    );
    test('actual retained font size and margin do not enter candidates', () {
      final report = auditBytes(
        auditFixture(
          body:
              '<div style="border:1px solid red;padding:1em;margin-left:2em"><p style="font-size:1.5em">Text.</p></div>',
        ),
      );
      final supported = (report['findings'] as List)
          .cast<Json>()
          .where(
            (f) =>
                ['font-size', 'margin-left'].contains(f['property']) &&
                f['confidence'] == 'confirmed' &&
                f['disposition'] == 'emitted_native',
          )
          .toList();
      expect(supported.map((f) => f['property']).toSet(), {
        'font-size',
        'margin-left',
      });
      expect(supported.every((f) => priorityTier(f) == 4), true);
      expect(supported.every((f) => f['runtimeVerified'] == false), true);
    });
  });
}
