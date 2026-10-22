import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/reader/reader_inline_images.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/reader_authored_colors.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import '../../data/local/epub_prose_semantics_test.dart' show paragraphs;
import 'local_search_test.dart' show fonts;
import 'search_highlight_test.dart' show screenshot;

void main() {
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
