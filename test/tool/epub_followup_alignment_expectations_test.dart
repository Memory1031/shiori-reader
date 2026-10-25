import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import '../../tool/epub_audit/image_expectations.dart';
import '../../tool/epub_audit/audit.dart';
import 'support/audit_fixture.dart';

void main() {
  test(
    'independent SVG expectation distinguishes encoded and display axes',
    () {
      final doc = html.parse(
        '<html><body>'
        '<svg width="100%" height="100%" viewBox="0 0 200 80">'
        '<image width="200" height="80" href="image.jpg"/>'
        '</svg></body></html>',
      );
      final node = doc.querySelector('image')!;
      final known = sourceImageExpectation(
        node,
        {},
        80,
        200,
        displaySize: (width: 200, height: 80),
        displaySizeChecked: true,
      );
      expect(known['encodedNaturalSize'], {'width': 80, 'height': 200});
      expect(known['displayNaturalSize'], {'width': 200, 'height': 80});
      expect(known['expectedAlignment'], 'center');
      expect(known['alignmentBasis'], 'source_single_raster_svg_meet');
      final uncertain = sourceImageExpectation(
        node,
        {},
        80,
        200,
        displaySizeChecked: true,
      );
      expect(uncertain['expectedAlignment'], isNull);
      expect(uncertain['displayNaturalSize'], {'width': null, 'height': null});
    },
  );
  test('single-image policy is not reported as authored alignment', () {
    final doc = html.parse(
      '<html><body><div><p>'
      '<img src="image.png"/></p></div></body></html>',
    );
    final image = doc.querySelector('img')!;
    final inferred = sourceImageExpectation(image, {}, 80, 200);
    expect(inferred['expectedAlignment'], 'center');
    expect(inferred['alignmentBasis'], 'reader_single_image_document_default');
    final explicit = sourceImageExpectation(
      image,
      {
        doc.querySelector('p')!: {'text-align': 'right'},
      },
      80,
      200,
    );
    expect(explicit['expectedAlignment'], 'end');
    expect(explicit['alignmentBasis'], 'source_text_align');
    for (final body in [
      '<p>Text.</p><img src="a.png"/>',
      '<img src="a.png"/><img src="b.png"/>',
      '<p><br/></p><img src="a.png"/>',
      '<div style="float:left"><img src="a.png"/></div>',
    ]) {
      final d = html.parse('<html><body>$body</body></html>');
      final n = d.querySelector('img')!;
      final e = sourceImageExpectation(
        n,
        {
          if (body.contains('float'))
            d.querySelector('div')!: {'float': 'left'},
        },
        80,
        200,
      );
      expect(e['expectedAlignment'], isNull, reason: body);
    }
    final report = auditBytes(
      auditFixture(body: '<div><p><img src="../images/星 空.png"/></p></div>'),
    );
    final candidates = (report['readingLoss'] as Map)['candidates'] as List;
    expect(
      candidates.any((c) => c['rule'] == 'image.reader_default_alignment'),
      true,
    );
    expect(
      candidates.any((c) => c['rule'] == 'image.authored_alignment'),
      false,
    );
  });
}
