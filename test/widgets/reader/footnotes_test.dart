import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/local_content_links.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

import '../../data/local/support/epub_fixtures.dart';

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets(
      '$language parsed footnote tap opens bottom sheet without turning',
      (tester) async {
        final annotation = List.filled(50, 'Original annotation.').join('\n');
        final files = epubFiles();
        files['OPS/text/a.xhtml'] = utf8.encode(
          '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
          '<p>Before<a epub:type="noteref" href="#n">'
          '<img src="note.png"/></a>after.</p>'
          '<aside epub:type="footnote" id="n">'
          '${List.filled(50, '<p>Original annotation.</p>').join()}'
          '</aside></body></html>',
        );
        final parsed = EpubParser(
          zipFiles(files),
          fixtureChapterKey(FixtureScenario.shortChapter).novelKey,
          'notes.epub',
        ).parse().content;
        final content = parsed.chapters.first;
        expect(
          (content.blocks.single as ParagraphBlock).text,
          'Before⁽¹⁾after.',
        );
        final note = LocalContentLink.fromJson(
          jsonDecode(jsonEncode(parsed.links.single.toJson()))
              as Map<String, dynamic>,
        );
        expect(note.unavailable, isNull);
        expect(note.footnoteText, annotation);
        final controller = PagedReaderController();
        var turns = 0;
        var centerTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 400,
                  child: PagedReaderViewport(
                    content: content,
                    controller: controller,
                    contentLinks: [note],
                    onBoundary: (_) => turns++,
                    onCenterTap: () => centerTaps++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = controller.capture();
        final rich = find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText(includeSemanticsLabels: false) ==
                  'Before⁽¹⁾after.',
        );
        final paragraph = tester.renderObject<RenderParagraph>(rich);
        final box = paragraph
            .getBoxesForSelection(
              const TextSelection(baseOffset: 6, extentOffset: 9),
            )
            .first;
        await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.text(language == 'en' ? 'Footnote ⁽¹⁾' : '脚注 ⁽¹⁾'),
          findsOneWidget,
        );
        expect(find.byType(SelectableText), findsOneWidget);
        expect(
          tester.widget<SelectableText>(find.byType(SelectableText)).data,
          annotation,
        );
        expect(turns, 0);
        expect(centerTaps, 0);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(controller.capture(), before);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('footnote sheet surface follows the reader theme', (
    tester,
  ) async {
    final theme = readerTheme(
      ReaderSettings(paper: ReaderPaper.warm),
      Brightness.light,
    );
    final content = ChapterContent(
      key: fixtureChapterKey(FixtureScenario.shortChapter),
      title: 'Notes',
      blocks: [ParagraphBlock(text: 'Before⁽¹⁾after.')],
    );
    final note = LocalContentLink(
      source: content.key,
      sourceBlockKey: content.blocks.single.blockKey,
      label: '⁽¹⁾',
      sourceOffset: 6,
      target: content.key,
      footnoteText: 'Annotation.',
    );
    final controller = PagedReaderController();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: Theme(
                data: theme,
                child: PagedReaderViewport(
                  content: content,
                  controller: controller,
                  contentLinks: [note],
                  onBoundary: (_) {},
                  onCenterTap: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rich = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText(includeSemanticsLabels: false) ==
              'Before⁽¹⁾after.',
    );
    final paragraph = tester.renderObject<RenderParagraph>(rich);
    final box = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 6, extentOffset: 9),
        )
        .first;
    await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material &&
              widget.color == theme.scaffoldBackgroundColor,
        ),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
