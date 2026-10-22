import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/reader/reader_inline_images.dart';
import 'package:shiori/features/reader/reader_superscript.dart';
import 'package:shiori/features/reader/reader_search_highlight.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/reader_authored_colors.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/reader_box.dart';
import 'package:shiori/features/reader/viewport/paragraph_flow.dart';
import '../../data/local/epub_table_test.dart' show tableHtml;
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import '../../data/local/epub_prose_semantics_test.dart' show paragraphs;
import 'local_search_test.dart' show fonts;
import 'search_highlight_test.dart' show screenshot, hit;

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double size) => size <= 24 ? size * 1.8 : size * 1.3;
  @override
  double get textScaleFactor => 1.3;
}

void main() {
  test(
    'superscript source mapping preserves emoji, combining text and ruby',
    () {
      const text = '😀A[12]e\u0301Z';
      final styles = [
        InlineTextStyle(start: 2, length: 4, superscript: true, fontScale: .75),
      ];
      final ruby = [InlineRuby(start: 6, length: 2, annotation: 'reading')];
      final collapsed = <(int, int)>[];
      final spans = readerInlineSpans(
        text: text,
        offset: 0,
        images: const [],
        styles: styles,
        ruby: ruby,
        style: const TextStyle(fontSize: 20),
        maxWidth: 300,
        onCollapsed: (s, l) => collapsed.add((s, l)),
      );
      expect(spans.whereType<WidgetSpan>(), hasLength(2));
      final display = TextSpan(
        children: spans,
      ).toPlainText(includeSemanticsLabels: false);
      expect(display, '😀A\uFFFC\uFFFCZ');
      expect(
        readerInlineSourceBoundary(text, 0, ruby, 4, collapsed: collapsed),
        7,
      );
      expect(
        readerInlineSourceBoundary(text, 0, ruby, 5, collapsed: collapsed),
        9,
      );
      expect(
        readerInlineSourceBoundary(
          text,
          0,
          ruby,
          display.length,
          collapsed: collapsed,
        ),
        text.length,
      );
      final tooWide = readerInlineSpans(
        text: '[12]',
        offset: 2,
        images: const [],
        styles: styles,
        style: const TextStyle(fontSize: 20),
        maxWidth: 1,
      );
      expect(tooWide.every((s) => s is TextSpan), isTrue);
      final long = readerInlineSpans(
        text: 'a' * 17,
        offset: 0,
        images: const [],
        styles: [InlineTextStyle(start: 0, length: 17, superscript: true)],
        style: const TextStyle(fontSize: 20),
      );
      expect(long.every((s) => s is TextSpan), isTrue);
    },
  );
  test('table labels and decorated links reserve superscript placeholders', () {
    const span =
        '<span style="vertical-align:super;font-size:.75em">[1]</span>';
    final table = paragraphs(
      tableHtml('<tr><td>$span</td><td>Body text</td></tr>'),
    ).single;
    expect(table.tableRow, isNotNull);
    const style = TextStyle(fontSize: 28, height: 1.6);
    final width = readerTableLabelWidth(table, style, TextScaler.linear(1.5));
    expect(width, greaterThan(0));
    final flow = readerParagraphFlow(
      block: table,
      text: table.text,
      offset: 0,
      width: 320,
      style: style,
      scaler: TextScaler.linear(1.5),
    );
    expect(flow.end, table.text.runes.length);
    final decorated = paragraphs(
      '<p><a href="#note"><span style="background-color:#eeeeee;vertical-align:super;font-size:.75em">[1]</span></a></p>',
    ).single;
    expect(decorated.linkDecoration, isNotNull);
    final link = readerLinkLayout(
      decorated,
      320,
      style,
      TextScaler.linear(1.5),
      TextDirection.ltr,
    );
    expect(link!.height, greaterThan(0));
  });

  for (final (width, scaler) in [
    (320.0, TextScaler.linear(1.5)),
    (390.0, const _NonlinearScaler()),
    (420.0, TextScaler.noScaling),
  ]) {
    testWidgets(
      'raised links share page metrics, source, semantics and highlight at $width',
      (tester) async {
        await fonts(tester);
        final semantics = tester.ensureSemantics();
        try {
          final block = paragraphs(
            '<p>${'😀e\u0301 正文<span style="font-size:.75em;vertical-align:super;border-bottom:1px dotted black">[12]</span>继续阅读。 ' * 12}</p>',
          ).single;
          final key = LocalBookIdentity.chapter(
            LocalBookIdentity.book('a' * 64),
            'raised',
          );
          final content = ChapterContent(
            key: key,
            title: 'Raised',
            blocks: [block],
          );
          final active = ValueNotifier<LocalSearchBodyHit?>(null);
          addTearDown(active.dispose);
          const style = TextStyle(
            inherit: false,
            fontFamily: 'Roboto',
            fontSize: 28,
            height: 1.6,
            color: Colors.black,
          );
          final layout = PageLayout(
            index: ChunkIndex(content, maxCodePoints: 80),
            width: width,
            height: 260,
            style: style,
            scaler: scaler,
            direction: TextDirection.ltr,
            paragraphSpacing: 16,
          );
          var cursor = const PageCursor(0, 0);
          final seen = StringBuffer();
          var pages = 0;
          while (true) {
            final page = layout.forward(cursor);
            if (page == null) break;
            for (final fragment in page.fragments) {
              seen.write(fragment.text);
              final sourceStart =
                  layout.index.chunks[fragment.unit].start + fragment.start;
              final sourceEnd =
                  layout.index.chunks[fragment.unit].start + fragment.end;
              final range = block.inlineStyles
                  .where(
                    (s) =>
                        s.superscript &&
                        s.start >= sourceStart &&
                        s.start + s.length <= sourceEnd,
                  )
                  .firstOrNull;
              if (range == null) continue;
              final note = LocalContentLink(
                source: key,
                sourceBlockKey: block.blockKey,
                label: '[12]',
                sourceOffset: range.start,
                sourceLength: range.length,
                target: key,
                targetBlockKey: block.blockKey,
              );
              LocalContentLink? tapped;
              final boundary = GlobalKey();
              await tester.pumpWidget(
                MaterialApp(
                  home: Scaffold(
                    body: Center(
                      child: RepaintBoundary(
                        key: boundary,
                        child: Container(
                          color: Colors.white,
                          width: width,
                          child: ReaderSearchHighlightScope(
                            active: active,
                            content: content,
                            child: ReaderLinkedText(
                              text: fragment.text!,
                              prefix: '',
                              blockKey: block.blockKey,
                              blockIndex: 0,
                              blockOffset: sourceStart,
                              inlineStyles: block.inlineStyles,
                              links: [note],
                              onLink: (l) => tapped = l,
                              style: style,
                              align: TextAlign.left,
                              scaler: scaler,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              final render = tester.renderObject<RenderParagraph>(
                find
                    .descendant(
                      of: find.byType(ReaderLinkedText),
                      matching: find.byType(RichText),
                    )
                    .first,
              );
              expect(
                render.size.height,
                lessThanOrEqualTo(fragment.height - 16 + .01),
              );
              final raised = find.byWidgetPredicate(
                (w) => w is ReaderSuperscript && w.sourceStart == range.start,
              );
              expect(raised, findsOneWidget);
              final widget = tester.widget<ReaderSuperscript>(raised);
              expect(widget.layout.text, '[12]');
              expect(widget.layout.rise, greaterThan(0));
              final child = tester.renderObject<RenderBox>(raised);
              final rect = MatrixUtils.transformRect(
                child.getTransformTo(render),
                Offset.zero & child.size,
              );
              // Flutter rounds line ascent to device pixels.
              expect(rect.top, greaterThanOrEqualTo(-1));
              expect(rect.bottom, lessThanOrEqualTo(render.size.height + .01));
              await tester.tapAt(
                child.localToGlobal(child.size.center(Offset.zero)),
              );
              expect(tapped, same(note));
              expect(tapped!.isFootnote, isFalse);
              expect(
                tester.getSemantics(raised).getSemanticsData().label,
                contains('[12]'),
              );
              expect(
                tester
                    .getSemantics(raised)
                    .getSemanticsData()
                    .hasAction(SemanticsAction.tap),
                isTrue,
              );
              final before = render.size.height;
              active.value = hit(content, 0, range.start + 1, range.start + 3);
              await tester.pump();
              expect(
                widget.layout.selectedBoxes(
                  widget.highlight,
                  widget.sourceStart,
                ),
                isNotEmpty,
              );
              expect(render.size.height, before);
              if (pages == 0) {
                await screenshot(
                  tester,
                  boundary,
                  'superscript-${width.toInt()}',
                );
              }
            }
            pages++;
            cursor = page.end;
          }
          expect(pages, greaterThan(1));
          expect(seen.toString(), block.text);
          final reverse = <String>[];
          while (true) {
            final page = layout.backward(cursor);
            if (page == null) break;
            reverse.add(page.fragments.map((f) => f.text ?? '').join());
            cursor = page.start;
          }
          expect(reverse.reversed.join(), block.text);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  for (final (paper, size, width) in [
    ('paper', 28.0, 320.0),
    ('warm', 24.0, 390.0),
    ('night', 20.0, 420.0),
  ]) {
    testWidgets(
      'inline borders preserve pagination and link hit boxes on $paper',
      (tester) async {
        await fonts(tester);
        final theme = readerTheme(
          ReaderSettings(
            paper: paper == 'warm' ? ReaderPaper.warm : ReaderPaper.paper,
            themeMode: paper == 'night'
                ? ReaderThemeMode.dark
                : ReaderThemeMode.light,
          ),
          Brightness.light,
        );
        final text = '甲😀e\u0301 文本跨行强调 ' * 20;
        final block = paragraphs(
          '<p><span style="border-bottom:2px dotted black"><b>$text</b></span></p>',
        ).single;
        final plain = ParagraphBlock(
          text: block.text,
          inlineStyles: [
            InlineTextStyle(
              start: 0,
              length: block.text.runes.length,
              bold: true,
            ),
          ],
        );
        final key = fixtureChapterKey(FixtureScenario.shortChapter);
        final style = TextStyle(
          fontSize: size,
          height: 1.6,
          color: theme.colorScheme.onSurface,
        );
        PageLayout layout(ParagraphBlock b) => PageLayout(
          index: ChunkIndex(
            ChapterContent(key: key, title: 'Inline', blocks: [b]),
          ),
          width: width,
          height: 280,
          style: style,
          scaler: TextScaler.noScaling,
          direction: TextDirection.ltr,
          paragraphSpacing: 16,
        );
        final decorated = layout(block), undecorated = layout(plain);
        var cursor = const PageCursor(0, 0);
        final seen = StringBuffer();
        var pageIndex = 0;
        while (true) {
          final page = decorated.forward(cursor);
          if (page == null) break;
          expect(
            (page.end.unit, page.end.offset),
            (
              undecorated.forward(cursor)!.end.unit,
              undecorated.forward(cursor)!.end.offset,
            ),
          );
          for (final fragment in page.fragments) {
            seen.write(fragment.text);
            final note = LocalContentLink(
              source: key,
              sourceBlockKey: block.blockKey,
              sourceOffset: fragment.start,
              sourceLength: fragment.end - fragment.start,
              label: 'link',
              target: key,
              targetBlockKey: block.blockKey,
            );
            LocalContentLink? activated;
            final boundary = GlobalKey();
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: Center(
                    child: RepaintBoundary(
                      key: boundary,
                      child: SizedBox(
                        width: width,
                        child: ColoredBox(
                          color: theme.scaffoldBackgroundColor,
                          child: ReaderLinkedText(
                            text: fragment.text!,
                            prefix: '',
                            blockOffset: fragment.start,
                            inlineStyles: block.inlineStyles,
                            links: [note],
                            onLink: (link) => activated = link,
                            style: style,
                            align: TextAlign.left,
                            scaler: TextScaler.noScaling,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            final render = tester.renderObject<RenderParagraph>(
              find
                  .descendant(
                    of: find.byType(ReaderLinkedText),
                    matching: find.byType(RichText),
                  )
                  .first,
            );
            expect(
              render.size.height,
              lessThanOrEqualTo(fragment.height - 16 + .01),
            );
            final boxes = render.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: fragment.text!.length),
            );
            expect(boxes, isNotEmpty);
            expect(
              boxes.every((b) => b.bottom <= render.size.height + .01),
              isTrue,
            );
            await tester.tapAt(
              render.localToGlobal(boxes.first.toRect().center),
            );
            expect(activated, same(note));
            if (pageIndex == 0) {
              await screenshot(tester, boundary, 'inline-border-$paper');
            }
          }
          pageIndex++;
          cursor = page.end;
        }
        expect(pageIndex, greaterThan(1));
        expect(seen.toString(), block.text);
        final colors = ReaderAuthoredColors(theme);
        final ink = readerAuthoredStyle(
          style,
          block.inlineStyles,
          0,
          resolveColor: (c) => colors.resolve(c, ReaderColorRole.foreground),
        );
        expect(ink.decorationStyle, TextDecorationStyle.dotted);
        expect(
          readerColorContrast(
            ink.decorationColor!,
            theme.scaffoldBackgroundColor,
          ),
          greaterThan(4.5),
        );
      },
    );
  }
}
