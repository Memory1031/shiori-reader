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

ReaderBorderSpan _border(
  String text, {
  Color color = Colors.black,
  BoxBorderStyle type = BoxBorderStyle.dotted,
  double width = 2,
  double fontSize = 20,
}) => ReaderBorderSpan(
  text: text,
  style: TextStyle(fontSize: fontSize),
  borderStyle: type,
  color: color,
  width: width,
);

void main() {
  test('mixed font boxes share one continuous line and phase', () {
    var queries = 0;
    const boxes = [
      TextBox.fromLTRBD(0, 8, 20, 32, TextDirection.ltr),
      TextBox.fromLTRBD(20, 8, 32, 32, TextDirection.ltr),
      TextBox.fromLTRBD(32, 8.004, 72, 32.004, TextDirection.ltr),
    ];
    final strokes = readerBorderStrokes(
      _border('示例C123'),
      TextScaler.noScaling,
      const Size(80, 48),
      (_) {
        queries++;
        return boxes;
      },
    );
    expect(queries, 2);
    expect(strokes, hasLength(1));
    expect(strokes.single.rect.left, 0);
    expect(strokes.single.rect.right, 72);
    expect(strokes.single.rect.top, closeTo(33.6, .01));
  });

  test('adjacent equivalent spans merge before querying UTF-16 ranges', () {
    final queries = <(int, int)>[];
    List<ReaderBorderStroke> strokes(InlineSpan span) => readerBorderStrokes(
      span,
      TextScaler.noScaling,
      const Size(100, 48),
      (selection) {
        queries.add((selection.start, selection.end));
        return [TextBox.fromLTRBD(10, 8, 90, 32, TextDirection.ltr)];
      },
    );
    final whole = strokes(_border('甲😀e\u0301C乙'));
    queries.clear();
    final split = TextSpan(
      children: [
        _border('甲'),
        TextSpan(children: [_border('😀'), _border('e\u0301')]),
        readerCopyTextSpan(
          _border('C'),
          style: const TextStyle(
            fontSize: 20,
            fontFamily: 'another-family',
            fontWeight: FontWeight.bold,
          ),
        ),
        _border('乙'),
      ],
    );
    expect(strokes(split), whole);
    expect(queries, [(0, 7), (0, 7)]);
    expect(split.toPlainText(), '甲😀e\u0301C乙');
  });

  test(
    'non-emphasized content and atomic spans separate touching intervals',
    () {
      for (final separator in <InlineSpan>[
        const TextSpan(text: ' '),
        const TextSpan(text: '\u200b'),
        const WidgetSpan(child: SizedBox.shrink()),
      ]) {
        final span = TextSpan(
          children: [_border('甲'), separator, _border('乙')],
        );
        final queries = <(int, int)>[];
        final strokes = readerBorderStrokes(
          span,
          TextScaler.noScaling,
          const Size(60, 48),
          (s) {
            queries.add((s.start, s.end));
            // Even a zero-width separator must prevent a shared dotted phase.
            const edges = [0.0, 10.0, 10.0, 20.0];
            return [
              TextBox.fromLTRBD(
                edges[s.start],
                8,
                edges[s.end],
                32,
                TextDirection.ltr,
              ),
            ];
          },
        );
        expect(queries, [(0, 3), (0, 1), (2, 3)]);
        expect(strokes.map((s) => (s.rect.left, s.rect.right)).toList(), [
          (0.0, 10.0),
          (10.0, 20.0),
        ]);
      }
      final strokes = readerBorderStrokes(
        _border('甲 C 乙'),
        TextScaler.noScaling,
        const Size(60, 48),
        (_) => [const TextBox.fromLTRBD(0, 8, 50, 32, TextDirection.ltr)],
      );
      expect(strokes, hasLength(1));
      expect(strokes.single.rect.width, 50);
    },
  );

  test('only matching effective decoration parameters merge', () {
    for (final (second, merged) in [
      (_border('乙', color: Colors.red), false),
      (_border('乙', type: BoxBorderStyle.dashed), false),
      (_border('乙', width: .5), false),
      (_border('乙', fontSize: 24), false),
      (_border('乙', width: 8), true),
    ]) {
      final strokes = readerBorderStrokes(
        TextSpan(children: [_border('甲'), second]),
        TextScaler.noScaling,
        const Size(60, 48),
        (s) => [
          TextBox.fromLTRBD(
            s.start * 10.0,
            8,
            s.end * 10.0,
            32,
            TextDirection.ltr,
          ),
        ],
      );
      expect(strokes, hasLength(merged ? 1 : 2));
    }
    final strokes = readerBorderStrokes(
      TextSpan(
        children: [
          _border('甲', width: .5),
          _border('乙', width: .5, fontSize: 24),
        ],
      ),
      TextScaler.noScaling,
      const Size(60, 48),
      (s) => [
        TextBox.fromLTRBD(
          s.start * 10.0,
          8,
          s.end * 10.0,
          32,
          TextDirection.ltr,
        ),
      ],
    );
    expect(
      strokes,
      hasLength(2),
      reason: 'equal thickness does not erase different em spacing',
    );
  });

  test('separate visual islands, directions and rows never bridge', () {
    final strokes = readerBorderStrokes(
      _border('示例C123'),
      TextScaler.noScaling,
      const Size(100, 100),
      (_) => const [
        TextBox.fromLTRBD(0, 8, 10, 32, TextDirection.ltr),
        TextBox.fromLTRBD(10, 8, 20, 32, TextDirection.rtl),
        TextBox.fromLTRBD(40, 8, 50, 32, TextDirection.ltr),
        TextBox.fromLTRBD(0, 50, 20, 74, TextDirection.ltr),
      ],
    );
    expect(strokes, hasLength(4));
    expect(
      strokes
          .where((s) => s.rect.top < 50)
          .map((s) => s.rect.center.dy)
          .toSet(),
      hasLength(1),
    );
    expect(strokes.every((s) => s.rect.width <= 20), isTrue);
    expect(strokes.last.rect.top, greaterThan(74));
  });

  test('unrecognized row bounds keep touching boxes separate', () {
    final strokes = readerBorderStrokes(
      TextSpan(
        children: [
          const TextSpan(text: '前'),
          _border('甲C'),
        ],
      ),
      TextScaler.noScaling,
      const Size(60, 48),
      (selection) => selection.start == 0
          ? [const TextBox.fromLTRBD(0, 8, 30, 32, TextDirection.ltr)]
          : const [
              TextBox.fromLTRBD(10, 8, 20, 33, TextDirection.ltr),
              TextBox.fromLTRBD(20, 8, 30, 33, TextDirection.ltr),
            ],
    );
    expect(strokes, hasLength(2));
    expect(strokes.first.rect.right, strokes.last.rect.left);
  });

  test('undecorated visible spans never query selection geometry', () {
    var calls = 0;
    for (final span in [
      const TextSpan(text: '普通正文'),
      const TextSpan(children: [TextSpan(text: '注音、上标或双层文字的正文')]),
      const TextSpan(children: [WidgetSpan(child: SizedBox())]),
      const ReaderBorderSpan(
        text: '',
        style: TextStyle(fontSize: 28),
        borderStyle: BoxBorderStyle.dotted,
        color: Colors.black,
        width: 2,
      ),
    ]) {
      expect(
        readerBorderStrokes(span, TextScaler.noScaling, const Size(320, 48), (
          _,
        ) {
          calls++;
          return const [];
        }),
        isEmpty,
      );
    }
    expect(calls, 0);
  });

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
      const marked = '示例C123混排文字，最后一行也保留点线。';
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
        List<TextBox> lineBoxes(TextSelection selection) =>
            painter.getBoxesForSelection(
              selection,
              boxHeightStyle: ui.BoxHeightStyle.max,
              boxWidthStyle: ui.BoxWidthStyle.tight,
            );
        final selected = lineBoxes(selection);
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
          lineBoxes,
        );
        expect(strokes.length, greaterThan(1));
        final rows = <double, Set<double>>{};
        for (final box in selected) {
          final nextTop = selected
              .where((b) => b.top > box.top + .01)
              .fold(painter.height, (top, b) => b.top < top ? b.top : top);
          final covering = strokes.where(
            (s) =>
                s.rect.left <= box.left + .01 &&
                s.rect.right >= box.right - .01 &&
                s.rect.center.dy >= box.top &&
                s.rect.center.dy < nextTop,
          );
          expect(
            covering,
            hasLength(1),
            reason: 'every selected interval stays covered',
          );
          (rows[box.top] ??= {}).add(covering.single.rect.center.dy);
        }
        expect(rows.values.every((ys) => ys.length == 1), isTrue);
        expect(strokes.length, rows.length);
        expect(
          strokes.first.rect.left,
          selected.first.left,
          reason: 'the unmarked prefix must remain unmarked',
        );
        for (final stroke in strokes) {
          final rect = stroke.rect;
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(painter.height));
          expect(rect.height, lessThan(2 * scale));
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
