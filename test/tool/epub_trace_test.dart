import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_trace.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'support/audit_fixture.dart';

void main() {
  final baseline =
      (jsonDecode(
                File(
                  'test/tool/support/parser_baseline.json',
                ).readAsStringSync(),
              )
              as Map)['fixtures']
          as Map;
  for (final fixture in baselineFixtures().entries) {
    for (final limit in [null, 100000, 1, 0]) {
      test('${fixture.key}: original baseline, trace capacity $limit', () {
        final trace = limit == null
            ? null
            : EpubTraceCollector(capacity: limit);
        // ZIP fixture encoder embeds the wall-clock timestamp. Pin the caller's
        // book identity to the original snapshot so byte-container timestamp
        // changes cannot masquerade as parser changes.
        final expected = baseline[fixture.key] as Map;
        final digest = expected['content'] == null
            ? '0' * 64
            : (jsonDecode((expected['content'] as Map)['detail'] as String)
                      as Map)['payload']['summary']['key']['novelId']
                  as String;
        final parser = EpubParser(
          fixture.value,
          LocalBookIdentity.book(digest),
          'synthetic.epub',
          includePresentations: true,
          trace: trace,
        );
        Map<String, Object?> snapshot;
        try {
          snapshot = parserSnapshot(parser);
        } on LocalParseException catch (e) {
          snapshot = {'rejected': e.problem.name};
        }
        expect(snapshot, baseline[fixture.key]);
        if (trace != null) {
          expect(trace.events.length, lessThanOrEqualTo(limit!));
        }
      });
    }
  }
  test('CSS trace values never expose author strings/URLs', () {
    for (final value in [
      'url(https://secret.example/?token=x)',
      '"private text"',
      'private-family',
      'var(--secret)',
    ]) {
      expect(traceCssValue(value), '[redacted]');
    }
    expect(traceCssValue('ridge groove none none'), 'ridge groove none none');
  });
}
