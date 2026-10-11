import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/reader_box.dart';
import '../../tool/epub_audit/native_probe.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/loss_report.dart';
import '../../tool/epub_audit/plan.dart';
import '../../tool/epub_audit/replay.dart';
import 'support/audit_fixture.dart';
import 'epub_audit_audio_test.dart' as audio;
import '../data/local/support/epub_fixtures.dart';
import '../data/local/support/synthetic_font.dart';

Future<ProducerSnapshot> probeBook(
  WidgetTester tester, {
  String? body,
  bool sound = false,
}) async => (await tester.runAsync(
  () => produce(
    sound
        ? audio.fixture(
            '<p style="border-radius:12px">Target.</p><audio controls src="../audio/test"/>',
          )
        : auditFixture(
            body:
                body ??
                '<p style="background-color:white;color:black;border:3px solid blue;border-radius:12px">Render identity.</p><p>Tail.</p>',
          ),
  ),
))!;
VerificationTarget targetFor(ProducerSnapshot snapshot, {int maxPages = 12}) {
  final candidate = bookCandidates(
    auditParsed(snapshot.parser, snapshot.parsed),
  ).first;
  final chapter = snapshot.parsed.content.chapters.first;
  return VerificationTarget(
    candidate,
    chapter.key.toJson(),
    chapter.blocks.first.blockKey,
    [ProbeConfiguration()],
    maxPages: maxPages,
  );
}

class SquareFaultPainter extends ReaderBoxPainter {
  SquareFaultPainter(ReaderBoxPainter original)
    : super(
        original.box,
        original.geometry,
        original.top,
        original.bottom,
        original.colors,
      );
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    canvas.drawRect(
      (Offset.zero & size).deflate(1.5),
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }
}

