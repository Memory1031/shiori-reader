import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_inline_border.dart';
import 'package:shiori/features/reader/reader_inline_images.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_superscript.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import '../../data/local/epub_prose_semantics_test.dart' show paragraphs;
import 'local_search_test.dart' show fonts;
import 'search_highlight_test.dart' show screenshot;

void main() {
  testWidgets('border paint preserves shaping and fits wrapped last lines', (
    tester,
  ) async {
    await fonts(tester);
    for (final (width, height, scale) in [
      (168.0, 1.6, 1.0),
      (320.0, 1.2, 1.5),
      (320.0, 1.6, 1.0),
    ]) {
      final style = TextStyle(
        fontFamily: 'Roboto',
        fontSize: 28,
        height: height,
      );
      const prefix = '😀前文 ';
      const marked = '跨行强调文字，最后一行也保留点线。';
      final span = ReaderBorderSpan(
        text: marked,
        style: style,
        borderStyle: BoxBorderStyle.dotted,
        color: Colors.black,
        width: 2,
      );
      TextPainter layout(TextSpan content) => TextPainter(
        text: TextSpan(
          style: style,
          children: [
            const TextSpan(text: prefix),
            content,
          ],
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(scale),
      )..layout(maxWidth: width);
      final painter = layout(span);
      final legacy = layout(
        TextSpan(
          text: marked,
          style: style.copyWith(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            decorationThickness: 2,
          ),
        ),
      );
      try {
        expect(painter.size, legacy.size);
        final selection = const TextSelection(
          baseOffset: prefix.length,
          extentOffset: prefix.length + marked.length,
        );
        final boxes = painter.getBoxesForSelection(selection);
        expect(
          boxes.map((b) => b.toRect()).toList(),
          legacy
              .getBoxesForSelection(selection)
              .map((b) => b.toRect())
              .toList(),
        );
        final strokes = readerBorderStrokes(
          painter.text!,
          painter.textScaler,
          painter.size,
          painter.getBoxesForSelection,
        );
        expect(strokes.length, boxes.length);
        expect(strokes.length, greaterThan(1));
        for (var i = 0; i < strokes.length; i++) {
          final rect = strokes[i].rect;
          expect(rect.left, boxes[i].left);
          expect(rect.right, boxes[i].right);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(painter.height));
          expect(rect.height, lessThan(2 * scale));
          if (height == 1.6 && i < strokes.length - 1) {
            expect(rect.top - boxes[i].bottom, closeTo(28 * scale * .08, .01));
          }
        }
      } finally {
        painter.dispose();
        legacy.dispose();
      }
    }
  });

  test('border-only changes repaint without changing layout', () {
    const span = ReaderBorderSpan(
      text: '字',
      style: TextStyle(fontSize: 28),
      borderStyle: BoxBorderStyle.dotted,
      color: Colors.black,
      width: 2,
    );
    final changed = readerCopyTextSpan(span, semanticsLabel: '文字');
    expect(changed, isA<ReaderBorderSpan>());
    expect((changed as ReaderBorderSpan).width, 2);
    const newBorder = ReaderBorderSpan(
      text: '字',
      style: TextStyle(fontSize: 28),
      borderStyle: BoxBorderStyle.dashed,
      color: Colors.red,
      width: 1,
    );
    expect(span, isNot(newBorder));
    expect(span.compareTo(newBorder), RenderComparison.paint);
  });

  testWidgets('ruby, stack and superscript paint borders inside their bounds', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 28, height: 1.6, color: Colors.black);
    final styles = [
      InlineTextStyle(
        start: 0,
        length: 5,
        borderBottom: BoxBorderSide(
          style: BoxBorderStyle.dotted,
          width: LayoutLength(2),
          color: 0xffff0000,
        ),
      ),
    ];
    final ruby = readerRubyLayout(
      text: '示例',
      ruby: InlineRuby(start: 0, length: 2, annotation: 'example'),
      styles: styles,
      style: style,
      scaler: TextScaler.noScaling,
      direction: TextDirection.ltr,
      maxWidth: 320,
    );
    final stack = readerStackLayout(
      text: 'UP\n下层',
      stack: InlineStack(start: 0, length: 5, separator: 2),
      styles: styles,
      style: style,
      scaler: TextScaler.linear(1.5),
      direction: TextDirection.ltr,
    );
    final raised = ReaderSuperscriptLayout(
      span: readerAuthoredSpan('[1]', style.copyWith(fontSize: 14), styles, 0),
      scaler: TextScaler.noScaling,
      direction: TextDirection.ltr,
    );
    for (final (size, paint) in <(Size, void Function(Canvas))>[
      (ruby.metrics.size, (c) => ruby.paint(c)),
      (stack.geometry.size, (c) => stack.paint(c)),
      (raised.metrics.size, (c) => raised.paint(c, null, 0)),
    ]) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..translate(2, 2);
      paint(canvas);
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final image = await picture.toImage(
          size.width.ceil() + 4,
          size.height.ceil() + 4,
        );
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        ))!;
        var red = 0;
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            final i = (y * image.width + x) * 4;
            if (data.getUint8(i) > 200 &&
                data.getUint8(i + 1) < 50 &&
                data.getUint8(i + 3) > 50) {
              red++;
              expect(x, inInclusiveRange(2, size.width.ceil() + 1));
              expect(y, inInclusiveRange(2, size.height.ceil() + 1));
            }
          }
        }
        image.dispose();
        expect(red, greaterThan(0), reason: 'border missing from $size');
      });
      picture.dispose();
    }
  });

  testWidgets('inline border spacing on warm paper', (tester) async {
    await fonts(tester);
    final theme = readerTheme(
      ReaderSettings(paper: ReaderPaper.warm),
      Brightness.light,
    );
    final block = paragraphs(
      '<p>她合上书，轻声说：“<span style="border-bottom:2px dotted black">请在明天傍晚之前，把这本书放回原处。</span>”窗外的雨还在下。</p>',
    ).single;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundary,
              child: Container(
                width: 320,
                color: theme.scaffoldBackgroundColor,
                padding: const EdgeInsets.all(16),
                child: ReaderLinkedText(
                  text: block.text,
                  prefix: '',
                  blockOffset: 0,
                  links: const [],
                  inlineStyles: block.inlineStyles,
                  style: TextStyle(
                    inherit: false,
                    fontFamily: 'Roboto',
                    fontSize: 28,
                    height: 1.6,
                    color: theme.colorScheme.onSurface,
                  ),
                  align: TextAlign.left,
                  scaler: TextScaler.noScaling,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await screenshot(tester, boundary, 'border-spacing-warm');
  });
}
