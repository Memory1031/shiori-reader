import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/epub_audit/native_probe.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/replay.dart';
import 'support/audit_fixture.dart';

Future<RenderParagraph> paragraph(
  WidgetTester tester,
  String text, {
  bool decorated = false,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 90,
          child: RichText(
            textAlign: TextAlign.right,
            text: TextSpan(
              text: text,
              style: TextStyle(
                fontFamily: 'Ahem',
                fontSize: 20,
                height: 1,
                decoration: decorated ? TextDecoration.underline : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.renderObject<RenderParagraph>(find.byType(RichText));
}

void main() {
  testWidgets('only source-confirmed soft-wrap U+0020 is excluded', (
    tester,
  ) async {
    final render = await paragraph(tester, 'AAAA BBBB');
    final raw = nativeGeometryBoxes(render, collapsesOrdinarySpaces: false);
    expect(raw.boxes.any((b) => b.right > render.size.width + 1), isTrue);
    final measured = nativeGeometryBoxes(render, collapsesOrdinarySpaces: true);
    expect(measured.excludedSpaces, 1);
    expect(
      measured.boxes.every((b) => b.right <= render.size.width + 1),
      isTrue,
    );
    expect(raw.excludedSpaces, 0);
  });
  for (final text in [
    'AAAA\u00a0BBBB',
    'AAAA\u3000BBBB',
    'AAAA \nBBBB',
    'AAAA  BBBB',
    'AAAA ',
  ]) {
    testWidgets(
      'special or preserved whitespace remains checked: ${text.codeUnits}',
      (tester) async {
        final render = await paragraph(tester, text);
        final raw = nativeGeometryBoxes(render, collapsesOrdinarySpaces: false);
        final measured = nativeGeometryBoxes(
          render,
          collapsesOrdinarySpaces: true,
        );
        expect(measured.excludedSpaces, 0);
        expect(
          measured.boxes.map((b) => b.toRect()),
          raw.boxes.map((b) => b.toRect()),
        );
      },
    );
  }
  testWidgets('decorated spaces and real glyph overflow remain detectable', (
    tester,
  ) async {
    var render = await paragraph(tester, 'AAAA BBBB', decorated: true);
    var measured = nativeGeometryBoxes(render, collapsesOrdinarySpaces: true);
    expect(measured.excludedSpaces, 0);
    expect(measured.boxes.any((b) => b.right > render.size.width + 1), isTrue);
    render = await paragraph(tester, 'AAAA BBBB');
    measured = nativeGeometryBoxes(render, collapsesOrdinarySpaces: true);
    // A real Ahem letter occupies its glyph box. Narrowing the visible area
    // excludes painted letters, which must still fail after omitting U+0020.
    final visible = Rect.fromLTWH(
      0,
      0,
      render.size.width - 10,
      render.size.height,
    );
    expect(measured.excludedSpaces, 1);
    expect(
      measured.boxes.any((b) => !containsRect(visible, b.toRect())),
      isTrue,
    );
  });
  test(
    'source evidence conservatively rejects pre and inherited whitespace modes',
    () async {
      for (final (body, eligible) in [
        ('<p>AAAA BBBB</p>', true),
        ('<p><b>AAAA</b> BBBB</p>', true),
        ('<pre>AAAA BBBB</pre>', false),
        ('<p style="white-space:pre-wrap">AAAA BBBB</p>', false),
        ('<div style="white-space:pre"><p>AAAA BBBB</p></div>', false),
        ('<p><span style="white-space:pre">AAAA BBBB</span></p>', false),
      ]) {
        final book = await produce(auditFixture(body: body));
        final facts =
            ((auditParsed(book.parser, book.parsed)['readingLoss']
                        as Map)['sourceFacts']
                    as List)
                .where((f) => f['kind'] == 'text')
                .toList();
        expect(facts, isNotEmpty);
        expect(
          facts.first['details']['collapsesOrdinarySpaces'],
          eligible,
          reason: body,
        );
      }
    },
  );
}
