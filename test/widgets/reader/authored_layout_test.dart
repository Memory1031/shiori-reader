import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/reader_box.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/page_boundaries.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import 'package:shiori/features/reader/reader_authored_colors.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import '../../data/local/epub_authored_layout_test.dart' show authoredContent;

void main() {
  testWidgets(
    'missing authored ink uses readable link accent; paper links and geometry remain unchanged',
    (tester) async {
      final book = authoredContent(
        '<p><a href="#target">合成链接</a></p><p id="target">After</p>',
      );
      const ink = Color(0xff52756b), dark = Color(0xff272435);
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: ink,
        ).copyWith(primary: ink),
      );
      var activations = 0;
      Size? size;
      for (final background in [null, dark.toARGB32()]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Center(
              child: SizedBox(
                width: 240,
                child: ReaderLinkedText(
                  text: '合成链接',
                  prefix: '',
                  blockOffset: 0,
                  links: book.links,
                  style: const TextStyle(fontSize: 20),
                  align: TextAlign.left,
                  scaler: TextScaler.noScaling,
                  authoredBackground: background,
                  onLink: (_) => activations++,
                ),
              ),
            ),
          ),
        );
        final paragraph = tester
            .renderObjectList<RenderParagraph>(find.byType(RichText))
            .singleWhere((p) => p.text.toPlainText() == '合成链接');
        Color? color;
        paragraph.text.visitChildren((s) {
          if (s is TextSpan && s.recognizer != null) color = s.style!.color;
          return true;
        });
        if (background == null) {
          expect(color, ink);
          size = paragraph.size;
        } else {
          expect(readerColorContrast(color!, dark), greaterThanOrEqualTo(4.5));
          expect(paragraph.size, size);
        }
        final box = paragraph
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 4),
            )
            .first;
        final point = paragraph.localToGlobal(
          Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2),
        );
        await tester.tapAt(point);
        await tester.dragFrom(point, const Offset(-100, 0));
      }
      expect(activations, 2);
    },
  );
  testWidgets(
    'seven paragraph buttons share authored width, paint and hit geometry',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final labels = ['第一章', '第二章', '第三章', '第四章', '第五章', '较长章节标签', '后记'];
      final book = authoredContent(
        '${labels.map((l) => '<p class="entry"><a href="#target" style="color:white">$l</a><br/></p>').join()}<p id="target">${'After ' * 40}</p>',
        '.entry{width:4em;background-color:#272435;border-radius:15px;padding:1px;text-align:center;text-indent:0;margin:.7em}',
      );
      final controller = PagedReaderController();
      var activated = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 900,
              child: PagedReaderViewport(
                content: book.chapters.first,
                controller: controller,
                contentLinks: book.links,
                textStyle: const TextStyle(fontSize: 20, height: 1.6),
                turnStyle: PageTurnStyle.none,
                onLink: (_) => activated++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final buttons = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == const Color(0xff272435),
      );
      expect(buttons, findsNWidgets(7));
      final paragraphs = tester.renderObjectList<RenderParagraph>(
        find.byType(RichText),
      );
      for (var i = 0; i < labels.length; i++) {
        final button = buttons.at(i), rect = tester.getRect(button);
        expect(rect.width, closeTo(82, .01));
        final decoration =
            tester.widget<DecoratedBox>(button).decoration as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(15));
        final paragraph = paragraphs.singleWhere(
          (p) => p.text.toPlainText() == labels[i],
        );
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: labels[i].length),
        );
        for (final box in boxes) {
          expect(
            paragraph.localToGlobal(Offset((box.left + box.right) / 2, 0)).dx,
            closeTo(rect.center.dx, .01),
          );
        }
        expect(rect.height, closeTo(paragraph.size.height + 2, .01));
        Color? color;
        paragraph.text.visitChildren((s) {
          if (s is TextSpan && s.text?.isNotEmpty == true) {
            color = s.style?.color;
          }
          return true;
        });
        expect(
          readerColorContrast(color!, decoration.color!),
          greaterThanOrEqualTo(4.5),
        );
        await tester.tapAt(rect.center);
        expect(activated, i * 2 + 1);
        await tester.tapAt(rect.topLeft + const Offset(.5, .5));
        expect(activated, i * 2 + 2);
      }
      final frames = tester
          .widgetList<ReaderBoxFrame>(find.byType(ReaderBoxFrame))
          .where((f) => f.box?.backgroundColor == 0xff272435);
      expect(frames, hasLength(7));
      expect(frames.every((f) => f.linkOwnsDecoration), isTrue);
      await tester.tapAt(
        tester.getRect(buttons.first).topCenter - const Offset(0, 4),
      );
      expect(activated, 14);
      tester
          .widget<FocusableActionDetector>(
            find.byType(FocusableActionDetector).first,
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(activated, 16);
      final before = controller.capture();
      await tester.drag(buttons.first, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(activated, 16);
      expect(controller.capture(), isNot(before));
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'paragraph button fallback retains text, source link and background on short pages',
    () {
      final book = authoredContent(
        '<p style="background-color:#272435;width:4em;padding:2em;border-radius:99em"><a href="#target" style="color:white">${'长标签😀' * 30}</a></p><p id="target">After</p>',
      );
      final content = book.chapters.first,
          block = content.blocks.first as ParagraphBlock;
      expect(block.linkDecoration!.onBlock, isTrue);
      for (final scaler in [TextScaler.noScaling, TextScaler.linear(2)]) {
        final layout = PageLayout(
          index: ChunkIndex(content),
          width: 130,
          height: 150,
          style: const TextStyle(fontSize: 28, height: 1.6),
          scaler: scaler,
          direction: TextDirection.ltr,
        );
        var cursor = const PageCursor(0, 0);
        final text = StringBuffer();
        for (var i = 0; i < 100; i++) {
          final page = layout.forward(cursor);
          if (page == null) break;
          expect(PageBoundaries.compare(page.end, cursor), greaterThan(0));
          for (final f in page.fragments) {
            expect(f.linkLayout, isNull);
            text.write(f.text ?? '');
          }
          cursor = page.end;
        }
        expect(cursor.unit, layout.index.chunks.length);
        expect(text.toString(), '${block.text}After');
        expect(content.blocks.first.box!.backgroundColor, 0xff272435);
        expect(book.links.single.sourceLength, block.text.runes.length);
      }
    },
  );
  testWidgets(
    'background links retain readable authored foreground in every paper theme',
    (tester) async {
      final book = authoredContent(
        '<p style="background-color:#272435"><a href="#target" style="color:white">合成链接</a> extra</p>'
        '<p id="target">After</p>',
      );
      final block = book.chapters.first.blocks.first as ParagraphBlock;
      expect(block.linkDecoration, isNull);
      for (final theme in [
        ThemeData(),
        ThemeData(scaffoldBackgroundColor: const Color(0xfff4e9d5)),
        ThemeData.dark(),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: ReaderLinkedText(
              text: block.text,
              prefix: '',
              blockOffset: 0,
              links: book.links,
              style: const TextStyle(fontSize: 20),
              align: TextAlign.left,
              scaler: TextScaler.noScaling,
              inlineStyles: block.inlineStyles,
              authoredBackground: block.box!.backgroundColor,
            ),
          ),
        );
        final paragraph = tester
            .renderObjectList<RenderParagraph>(find.byType(RichText))
            .singleWhere((p) => p.text.toPlainText() == block.text);
        final foreground = <Color>[];
        paragraph.text.visitChildren((span) {
          if (span is TextSpan && span.recognizer != null) {
            foreground.add(span.style!.color!);
          }
          return true;
        });
        expect(foreground, isNotEmpty);
        for (final color in foreground) {
          expect(
            readerColorContrast(color, const Color(0xff272435)),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );
  for (final alignment in ['center', 'right']) {
    testWidgets(
      'two-line decorated link preserves $alignment character alignment',
      (tester) async {
        const label = 'ABCDEFGHIJKLM';
        final book = authoredContent(
          '<p style="text-align:$alignment"><a href="#target" '
          'style="background-color:#544f65;color:white;'
          'border-radius:30px;padding:.3em">$label</a></p>'
          '<p id="target">After</p>',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Center(
              child: SizedBox(
                width: 200,
                height: 260,
                child: PagedReaderViewport(
                  content: book.chapters.first,
                  controller: PagedReaderController(),
                  contentLinks: book.links,
                  textStyle: const TextStyle(fontSize: 20, height: 1.6),
                  turnStyle: PageTurnStyle.none,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final pill = find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xff544f65),
        );
        expect(pill, findsOneWidget);
        final paragraph = tester
            .renderObjectList<RenderParagraph>(find.byType(RichText))
            .singleWhere((p) => p.text.toPlainText() == label);
        final lines = paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: label.length),
        );
        expect(lines, hasLength(2));
        expect(
          lines.last.right - lines.last.left,
          lessThan(lines.first.right - lines.first.left),
        );
        if (alignment == 'center') {
          expect(
            lines.last.left + lines.last.right,
            closeTo(lines.first.left + lines.first.right, .01),
          );
        } else {
          expect(lines.last.right, closeTo(lines.first.right, .01));
        }
        final layout = readerLinkLayout(
          book.chapters.first.blocks.first as ParagraphBlock,
          200,
          const TextStyle(fontSize: 20, height: 1.6),
          TextScaler.noScaling,
          TextDirection.ltr,
          chapter: book.chapters.first.key,
        )!;
        expect(
          tester.getSize(pill).height,
          closeTo(paragraph.size.height + layout.padding.vertical, .01),
        );
        final pillBounds = tester.getRect(pill);
        final viewport = tester.getRect(find.byType(PagedReaderViewport));
        if (alignment == 'center') {
          expect(pillBounds.center.dx, closeTo(viewport.center.dx, .01));
        } else {
          expect(pillBounds.right, closeTo(viewport.right, .01));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'boxed placeholders paginate from mid-chapter with scaled nested edges',
    () {
      const picture =
          '<img src="../images/%E6%98%9F%20%E7%A9%BA.png" '
          'style="width:4em;height:4em"/>';
      for (final body in [
        '<p>$picture</p>',
        '<p style="margin-left:1em;text-indent:-1em">$picture</p>',
        '<p><ruby>Native<rt>Reading</rt></ruby></p>',
      ]) {
        final content = authoredContent(
          '<p>${'Before ' * 30}</p>'
          '<div style="margin:36% 0;padding:999em;border:3px solid blue">'
          '$body</div><p>After</p>',
        ).chapters.first;
        final boxed = content.blocks[1] as ParagraphBlock;
        if (body.contains('text-indent')) {
          expect(boxed.hangingIndentEm, 1);
        }
        if (body.contains('ruby')) {
          expect(boxed.inlineRuby, hasLength(1));
        }
        for (final scaler in [TextScaler.noScaling, TextScaler.linear(1.5)]) {
          final layout = PageLayout(
            index: ChunkIndex(content),
            width: 300,
            height: 250,
            style: const TextStyle(fontSize: 20, height: 1.6),
            scaler: scaler,
            direction: TextDirection.ltr,
          );
          var cursor = const PageCursor(0, 0);
          final text = StringBuffer();
          final pages = <ReaderPage>[];
          for (var i = 0; i < 30; i++) {
            final page = layout.forward(cursor);
            if (page == null) break;
            expect(PageBoundaries.compare(page.end, cursor), greaterThan(0));
            expect(
              page.fragments.fold<double>(0, (h, f) => h + f.height),
              lessThanOrEqualTo(250.01),
            );
            pages.add(page);
            text.write(page.fragments.map((f) => f.text ?? '').join());
            cursor = page.end;
          }
          expect(cursor.unit, layout.index.chunks.length);
          expect(
            text.toString(),
            content.blocks
                .whereType<ParagraphBlock>()
                .map((b) => b.text)
                .join(),
          );
          final back = layout.backward(cursor)!;
          expect(PageBoundaries.compare(back.start, pages.last.start), 0);
        }
      }
    },
  );

  testWidgets(
    'inline image shrinks optional box edges and reaches the real chapter end',
    (tester) async {
      final content = authoredContent(
        '<div style="background-color:#eeeeee;margin:36% 0">'
        '<p><img src="../images/%E6%98%9F%20%E7%A9%BA.png" '
        'style="width:4em;height:4em"/></p></div><p>After</p>',
      ).chapters.first;
      final image = content.blocks.first as ParagraphBlock;
      expect(image.inlineImages, hasLength(1));
      expect(image.inlineImages.single.heightEm, 4);
      const style = TextStyle(fontSize: 20, height: 1.6);
      final layout = PageLayout(
        index: ChunkIndex(content),
        width: 300,
        height: 250,
        style: style,
        scaler: TextScaler.noScaling,
        direction: TextDirection.ltr,
      );
      var cursor = const PageCursor(0, 0);
      final source = StringBuffer();
      final first = layout.forward(cursor);
      expect(first, isNotNull);
      for (var i = 0; i < 10; i++) {
        final page = layout.forward(cursor);
        if (page == null) break;
        expect(PageBoundaries.compare(page.end, cursor), greaterThan(0));
        expect(
          page.fragments.fold<double>(0, (sum, f) => sum + f.height),
          lessThanOrEqualTo(250.01),
        );
        source.write(page.fragments.map((f) => f.text ?? '').join());
        cursor = page.end;
      }
      expect(cursor.unit, layout.index.chunks.length);
      expect(source.toString(), '\uFFfcAfter');
      final fragment = first!.fragments.first;
      expect(fragment.boxTop + fragment.boxBottom, lessThan(216));
      final controller = PagedReaderController();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 250,
              child: PagedReaderViewport(
                content: content,
                controller: controller,
                textStyle: style,
                turnStyle: PageTurnStyle.none,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .singleWhere((p) => p.text.toPlainText() == '\uFFfc');
      expect(paragraph.size.height, greaterThanOrEqualTo(80));
      final frame = tester
          .widgetList<ReaderBoxFrame>(find.byType(ReaderBoxFrame))
          .singleWhere((f) => f.box == image.box);
      expect(frame.geometry!.top, closeTo(fragment.boxTop, .01));
      expect(frame.geometry!.bottom, closeTo(fragment.boxBottom, .01));
      final bounds = tester.getRect(find.byType(PagedReaderViewport));
      final paragraphBottom = paragraph
          .localToGlobal(Offset(0, paragraph.size.height))
          .dy;
      expect(paragraphBottom, lessThanOrEqualTo(bounds.bottom + .01));
      await controller.next();
      await tester.pumpAndSettle();
      expect(find.text('After', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'large headings and huge nested edges still progress on short pages',
    () {
      final content = authoredContent(
        '<div style="padding:999em;border:6px solid blue">'
        '<h1 style="font-size:xxx-large;margin:999em">Large title</h1>'
        '<p>After title</p></div><p>End</p>',
      ).chapters.first;
      final layout = PageLayout(
        index: ChunkIndex(content),
        width: 240,
        height: 100,
        style: const TextStyle(fontSize: 20, height: 1.6),
        scaler: TextScaler.noScaling,
        direction: TextDirection.ltr,
      );
      var cursor = const PageCursor(0, 0);
      final text = StringBuffer();
      for (var i = 0; i < 30; i++) {
        final page = layout.forward(cursor);
        if (page == null) break;
        expect(page.end, isNot(cursor));
        text.write(page.fragments.map((f) => f.text ?? '').join());
        cursor = page.end;
      }
      expect(cursor.unit, layout.index.chunks.length);
      expect(text.toString(), 'Large titleAfter titleEnd');
    },
  );
  testWidgets(
    'decorated text/padding activate once; focus keys and drag do not leak',
    (tester) async {
      final book = authoredContent(
        '<p style="text-align:center"><a href="#target"><span style="background-color:#544f65;'
        'color:white;border-radius:30px;padding:.3em">Synthetic link</span></a></p>'
        '<p id="target">${'After the label. ' * 40}</p>',
      );
      final content = book.chapters.first, controller = PagedReaderController();
      var activations = 0, center = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Center(
            child: SizedBox(
              width: 300,
              height: 260,
              child: PagedReaderViewport(
                content: content,
                controller: controller,
                contentLinks: book.links,
                textStyle: const TextStyle(fontSize: 20, height: 1.6),
                turnStyle: PageTurnStyle.none,
                onLink: (link) {
                  expect(link.targetBlockKey, content.blocks[1].blockKey);
                  activations++;
                },
                onCenterTap: () => center++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pill = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == const Color(0xff544f65),
      );
      expect(pill, findsOneWidget);
      expect(tester.getSize(pill).width, lessThan(300));
      final before = controller.capture();
      await tester.tapAt(tester.getRect(pill).center);
      await tester.pump();
      expect(activations, 1);
      expect(center, 0);
      expect(controller.capture(), before);
      await tester.tapAt(tester.getRect(pill).topLeft + const Offset(2, 2));
      await tester.pump();
      expect(activations, 2);
      expect(controller.capture(), before);
      tester
          .widget<FocusableActionDetector>(find.byType(FocusableActionDetector))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(activations, 4);
      expect(controller.capture(), before);
      final text = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .firstWhere((p) => p.text.toPlainText() == 'Synthetic link');
      Color? foreground;
      text.text.visitChildren((span) {
        if (span is TextSpan && span.text?.isNotEmpty == true) {
          foreground = span.style?.color;
        }
        return true;
      });
      expect(
        readerColorContrast(foreground!, const Color(0xff544f65)),
        greaterThanOrEqualTo(4.5),
      );
      await tester.drag(pill, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(activations, 4);
      expect(center, 0);
      expect(controller.capture(), isNot(before));
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'too-tall labels lose decoration and retain all source text across pages',
    () {
      final label = 'Unabridged native link text ' * 8;
      final content = authoredContent(
        '<p><a href="#target" style="background-color:#544f65;color:white;padding:2em">$label</a></p>'
        '<p id="target">After</p>',
      ).chapters.first;
      expect(
        (content.blocks.first as ParagraphBlock).linkDecoration,
        isNotNull,
      );
      final layout = PageLayout(
        index: ChunkIndex(content),
        width: 100,
        height: 110,
        style: const TextStyle(fontSize: 28, height: 1.6),
        scaler: TextScaler.noScaling,
        direction: TextDirection.ltr,
      );
      var cursor = const PageCursor(0, 0);
      final text = StringBuffer();
      var pages = 0;
      while (pages++ < 100) {
        final page = layout.forward(cursor);
        if (page == null) break;
        expect(PageBoundaries.compare(page.end, cursor), greaterThan(0));
        for (final f in page.fragments) {
          expect(f.linkLayout, isNull);
          text.write(f.text ?? '');
        }
        cursor = page.end;
      }
      expect(cursor.unit, layout.index.chunks.length);
      expect(
        text.toString(),
        content.blocks.whereType<ParagraphBlock>().map((b) => b.text).join(),
      );
    },
  );
  test('percent edges use containing width; asymmetric geometry is shared', () {
    final block = authoredContent(
      '<div style="margin-top:36%;margin-left:10px;padding:1px 2px 3px 4px;border-top:6px solid blue">Text</div>',
    ).chapters.first.blocks.single;
    final geometry = readerBlockBoxes(
      block,
      300,
      const TextStyle(fontSize: 20),
      TextScaler.noScaling,
      pageHeight: 1000,
    ).outer!;
    expect(geometry.requestedMarginTop, 108);
    expect(geometry.marginTop, 108);
    expect(geometry.contentWidth, 284);
    expect(geometry.borderLeft, 0);
    expect(geometry.paddingLeft, 4);
    expect(geometry.paddingRight, 2);
    expect(
      readerBlockBoxes(
        block,
        150,
        const TextStyle(fontSize: 20),
        TextScaler.noScaling,
        pageHeight: 1000,
      ).outer!.marginTop,
      54,
    );
  });
  test('painter has only top/right strokes, including continuation slices', () {
    final box = authoredContent(
      '<div style="border-width:6px;border-style:ridge groove none none;border-color:#4682b4">Text</div>',
    ).chapters.first.blocks.single.box!;
    final g = ReaderBoxGeometry(box, 300, 20, 600);
    final colors = ReaderAuthoredColors(ThemeData());
    void paint(Canvas c) => ReaderBoxPainter(
      box,
      g,
      true,
      true,
      colors,
    ).paint(c, const Size(300, 100));
    expect(
      paint,
      paints
        ..line(p1: const Offset(297, 0), p2: const Offset(297, 100))
        ..line(p1: const Offset(0, 3), p2: const Offset(300, 3)),
    );
    expect(paint, paintsExactlyCountTimes(#drawLine, 2));
    void continuation(Canvas c) => ReaderBoxPainter(
      box,
      g,
      false,
      false,
      colors,
    ).paint(c, const Size(300, 100));
    expect(continuation, paintsExactlyCountTimes(#drawLine, 1));
  });
  test(
    'container edges slice across chunks/pages; huge whitespace cannot stop text',
    () {
      final text = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ ' * 22;
      final content = authoredContent(
        '<div style="margin:999em 5px;padding:999em 7px;border:3px solid blue">'
        '<p>$text</p><dl><dt>Maker</dt><dd>Name</dd></dl></div><p>After</p>',
      ).chapters.first;
      final layout = PageLayout(
        index: ChunkIndex(content, maxCodePoints: 64),
        width: 240,
        height: 100,
        style: const TextStyle(fontSize: 20, height: 1.5),
        scaler: TextScaler.noScaling,
        direction: TextDirection.ltr,
      );
      final boundaries = PageBoundaries(layout), pages = <ReaderPage>[];
      var cursor = const PageCursor(0, 0);
      for (var i = 0; i < 100; i++) {
        final page = boundaries.forward(cursor);
        if (page == null) break;
        expect(PageBoundaries.compare(page.end, cursor), greaterThan(0));
        expect(
          page.fragments.fold<double>(0, (h, f) => h + f.height),
          lessThanOrEqualTo(100.01),
        );
        pages.add(page);
        cursor = page.end;
      }
      expect(cursor.unit, layout.index.chunks.length);
      expect(
        pages.expand((p) => p.fragments).map((f) => f.text ?? '').join(),
        content.blocks.whereType<ParagraphBlock>().map((b) => b.text).join(),
      );
      final fragments = pages.expand((p) => p.fragments).toList();
      expect(fragments.where((f) => f.boxTop > 0).length, 1);
      expect(fragments.where((f) => f.boxBottom > 0).length, 1);
      for (final page in pages.reversed) {
        final back = boundaries.backward(cursor)!;
        expect(PageBoundaries.compare(back.start, page.start), 0);
        cursor = back.start;
      }
      final middle = pages[2].start;
      expect(layout.forward(middle)!.fragments.first.boxTop, 0);
    },
  );
  testWidgets('half-width divider and dl/image frames use real layout positions', (
    tester,
  ) async {
    final content = authoredContent(
      '<div style="margin-top:36%"><img src="../images/%E6%98%9F%20%E7%A9%BA.png" width="100" height="20"/></div>'
      '<dl style="border-bottom:2px solid black;margin:0 2% 0 32%;padding-right:6%"><dt>Maker</dt><dd>Name</dd></dl>'
      '<hr style="width:50%;margin:0 auto"/><p>After</p>',
    ).chapters.first;
    final controller = PagedReaderController();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 500,
            child: PagedReaderViewport(
              content: content,
              controller: controller,
              turnStyle: PageTurnStyle.none,
              imageExtent: (_) => 20,
              imageBuilder: (_, _) => const ColoredBox(color: Colors.purple),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == Colors.purple,
    );
    expect(
      tester.getTopLeft(image).dy -
          tester.getTopLeft(find.byType(PagedReaderViewport)).dy,
      108,
    );
    final divider = find.byType(Divider);
    expect(tester.getSize(divider).width, 150);
    expect(
      tester.getCenter(divider).dx,
      tester.getCenter(find.byType(PagedReaderViewport)).dx,
    );
    final makers = tester
        .widgetList<ReaderBoxFrame>(find.byType(ReaderBoxFrame))
        .where((w) => w.box?.borders?.bottom?.width.value == 2)
        .toList();
    expect(makers.length, 2);
    expect(makers.map((w) => w.ends), [false, true]);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'rendered heading sizes and natural wrap use the reader base once',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final content = authoredContent(
        '<h1>A<span style="color:red">B</span></h1>'
        '<h1 style="font-size:xxx-large">Large title naturally wraps</h1>'
        '<h1>G<span style="font-size:.8em">H</span><span style="font-size:medium">I</span></h1>'
        '<h1 style="font-size:medium">Medium title</h1><p>End</p>',
      ).chapters.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 280,
              height: 1300,
              child: PagedReaderViewport(
                content: content,
                controller: PagedReaderController(),
                textStyle: const TextStyle(fontSize: 20, height: 1.6),
                turnStyle: PageTurnStyle.none,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraphs = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .where((p) => p.text.toPlainText().isNotEmpty)
          .toList();
      final a = paragraphs.firstWhere((p) => p.text.toPlainText() == 'AB');
      final large = paragraphs.firstWhere(
        (p) => p.text.toPlainText() == 'Large title naturally wraps',
      );
      final mixed = paragraphs.firstWhere((p) => p.text.toPlainText() == 'GHI');
      final medium = paragraphs.firstWhere(
        (p) => p.text.toPlainText() == 'Medium title',
      );
      List<double> sizes(RenderParagraph p) {
        final result = <double>[];
        p.text.visitChildren((span) {
          if (span is TextSpan && span.text?.isNotEmpty == true) {
            result.add(span.style!.fontSize!);
          }
          return true;
        });
        return result;
      }

      expect(sizes(a), [28, 28]);
      expect(sizes(large), [60]);
      expect(large.size.height, greaterThan(78));
      expect(sizes(mixed), [28, closeTo(22.4, .001), 20]);
      expect(sizes(medium), [20]);
      expect(tester.takeException(), isNull);
    },
  );
}
