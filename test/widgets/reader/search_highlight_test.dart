import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_inline_stack.dart';
import 'package:shiori/features/reader/reader_ruby.dart';
import 'package:shiori/features/reader/reader_search_highlight.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/reader_authored_colors.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import '../../data/local/epub_prose_semantics_test.dart' show paragraphs;
import 'local_search_test.dart' show fonts;

final key = LocalBookIdentity.chapter(
  LocalBookIdentity.book('a' * 64),
  'glyphs',
);
LocalSearchBodyHit hit(ChapterContent c, int block, int start, int end) =>
    LocalSearchBodyHit(
      snapshot: LocalSearchSnapshotId('glyph-snapshot'),
      chapter: c.key,
      contentRevision: c.contentRevision,
      blockKey: c.blocks[block].blockKey,
      blockIndex: block,
      start: start,
      end: end,
      snippet: const LocalSearchSnippet(before: '', match: '字', after: ''),
    );
Future<void> screenshot(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final directory = Platform.environment['SHIORI_RETURN_SCREENSHOTS'];
  if (directory == null) return;
  await tester.pump();
  await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

List<Rect> boxes(WidgetTester tester) => tester
    .renderObjectList<ReaderSearchTextRender>(
      find.byType(ReaderPaintedSearchText),
    )
    .expand((r) => r.selectedBoxes)
    .where((b) => !b.isEmpty)
    .toList();

void main() {
  for (final palette in ['paper', 'warm', 'night']) {
    testWidgets(
      'glyph backgrounds preserve original ink and readable theme accent surfaces on $palette',
      (tester) async {
        await fonts(tester);
        final theme = readerTheme(
          ReaderSettings(
            paper: palette == 'warm' ? ReaderPaper.warm : ReaderPaper.paper,
            themeMode: palette == 'night'
                ? ReaderThemeMode.dark
                : ReaderThemeMode.light,
          ),
          Brightness.light,
        );
        final content = ChapterContent(
          key: key,
          title: 'Paint order',
          blocks: paragraphs(
            '<p>H H</p><p><span style="color:#b53050">H H</span></p>'
            '<p><ruby>H H<rt>reading</rt></ruby></p>'
            '<p><span style="display:inline-block;text-align:center;line-height:1em;text-indent:0">H H<br/>L L</span></p>'
            '<p style="color:white;background-color:#333333">H H</p>'
            '<p style="color:#202020;background-color:#f9f9f9">H H</p>',
          ),
        );
        expect(content.blocks, hasLength(6));
        final active = ValueNotifier<LocalSearchBodyHit?>(null),
            controller = PagedReaderController(),
            boundary = GlobalKey();
        addTearDown(active.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                    width: 400,
                    height: 420,
                    child: ColoredBox(
                      color: theme.scaffoldBackgroundColor,
                      child: ReaderSearchHighlightScope(
                        active: active,
                        content: content,
                        child: PagedReaderViewport(
                          content: content,
                          controller: controller,
                          textStyle: TextStyle(
                            fontSize: 24,
                            height: 1.6,
                            color: theme.colorScheme.onSurface,
                          ),
                          turnStyle: PageTurnStyle.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        Future<({ByteData bytes, int width, int height})> capture() async =>
            (await tester.runAsync(() async {
              final image = await render.toImage();
              final data = (
                bytes: (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!,
                width: image.width,
                height: image.height,
              );
              image.dispose();
              return data;
            }))!;
        int rgba(Color color) {
          final argb = color.toARGB32();
          return ((argb & 0xffffff) << 8) | (argb >> 24);
        }

        final baseline = await capture(),
            page = controller.inspectDisplayedPage()!.page,
            position = controller.capture(),
            generation = controller.layoutGeneration;
        await screenshot(tester, boundary, '$palette-ink-unmarked');
        final ruby = tester.widget<ReaderRuby>(find.byType(ReaderRuby)),
            stack = tester.widget<ReaderInlineStack>(
              find.byType(ReaderInlineStack),
            );
        final phases = [
          ('body', hit(content, 0, 0, 2)),
          ('authored-ink', hit(content, 1, 0, 2)),
          (
            'ruby-base',
            hit(content, 2, ruby.sourceStart, ruby.sourceStart + 2),
          ),
          (
            'stack-upper',
            hit(content, 3, stack.sourceStart, stack.sourceStart + 2),
          ),
          (
            'stack-lower',
            hit(content, 3, stack.separator + 1, stack.separator + 3),
          ),
          ('authored-light', hit(content, 4, 0, 2)),
          ('authored-dark', hit(content, 5, 0, 2)),
        ];
        for (final (name, selected) in phases) {
          active.value = selected;
          await tester.pump();
          final selectedRects = <Rect>[];
          final foregroundColors = <int>{};
          void collectInk(InlineSpan span, [Color? inherited]) {
            final color = span.style?.color ?? inherited;
            if (span is TextSpan) {
              if (span.text?.isNotEmpty == true && color != null) {
                foregroundColors.add(rgba(color));
              }
              for (final child in span.children ?? const <InlineSpan>[]) {
                collectInk(child, color);
              }
            }
          }

          var background = theme.colorScheme.primaryContainer;
          void add(RenderBox box, List<Rect> rects) => selectedRects.addAll(
            rects.map(
              (r) => MatrixUtils.transformRect(box.getTransformTo(render), r),
            ),
          );
          if (name == 'ruby-base') {
            collectInk(ruby.layout.base);
            add(
              tester.renderObject(find.byType(ReaderRuby)),
              ruby.layout.selectedBoxes(ruby.highlight, ruby.sourceStart),
            );
          } else if (name.startsWith('stack')) {
            collectInk(
              name == 'stack-upper' ? stack.layout.upper : stack.layout.lower,
            );
            add(
              tester.renderObject(find.byType(ReaderInlineStack)),
              stack.layout.selectedBoxes(
                stack.highlight,
                stack.sourceStart,
                stack.separator,
              ),
            );
          } else {
            for (final box in tester.renderObjectList<ReaderSearchTextRender>(
              find.byType(ReaderPaintedSearchText),
            )) {
              if (box.configuration.highlight.blockIndex ==
                  selected.blockIndex) {
                final paragraph = tester.renderObject<RenderParagraph>(
                  find
                      .descendant(
                        of: find.byWidget(box.configuration),
                        matching: find.byType(RichText),
                      )
                      .last,
                );
                collectInk(paragraph.text);
                final canvas = TestRecordingCanvas();
                box.paint(TestRecordingPaintingContext(canvas), Offset.zero);
                background =
                    (canvas.invocations
                                .firstWhere(
                                  (c) => c.invocation.memberName == #drawRect,
                                )
                                .invocation
                                .positionalArguments[1]
                            as Paint)
                        .color;
              }
              add(box, box.selectedBoxes);
            }
          }
          expect(selectedRects, isNotEmpty);
          if (name == 'body') {
            expect(
              background.toARGB32(),
              theme.colorScheme.primaryContainer.toARGB32(),
            );
          }
          final marked = await capture(), ink = <int, int>{};
          var backgroundPixels = 0;
          for (var y = 0; y < baseline.height; y++) {
            for (var x = 0; x < baseline.width; x++) {
              final at = Offset(x + .5, y + .5),
                  offset = (y * baseline.width + x) * 4;
              final before = baseline.bytes.getUint32(offset),
                  after = marked.bytes.getUint32(offset);
              if (selectedRects.any((r) => r.contains(at))) {
                if (after == rgba(background)) {
                  backgroundPixels++;
                }
                if (foregroundColors.contains(before)) {
                  ink.update(before, (n) => n + 1, ifAbsent: () => 1);
                }
              } else if (!selectedRects.any((r) => r.inflate(1).contains(at))) {
                expect(
                  after,
                  before,
                  reason: '$palette/$name paints outside the selected glyphs',
                );
              }
            }
          }
          expect(
            backgroundPixels,
            greaterThan(0),
            reason: '$palette/$name uses an opaque theme accent surface',
          );
          final foreground = ink.keys.reduce(
            (a, b) => ink[a]! > ink[b]! ? a : b,
          );
          if (name.startsWith('authored')) {
            expect(
              readerColorContrast(
                Color((foreground >> 8) | ((foreground & 255) << 24)),
                background,
              ),
              greaterThanOrEqualTo(4.5),
            );
          }
          var preserved = 0;
          for (var y = 0; y < baseline.height; y++) {
            for (var x = 0; x < baseline.width; x++) {
              final offset = (y * baseline.width + x) * 4;
              if (selectedRects.any(
                    (r) => r.contains(Offset(x + .5, y + .5)),
                  ) &&
                  baseline.bytes.getUint32(offset) == foreground) {
                expect(
                  marked.bytes.getUint32(offset),
                  foreground,
                  reason: '$palette/$name must paint the original ink last',
                );
                preserved++;
              }
            }
          }
          expect(preserved, greaterThan(0));
          expect(controller.layoutGeneration, generation);
          expect(controller.capture(), position);
          expect(controller.inspectDisplayedPage()!.page, same(page));
          await screenshot(tester, boundary, '$palette-$name-highlight');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('one hit across authored inks keeps both readable without reflow', (
    tester,
  ) async {
    await fonts(tester);
    final theme = readerTheme(
      ReaderSettings(themeMode: ReaderThemeMode.light),
      Brightness.light,
    );
    final content = ChapterContent(
      key: key,
      title: 'Mixed ink',
      blocks: paragraphs(
        '<p style="color:white;background-color:#333333">A<span style="color:#a0b8a4">B</span></p>',
      ),
    );
    final active = ValueNotifier<LocalSearchBodyHit?>(null),
        controller = PagedReaderController(),
        boundary = GlobalKey();
    addTearDown(active.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 400,
                height: 200,
                child: ColoredBox(
                  color: theme.scaffoldBackgroundColor,
                  child: ReaderSearchHighlightScope(
                    active: active,
                    content: content,
                    child: PagedReaderViewport(
                      content: content,
                      controller: controller,
                      textStyle: TextStyle(
                        fontSize: 36,
                        height: 1.6,
                        color: theme.colorScheme.onSurface,
                      ),
                      turnStyle: PageTurnStyle.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    Future<ByteData> pixels() async => (await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      image.dispose();
      return bytes;
    }))!;
    final before = await pixels(),
        position = controller.capture(),
        page = controller.inspectDisplayedPage()!.page,
        generation = controller.layoutGeneration;
    await screenshot(tester, boundary, 'mixed-ink-unmarked');
    active.value = hit(content, 0, 0, 2);
    await tester.pump();
    final box = tester.renderObject<ReaderSearchTextRender>(
      find.byType(ReaderPaintedSearchText),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byType(ReaderPaintedSearchText),
            matching: find.byType(RichText),
          )
          .last,
    );
    final canvas = TestRecordingCanvas();
    box.paint(TestRecordingPaintingContext(canvas), Offset.zero);
    final fills = canvas.invocations
        .where((c) => c.invocation.memberName == #drawRect)
        .map(
          (c) => (
            rect: c.invocation.positionalArguments[0] as Rect,
            color: (c.invocation.positionalArguments[1] as Paint).color,
          ),
        )
        .toList();
    final start = paragraph.text
        .toPlainText(includeSemanticsLabels: false)
        .indexOf('AB');
    expect(start, greaterThanOrEqualTo(0));
    final after = await pixels();
    for (final (index, ink) in [
      Colors.white,
      const Color(0xffa0b8a4),
    ].indexed) {
      final glyph = MatrixUtils.transformRect(
        paragraph.getTransformTo(box),
        paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: start + index,
                extentOffset: start + index + 1,
              ),
            )
            .single
            .toRect(),
      );
      final background = Color(
        fills.lastWhere((f) => f.rect.contains(glyph.center)).color.toARGB32(),
      );
      expect(
        readerColorContrast(ink, background),
        greaterThanOrEqualTo(4.5),
        reason: 'Each actual painted style run must remain readable',
      );
      final argb = ink.toARGB32(),
          rgba = ((argb & 0xffffff) << 8) | (argb >> 24);
      var preserved = 0;
      for (var offset = 0; offset < before.lengthInBytes; offset += 4) {
        if (before.getUint32(offset) == rgba) {
          expect(
            after.getUint32(offset),
            rgba,
            reason: 'Keep original authored ink',
          );
          preserved++;
        }
      }
      expect(preserved, greaterThan(0));
    }
    expect(controller.layoutGeneration, generation);
    expect(controller.capture(), position);
    expect(controller.inspectDisplayedPage()!.page, same(page));
    await screenshot(tester, boundary, 'mixed-ink-highlight');
    active.value = null;
    await tester.pump();
    expect((await pixels()).buffer.asUint8List(), before.buffer.asUint8List());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'actual pages, chunks, dual columns and reflow retain bounds and source identity',
    (tester) async {
      await fonts(tester);
      final content = ChapterContent(
        key: key,
        title: 'Source geometry',
        blocks: [
          ParagraphBlock(text: '前文😀e\u0301重复。' * 600),
          ParagraphBlock(text: '前文😀e\u0301重复。' * 4),
        ],
      );
      final active = ValueNotifier<LocalSearchBodyHit?>(null),
          controller = PagedReaderController(),
          boundary = GlobalKey();
      addTearDown(active.dispose);
      Future<void> mount(double width, int columns, {double font = 20}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: shioriTheme(Brightness.light),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                    width: width,
                    height: 300,
                    child: ReaderSearchHighlightScope(
                      active: active,
                      content: content,
                      child: PagedReaderViewport(
                        content: content,
                        controller: controller,
                        maxChunkCodePoints: 800,
                        columns: columns,
                        textStyle: TextStyle(fontSize: font, height: 1.6),
                        turnStyle: PageTurnStyle.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount(360, 1);
      final before = controller.inspectDisplayedPage()!,
          position = controller.capture(),
          epoch = controller.layoutGeneration;
      final last = before.page.fragments.last, chunk = before.chunks[last.unit];
      final edge = chunk.start + last.end;
      await screenshot(tester, boundary, 'cross-page-unmarked');
      active.value = hit(content, 0, edge - 3, edge + 3);
      await tester.pump();
      expect(boxes(tester), isNotEmpty);
      expect(controller.capture(), position);
      expect(controller.layoutGeneration, epoch);
      expect(controller.inspectDisplayedPage()!.page.start, before.page.start);
      expect(controller.inspectDisplayedPage()!.page.end, before.page.end);
      await screenshot(tester, boundary, 'cross-page-highlight-before');
      unawaited(controller.next());
      await tester.pumpAndSettle();
      expect(
        boxes(tester),
        isNotEmpty,
        reason:
            'the continuation paints only the selected visible source range',
      );
      await screenshot(tester, boundary, 'cross-page-highlight-after');
      final nextPosition = controller.capture();
      active.value = null;
      await tester.pump();
      expect(boxes(tester), isEmpty);
      expect(controller.capture(), nextPosition);
      await screenshot(tester, boundary, 'cross-page-highlight-cleared');
      // A hit in a later chunk must not mark an earlier copy of the same text.
      active.value = hit(content, 0, 1203, 1206);
      final restore = controller.restoreConfirmed(
        ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks[0].blockKey,
          blockIndex: 0,
          blockFraction:
              1203 / (content.blocks.first as ParagraphBlock).text.runes.length,
          chapterFraction: ReaderPosition.fractionFor(
            blockIndex: 0,
            blockFraction:
                1203 /
                (content.blocks.first as ParagraphBlock).text.runes.length,
            blockCount: 2,
          ),
        ),
        isCurrent: () => true,
      );
      await tester.pumpAndSettle();
      expect(await restore, isTrue);
      expect(boxes(tester), isNotEmpty);
      final source = controller.capture();
      await mount(760, 2, font: 24);
      expect(controller.inspectDisplayedPage()!.columns, 2);
      expect(controller.capture(), source);
      expect(boxes(tester), isNotEmpty);
      await screenshot(tester, boundary, 'dual-column-reflow-highlight');
      active.value = hit(content, 1, 3, 6);
      await tester.pump();
      expect(boxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ruby partial base and stacked upper/lower use their shaped glyph boxes',
    (tester) async {
      await fonts(tester);
      final blocks = paragraphs(
        '<p>前😀é<ruby>同名文字<rt>どうめいもじ</rt></ruby>中<ruby>同名文字<rt>ふたつめ</rt></ruby>尾 '
        '<span style="display:inline-block;text-align:center;line-height:1em;text-indent:0">UPPER<br/>下层文字</span> 末尾</p>',
      );
      final content = ChapterContent(
        key: key,
        title: 'Ruby and stack',
        blocks: blocks,
      );
      final active = ValueNotifier<LocalSearchBodyHit?>(null),
          controller = PagedReaderController(),
          boundary = GlobalKey();
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: shioriTheme(Brightness.dark),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: 620,
                  height: 300,
                  child: ReaderSearchHighlightScope(
                    active: active,
                    content: content,
                    child: PagedReaderViewport(
                      content: content,
                      controller: controller,
                      textStyle: const TextStyle(fontSize: 24, height: 1.6),
                      turnStyle: PageTurnStyle.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ruby = tester
          .widgetList<ReaderRuby>(find.byType(ReaderRuby))
          .toList();
      expect(ruby, hasLength(2));
      final page = controller.inspectDisplayedPage()!.page,
          position = controller.capture();
      await screenshot(tester, boundary, 'dark-ruby-unmarked');
      active.value = hit(
        content,
        0,
        ruby.first.sourceStart + 1,
        ruby.first.sourceStart + 2,
      );
      await tester.pump();
      final marked = ruby.first.layout.selectedBoxes(
        ruby.first.highlight,
        ruby.first.sourceStart,
      );
      expect(marked, hasLength(1));
      expect(
        marked.single.width,
        lessThan(ruby.first.layout.metrics.size.width / 2),
      );
      expect(
        marked.single.top,
        greaterThan(0),
        reason: 'annotation row is excluded',
      );
      expect(
        ruby.last.layout.selectedBoxes(
          ruby.last.highlight,
          ruby.last.sourceStart,
        ),
        isEmpty,
      );
      expect(
        boxes(tester),
        isEmpty,
        reason: 'placeholder box itself is never painted',
      );
      await screenshot(tester, boundary, 'dark-ruby-partial-highlight');
      final stack = tester.widget<ReaderInlineStack>(
        find.byType(ReaderInlineStack),
      );
      active.value = hit(
        content,
        0,
        stack.sourceStart + 1,
        stack.sourceStart + 3,
      );
      await tester.pump();
      final upper = stack.layout.selectedBoxes(
        stack.highlight,
        stack.sourceStart,
        stack.separator,
      );
      expect(upper, isNotEmpty);
      expect(
        upper.every(
          (r) => r.center.dy <= stack.layout.geometry.upper.bottom + .01,
        ),
        isTrue,
      );
      active.value = hit(content, 0, stack.separator + 2, stack.separator + 3);
      await tester.pump();
      final lower = stack.layout.selectedBoxes(
        stack.highlight,
        stack.sourceStart,
        stack.separator,
      );
      expect(lower, isNotEmpty);
      expect(
        lower.every(
          (r) => r.center.dy >= stack.layout.geometry.lower.top - .01,
        ),
        isTrue,
      );
      await screenshot(tester, boundary, 'dark-stack-lower-highlight');
      expect(controller.capture(), position);
      expect(controller.inspectDisplayedPage()!.page.end, page.end);
      expect(
        expandReaderGlyphSelection(
          '😀é',
          const TextSelection(baseOffset: 3, extentOffset: 4),
        ),
        const TextSelection(baseOffset: 2, extentOffset: 4),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hanging/table/decoration pieces preserve positions and author backgrounds',
    (tester) async {
      final blocks = paragraphs(
        '<p style="text-indent:-2em;padding-left:2em">${'前文重复内容。' * 10}</p>'
        '<table><tr><td>表格文字一</td><td>表格文字二</td></tr></table>'
        '<p style="background-color:#333333;color:white">作者背景文字</p>',
      );
      for (var index = 0; index < blocks.length; index++) {
        final content = ChapterContent(
          key: key,
          title: 'Flow',
          blocks: [blocks[index]],
        );
        final active = ValueNotifier<LocalSearchBodyHit?>(null),
            controller = PagedReaderController();
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(index),
            theme: shioriTheme(Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  height: 400,
                  child: ReaderSearchHighlightScope(
                    active: active,
                    content: content,
                    child: PagedReaderViewport(
                      content: content,
                      controller: controller,
                      turnStyle: PageTurnStyle.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final position = controller.capture(),
            page = controller.inspectDisplayedPage()!.page;
        active.value = hit(content, 0, 1, 3);
        await tester.pump();
        expect(boxes(tester), isNotEmpty);
        expect(controller.capture(), position);
        expect(controller.inspectDisplayedPage()!.page.end, page.end);
        active.value = null;
        await tester.pump();
        expect(boxes(tester), isEmpty);
        await tester.pumpWidget(const SizedBox());
        active.dispose();
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'active glyph background preserves inline images, links and page swipes',
    (tester) async {
      final media = MediaRef(
        sourceId: key.novelKey.sourceId,
        mediaId: 'inline',
      );
      final content = ChapterContent(
        key: key,
        title: 'Linked glyphs',
        blocks: [
          ParagraphBlock(
            text: '😀é 图\ufffc链接文字尾${' more text' * 100}',
            inlineImages: [
              InlineImage(offset: 5, media: media, widthEm: 1, heightEm: 1),
            ],
          ),
        ],
      );
      final link = LocalContentLink(
        source: key,
        sourceBlockKey: content.blocks.single.blockKey,
        label: '链接文字',
        sourceOffset: 6,
        sourceLength: 4,
        target: key,
      );
      final active = ValueNotifier<LocalSearchBodyHit?>(null),
          controller = PagedReaderController();
      addTearDown(active.dispose);
      LocalContentLink? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 300,
                child: ReaderSearchHighlightScope(
                  active: active,
                  content: content,
                  child: PagedReaderViewport(
                    content: content,
                    controller: controller,
                    contentLinks: [link],
                    onLink: (value) => tapped = value,
                    turnStyle: PageTurnStyle.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: find.byType(ReaderPaintedSearchText),
              matching: find.byType(RichText),
            )
            .last,
      );
      final imageOffset = paragraph.text
          .toPlainText(includeSemanticsLabels: false)
          .indexOf('\ufffc');
      List<Rect> imageBoxes() => paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: imageOffset,
              extentOffset: imageOffset + 1,
            ),
          )
          .map((b) => b.toRect())
          .toList();
      final before = imageBoxes(),
          page = controller.inspectDisplayedPage()!.page;
      active.value = hit(content, 0, 6, 10);
      await tester.pump();
      final render = tester.renderObject<ReaderSearchTextRender>(
        find.byType(ReaderPaintedSearchText),
      );
      expect(render.selectedBoxes, isNotEmpty);
      expect(imageBoxes(), before);
      expect(controller.inspectDisplayedPage()!.page.end, page.end);
      await tester.tapAt(
        render.localToGlobal(render.selectedBoxes.first.center),
      );
      await tester.pump();
      expect(tapped, same(link));
      final gesture = await tester.startGesture(
        render.localToGlobal(render.selectedBoxes.first.center),
      );
      await gesture.moveBy(const Offset(-24, 0));
      await gesture.moveBy(const Offset(-200, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.inspectDisplayedPage()!.page.start, isNot(page.start));
      expect(tester.takeException(), isNull);
    },
  );
}