void main() {
  testWidgets(
    'wrapped Unicode text uses code point offsets when matching paint',
    (tester) async {
      final book = await probeBook(
        tester,
        body:
            '<p style="border-radius:12px">${'AB😀 CD ' * 80}</p><p>Tail.</p>',
      );
      final target = targetFor(book);
      final result = await runNativeProbe(
        tester,
        book,
        target,
        ProbeConfiguration(width: 500, height: 600, columns: 2),
      );
      expect(result['assertions']['characterIdentityFailures'], 0);
      expect(result['assertions']['reachedDocumentEnd'], true);
      expect(result['assertions']['restoreVisible'], true);
      expect(result['layers']['widget_geometry'], isNot('fail'));
    },
  );
  testWidgets(
    'embedded font bytes and rendered declaration are distinct from fallback glyph proof',
    (tester) async {
      final files = epubFiles();
      files['OPS/fonts/probe.ttf'] = syntheticFont(advance: 500);
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<html><head><style>@font-face{font-family:probe;src:url(../fonts/probe.ttf)}</style></head><body><p style="font-family:probe;border-radius:12px">ABAB</p><p>Tail.</p></body></html>',
      );
      final book = (await tester.runAsync(() => produce(zipFiles(files))))!;
      final target = targetFor(book);
      final good = await runNativeProbe(
        tester,
        book,
        target,
        target.configurations.first,
      );
      expect(
        good['assertions']['fonts']['resourceBytesSupplied'],
        greaterThan(0),
      );
      expect(
        good['assertions']['fonts']['allObservedDeclarationsOnSpan'],
        true,
      );
      expect(good['layers']['font_glyph'], 'unknown');
      final fallback = await runNativeProbe(
        tester,
        book,
        target,
        target.configurations.first,
        testOnlyMedia: ProbeMedia({}),
      );
      expect(fallback['assertions']['fonts']['resourceBytesSupplied'], 0);
      expect(fallback['layers']['font_glyph'], 'unknown');
      expect(fallback['assertions']['fonts']['glyphAttribution'], 'unknown');
    },
  );
  testWidgets(
    'rounded metadata with a square actual painter fails corner pixels',
    (tester) async {
      final book = await probeBook(tester), target = targetFor(book);
      final result = await runNativeProbe(
        tester,
        book,
        target,
        target.configurations.first,
        testOnlyTamper: (tester) async {
          for (final e in find.byType(CustomPaint).evaluate()) {
            final r = e.renderObject;
            if (r is RenderCustomPaint && r.painter is ReaderBoxPainter) {
              r.painter = SquareFaultPainter(r.painter! as ReaderBoxPainter);
            }
          }
          await tester.pump();
        },
      );
      expect(result['layers']['widget_geometry'], 'fail');
      expect(
        (result['assertions']['decorationPixels'] as List).any(
          (p) => p['status'] == 'fail',
        ),
        true,
      );
    },
  );
  testWidgets(
    'equal-length wrong painted characters fail independently of model',
    (tester) async {
      final book = await probeBook(tester), target = targetFor(book);
      final result = await runNativeProbe(
        tester,
        book,
        target,
        target.configurations.first,
        testOnlyTamper: (tester) async {
          final render = tester
              .renderObjectList<RenderParagraph>(find.byType(RichText))
              .firstWhere(
                (p) => p.text.toPlainText().contains('Render identity.'),
              );
          render.text = TextSpan(
            text: 'Render identitz.',
            style: render.text.style,
          );
          await tester.pump();
        },
      );
      expect(result['layers']['source_model'], 'fail');
      expect(result['assertions']['characterIdentityFailures'], greaterThan(0));
    },
  );
  testWidgets(
    'actual local background and foreground can expose unreadable text',
    (tester) async {
      final book = await probeBook(tester), target = targetFor(book);
      final result = await runNativeProbe(
        tester,
        book,
        target,
        target.configurations.first,
        testOnlyTamper: (tester) async {
          final render = tester
              .renderObjectList<RenderParagraph>(find.byType(RichText))
              .firstWhere(
                (p) => p.text.toPlainText().contains('Render identity.'),
              );
          render.text = TextSpan(
            text: render.text.toPlainText(),
            style: render.text.style?.copyWith(color: Colors.white),
          );
          await tester.pump();
        },
      );
      expect(result['layers']['widget_geometry'], 'fail');
      expect(result['assertions']['lowContrastFailures'], greaterThan(0));
    },
  );
  testWidgets('page budget is partial and restore must expose actual target', (
    tester,
  ) async {
    final body =
        '<p style="border-radius:12px">Target.</p>${List.generate(30, (i) => '<p>Self authored paragraph $i. ${'Long text. ' * 25}</p>').join()}';
    final book = await probeBook(tester, body: body),
        target = targetFor(book, maxPages: 1);
    final result = await runNativeProbe(
      tester,
      book,
      target,
      target.configurations.first,
      testOnlyAfterRestore: (tester) async {
        final viewport = tester.widget<PagedReaderViewport>(
          find.byType(PagedReaderViewport).first,
        );
        await viewport.controller.next();
        await tester.pumpAndSettle();
      },
    );
    expect(result['complete'], false);
    expect(result['assertions']['reachedDocumentEnd'], false);
    expect(result['assertions']['restoreVisible'], false);
    expect(result['layers']['widget_geometry'], 'fail');
  });
  testWidgets(
    'real audio hit test requests play once then stops and closes without decode claim',
    (tester) async {
      final book = await probeBook(tester, sound: true),
          target = targetFor(book);
      final result = await runNativeProbe(
        tester,
        book,
        target,
        target.configurations.first,
      );
      expect(result['layers']['control_routing'], 'pass');
      expect(result['assertions']['inputChecks'], 1);
      expect(result['assertions']['inputFailures'], 0);
      expect(result['assertions']['audioStops'], greaterThan(0));
      expect(result['assertions']['audioCloses'], 1);
      expect(result['layers']['audio_decode'], 'not_run');
    },
  );
  testWidgets(
    'Ruby mixed line and rounded painter pixels are measured on production components',
    (tester) async {
      final book = await probeBook(
        tester,
        body:
            '<p style="background-color:white;color:black;border:3px solid blue;border-radius:12px">Before <ruby>base<rt>annotation</rt></ruby> after.</p><p>Tail.</p>',
      );
      final target = targetFor(book);
      final result = await runNativeProbe(
        tester,
        book,
        target,
        target.configurations.first,
      );
      expect(result['assertions']['mixedLineChecks'], greaterThan(0));
      expect(
        (result['assertions']['decorationPixels'] as List).any(
          (p) => p['status'] == 'pass',
        ),
        true,
      );
      expect(result['assertions']['atomicFailures'], 0);
      expect(jsonEncode(result), isNot(contains('annotation')));
    },
  );
}
