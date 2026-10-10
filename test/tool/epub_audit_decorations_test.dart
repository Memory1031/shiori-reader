import 'package:test/test.dart';
import '../../tool/epub_audit/audit.dart';
import 'epub_audit_test.dart' show traced, findings;
import 'support/audit_fixture.dart';

void main() {
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
