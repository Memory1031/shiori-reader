import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/local_content_links.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets('$language footnote tap opens bottom sheet without turning', (
      tester,
    ) async {
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
        footnoteText: List.filled(50, 'Original annotation.').join('\n'),
      );
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
                  footnotes: [note],
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
      expect(turns, 0);
      expect(centerTaps, 0);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(controller.capture(), before);
      expect(tester.takeException(), isNull);
    });
  }
}
