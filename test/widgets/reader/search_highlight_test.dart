import 'dart:async';
import 'dart:io';
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
    'active glyph overlay preserves inline image boxes and link activation',
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
            text: '😀é 图\ufffc链接文字尾',
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
      expect(tester.takeException(), isNull);
    },
  );
}
