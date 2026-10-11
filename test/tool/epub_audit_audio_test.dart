import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart'
    show EpubParser, ParsedEpub;
import 'package:shiori/domain/contracts/local_books.dart';
import 'package:shiori/domain/models/models.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/report.dart';
import '../data/local/support/synthetic_audio.dart';
import '../data/local/support/epub_fixtures.dart';
import 'epub_audit_test.dart' show changed, findings, traced;

Uint8List fixture(
  String body, {
  String type = 'audio/wav',
  List<int>? bytes,
  bool tail = true,
}) {
  final files = epubFiles(toc: false);
  files['OPS/book.opf'] = utf8.encode(
    utf8
        .decode(files['OPS/book.opf']!)
        .replaceFirst(
          '</manifest>',
          '<item id="sound" href="audio/test" media-type="$type"/></manifest>',
        ),
  );
  files['OPS/audio/test'] = bytes ?? syntheticWav();
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><body>$body${tail ? '<p>Tail.</p>' : ''}</body></html>',
  );
  return zipFiles(files);
}

void main() {
  test('an omitted audio-only spine document is not empty content', () {
    final parser = traced(
      fixture('<audio controls src="../audio/test"></audio>', tail: false),
    );
    final parsed = parser.parse();
    expect(parsed.content.chapters.first.blocks.single, isA<AudioBlock>());
    final report = auditParsed(
      parser,
      changed(parsed, chapters: parsed.content.chapters.skip(1).toList()),
    );
    expect(findings(report, 'document.spine_omitted'), hasLength(1));
    expect(report['checks']['documents']['status'], 'fail');
    expect(findings(report, 'audio.control_missing'), hasLength(1));
    // An output-side empty-skip decision must not erase a source control.
    parser.skippedEmptyPaths.add('OPS/text/a.xhtml');
    final skipped = auditParsed(
      parser,
      changed(parsed, chapters: parsed.content.chapters.skip(1).toList()),
    );
    expect(findings(skipped, 'audio.control_missing'), hasLength(1));
    expect(skipped['checks']['structures']['status'], 'fail');
  });
  test('audio expectation remains independent with trace disabled', () {
    final parser = EpubParser(
      fixture('<audio controls src="../audio/test"></audio>'),
      LocalBookIdentity.book('a' * 64),
      'synthetic.epub',
      includePresentations: true,
    );
    final parsed = parser.parse(), chapter = parsed.content.chapters.first;
    expect(
      findings(auditParsed(parser, parsed), 'audio.native_control'),
      hasLength(1),
    );
    final altered = changed(
      parsed,
      chapters: [
        ChapterContent(
          key: chapter.key,
          title: chapter.title,
          blocks: chapter.blocks.where((b) => b is! AudioBlock),
        ),
        ...parsed.content.chapters.skip(1),
      ],
    );
    expect(
      findings(auditParsed(parser, altered), 'audio.control_missing'),
      hasLength(1),
    );
  });
  test(
    'legal repeated sources and extra output instances stay separate from resources',
    () {
      final repeated = traced(
        fixture(
          '<audio controls src="../audio/test"></audio>'
          '<audio controls src="../audio/test"></audio>',
        ),
      );
      final valid = auditParsed(repeated, repeated.parse());
      expect(valid['checks']['structures']['status'], 'pass');
      expect(findings(valid, 'audio.native_control').single['occurrences'], 2);
      final parser = traced(
        fixture('<audio controls src="../audio/test"></audio>'),
      );
      final parsed = parser.parse(), chapter = parsed.content.chapters.first;
      final altered = changed(
        parsed,
        chapters: [
          ChapterContent(
            key: chapter.key,
            title: chapter.title,
            blocks: [
              ...chapter.blocks,
              chapter.blocks.whereType<AudioBlock>().single,
            ],
          ),
          ...parsed.content.chapters.skip(1),
        ],
      );
      final failure = auditParsed(parser, altered);
      expect(findings(failure, 'audio.unexpected_control').single['counts'], {
        'source': 1,
        'native': 2,
      });
      expect(failure['checks']['structures']['status'], 'fail');
    },
  );
  for (final sample in [
    ('WAV', 'audio/wav', syntheticWav()),
    (
      'MP3 signature',
      'audio/mpeg',
      Uint8List.fromList([73, 68, 51, 4, 0, 0, 0, 0, 0, 0]),
    ),
  ]) {
    test(
      '${sample.$1} native audio metadata is support, runtime unverified',
      () {
        final parser = traced(
          fixture(
            '<audio controls aria-label="Private audio label" '
            'src="../audio/test"></audio>',
            type: sample.$2,
            bytes: sample.$3,
          ),
        );
        final parsed = parser.parse();
        final report = auditParsed(parser, parsed);
        final observation = findings(report, 'audio.native_control').single;
        expect(observation['disposition'], 'emitted_native');
        expect(observation['confidence'], 'confirmed');
        expect(observation['runtimeVerified'], false);
        expect(
          observation['counts']['hash'],
          parsed.content.chapters.first.blocks
              .whereType<AudioBlock>()
              .single
              .media!
              .mediaId
              .split('/')
              .last,
        );
        expect(priorityTier(observation), 4);
        expect(report['checks']['structures']['status'], 'pass');
        expect(report['checks']['runtime']['status'], 'unknown');
        expect(findings(report, 'dom.security_boundary'), isEmpty);
        expect(jsonEncode(report), isNot(contains('Private audio label')));
      },
    );
  }
  for (final sample in [
    ('missing', 'missing.wav', 'audio/wav', syntheticWav()),
    ('unsupported', '../audio/test', 'audio/ogg', syntheticWav()),
    (
      'external',
      'https://private.example/sound?secret=token',
      'audio/wav',
      syntheticWav(),
    ),
    (
      'unsupported',
      '../audio/test',
      'audio/wav',
      Uint8List.fromList([1, 2, 3]),
    ),
  ]) {
    test(
      '${sample.$1} audio retains a correctly unavailable native control',
      () {
        final parser = traced(
          fixture(
            '<audio controls src="${sample.$2}"></audio>',
            type: sample.$3,
            bytes: sample.$4,
          ),
        );
        final parsed = parser.parse();
        expect(
          parsed.content.chapters.first.blocks
              .whereType<AudioBlock>()
              .single
              .unavailable!
              .name,
          sample.$1,
        );
        final report = auditParsed(parser, parsed);
        expect(
          findings(report, 'audio.native_control').single['reason'],
          '${sample.$1}_unavailable_control_emitted',
        );
        expect(report['checks']['structures']['status'], 'pass');
        expect(findings(report, 'dom.security_boundary'), isEmpty);
        expect(jsonEncode(report), isNot(contains('private.example')));
      },
    );
  }
  for (final body in [
    '<audio src="../audio/test" autoplay></audio>',
    '<audio controls hidden src="../audio/test"></audio>',
    '<div hidden><audio controls src="../audio/test"></audio></div>',
    '<div style="display:none"><audio controls style="visibility:visible" src="../audio/test"></audio></div>',
    '<audio controls style="visibility:hidden" src="../audio/test"></audio>',
    '<aside role="doc-footnote"><audio controls src="../audio/test"></audio></aside>',
    '<p><a role="doc-noteref" href="#note"><audio controls src="../audio/test"></audio></a></p>',
  ]) {
    test('nonselected audio is informational: $body', () {
      final parser = traced(
        fixture(
          '<p style="transform:rotate(2deg)">Synthetic special page.</p>$body',
        ),
      );
      final parsed = parser.parse();
      expect(
        parsed.content.chapters.first.blocks.whereType<AudioBlock>(),
        isEmpty,
      );
      final report = auditParsed(parser, parsed);
      expect(findings(report, 'audio.not_selected'), hasLength(1));
      expect(
        findings(report, 'audio.not_selected').single['disposition'],
        'not_applicable',
      );
      expect(report['checks']['structures']['failed'], 0);
      expect(findings(report, 'dom.security_boundary'), isEmpty);
      expect(findings(report, 'audio.display_path_mismatch'), isEmpty);
    });
  }
  test('restored visibility and nonconsuming note semantics keep native audio', () {
    for (final body in [
      '<div style="visibility:hidden"><audio controls style="visibility:visible" src="../audio/test"></audio></div>',
      '<a role="doc-noteref" style="visibility:hidden" href="#note"><audio controls style="visibility:visible" src="../audio/test"></audio></a>',
      '<a role="doc-noteref"><audio controls src="../audio/test"></audio></a>',
    ]) {
      final parser = traced(fixture(body));
      final parsed = parser.parse();
      expect(
        parsed.content.chapters.first.blocks.whereType<AudioBlock>(),
        hasLength(1),
      );
      final report = auditParsed(parser, parsed);
      expect(findings(report, 'audio.native_control'), hasLength(1));
      expect(report['checks']['structures']['status'], 'pass');
    }
  });
  test(
    'source child fallback selects one control and the usable local candidate',
    () {
      final parser = traced(
        fixture(
          '<audio controls><source src="missing.wav"/>'
          '<source src="../audio/test"/><span>Fallback text.</span></audio>',
        ),
      );
      final report = auditParsed(parser, parser.parse());
      expect(findings(report, 'audio.native_control'), hasLength(1));
      expect(report['checks']['structures']['status'], 'pass');
    },
  );
  test(
    'removing an expected control fails even though trace records emission',
    () {
      final parser = traced(
        fixture('<audio controls src="../audio/test"></audio>'),
      );
      final parsed = parser.parse(), chapter = parsed.content.chapters.first;
      final altered = changed(
        parsed,
        chapters: [
          ChapterContent(
            key: chapter.key,
            title: chapter.title,
            blocks: chapter.blocks.where((b) => b is! AudioBlock),
          ),
          ...parsed.content.chapters.skip(1),
        ],
      );
      final report = auditParsed(parser, altered);
      expect(findings(report, 'audio.control_missing'), hasLength(1));
      expect(report['checks']['structures']['status'], 'fail');
    },
  );
  test(
    'wrong unavailable status and missing output resource fail metadata correspondence',
    () {
      final parser = traced(
        fixture('<audio controls src="../audio/test"></audio>'),
      );
      final parsed = parser.parse(), chapter = parsed.content.chapters.first;
      final altered = changed(
        parsed,
        chapters: [
          ChapterContent(
            key: chapter.key,
            title: chapter.title,
            blocks: [
              for (final block in chapter.blocks)
                if (block is AudioBlock)
                  AudioBlock(unavailable: AudioUnavailable.unsupported)
                else
                  block,
            ],
          ),
          ...parsed.content.chapters.skip(1),
        ],
      );
      expect(
        findings(
          auditParsed(parser, altered),
          'audio.control_metadata_mismatch',
        ),
        hasLength(1),
      );
      final missingMedia = ParsedEpub(parsed.content, {}, parsed.diagnostics);
      expect(
        findings(
          auditParsed(parser, missingMedia),
          'audio.control_metadata_mismatch',
        ),
        hasLength(1),
      );
    },
  );
  test(
    'native audio hidden by selected presentation fails the display path check',
    () {
      final parser = traced(
        fixture(
          '<p style="transform:rotate(2deg)">Synthetic special page.</p>'
          '<audio controls src="../audio/test"></audio>',
        ),
      );
      final parsed = parser.parse(), chapter = parsed.content.chapters.first;
      expect(parser.presentations, isEmpty);
      final normal = auditParsed(parser, parsed);
      // Only alter the output presentation descriptor, recreating the retired route bug.
      parser.presentations[chapter.key.chapterId] =
          '<html><body><p>Inert presentation.</p></body></html>';
      final report = auditParsed(parser, parsed);
      final failure = findings(report, 'audio.display_path_mismatch').single;
      expect(failure['processingPath'], 'presentation');
      expect(priorityTier(failure), 0);
      expect(failure['runtimeVerified'], false);
      expect(report['checks']['structures']['status'], 'fail');
      expect(findings(report, 'audio.native_control'), isEmpty);
      expect(findings(normal, 'audio.native_control'), hasLength(1));
    },
  );
  test('JSON and Markdown retain audio classification and coverage counts', () {
    final parser = traced(
      fixture(
        '<audio controls src="../audio/test"></audio>'
        '<audio controls src="missing.wav"></audio>',
      ),
    );
    final report = auditParsed(parser, parser.parse());
    final entry = {
      ...report,
      'sha256': 'a' * 64,
      'aliases': ['synthetic.epub'],
    };
    final aggregate = aggregateBooks([entry]);
    final audio = aggregate
        .where((f) => f['ruleId'] == 'audio.native_control')
        .toList();
    expect(audio, hasLength(2));
    expect(
      audio.every(
        (f) =>
            f['priorityTier'] == 4 &&
            f['uniqueEpubs'] == 1 &&
            f['documents'] == 1 &&
            f['occurrences'] == 1 &&
            f['countAccuracy'] == 'exact',
      ),
      true,
    );
    final markdown = reportMarkdown({
      'run': {
        'schemaVersion': schemaVersion,
        'auditRulesVersion': auditRulesVersion,
        'parserVersion': 27,
        'complete': true,
        'totalFiles': 1,
        'uniqueEpubs': 1,
        'duplicates': 0,
        'statuses': {'parsed': 1},
        'auditCompleteBooks': 1,
      },
      'aggregate': aggregate,
      'books': [entry],
    });
    expect(markdown, contains('audio.native\\_control'));
    expect(markdown, contains('missing\\_unavailable\\_control\\_emitted'));
    expect(markdown, isNot(contains('audio\\_filtered')));
    expect(markdown, contains('emitted_native'));
  });
  test('script iframe and video security observations remain unchanged', () {
    final parser = traced(
      fixture('<script>void 0;</script><iframe></iframe><video></video>'),
    );
    final report = auditParsed(parser, parser.parse());
    expect(
      findings(report, 'dom.security_boundary').map((f) => f['reason']),
      unorderedEquals(['script_filtered', 'iframe_filtered', 'video_filtered']),
    );
  });
}
