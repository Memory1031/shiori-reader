import 'package:test/test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_trace.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import '../../tool/epub_audit/audit.dart';
import 'epub_audit_test.dart' show traced, findings;
import 'support/audit_fixture.dart';

void main() {
  test(
    'direct blank borders are emitted while deeper decoration stays degraded',
    () {
      final bytes = auditFixture(
        body:
            '<div style="width:14em"><p style="border-top:1px solid red"><br/></p>'
            '<div><p style="border-top:1px solid red"><br/></p></div>'
            '<p style="border-top:1px solid red">Text</p></div>',
      );
      final parser = traced(bytes);
      final parsed = parser.parse();
      final report = auditParsed(parser, parsed);
      final losses = findings(report, 'box.nested_degraded');
      expect(losses.fold<int>(0, (n, f) => n + (f['occurrences'] as int)), 2);
      expect(
        parser.trace!.events.any(
          (e) =>
              e['kind'] == 'box.output' &&
              e['location'] == 'html[1]/body[1]/div[1]/p[1]' &&
              e['reason'] == 'emitted',
        ),
        isTrue,
      );
      for (final capacity in [null, 0, 1]) {
        final other = EpubParser(
          bytes,
          LocalBookIdentity.book('a' * 64),
          'synthetic.epub',
          includePresentations: true,
          trace: capacity == null
              ? null
              : EpubTraceCollector(capacity: capacity),
        ).parse();
        expect(
          other.content.chapters.map((c) => c.toJson()),
          parsed.content.chapters.map((c) => c.toJson()),
        );
      }
    },
  );
  test(
    'bounded native border styles and uniform radius are support observations',
    () {
      final parser = traced(
        auditFixture(
          body: '<div class="frame"><p>Self authored frame.</p></div>',
          css:
              '.frame{border:6px ridge #4682b4;border-radius:12px;background-color:#383838}',
        ),
      );
      final report = auditParsed(parser, parser.parse());
      expect(findings(report, 'box.border_style_approximation'), isEmpty);
      expect(findings(report, 'box.uniform_radius_metadata'), isNotEmpty);
      expect(
        findings(
          report,
          'box.uniform_radius_metadata',
        ).every((f) => f['disposition'] == 'emitted_native'),
        isTrue,
      );
      final fallback = traced(
        auditFixture(
          body: '<div class="frame"><p>Self authored frame.</p></div>',
          css: '.frame{border:6px inset #4682b4}',
        ),
      );
      expect(
        findings(
          auditParsed(fallback, fallback.parse()),
          'box.border_style_approximation',
        ),
        isNotEmpty,
      );
    },
  );
}
