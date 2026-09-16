import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

void main() {
  testWidgets('long title and prose use inherited typography without clipping', (
    tester,
  ) async {
    final content = ChapterContent(
      key: LocalBookIdentity.chapter(LocalBookIdentity.book('a' * 64), 'test'),
      title: 'Long heading',
      blocks: [
        HeadingBlock(
          text: 'A long chapter heading with multiple lines',
          level: 2,
        ),
        ParagraphBlock(
          text: List.filled(
            70,
            'Some long text follows the heading.',
          ).join(' '),
        ),
      ],
    );
    final controller = PagedReaderController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'Ahem',
              letterSpacing: 2.5,
              wordSpacing: 1.5,
            ),
            child: Center(
              child: SizedBox(
                width: 300,
                height: 560,
                child: PagedReaderViewport(
                  content: content,
                  controller: controller,
                  textStyle: const TextStyle(fontSize: 20, height: 1.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    void expectNoClipping() {
      for (final element
          in find
              .descendant(
                of: find.byType(ReaderLinkedText),
                matching: find.byType(RichText),
              )
              .evaluate()) {
        final paragraph = element.renderObject as RenderParagraph;
        final natural = paragraph.getDryLayout(
          BoxConstraints(maxWidth: paragraph.size.width),
        );
        expect(
          natural.height,
          lessThanOrEqualTo(paragraph.constraints.maxHeight + .01),
          reason:
              'Every rendered line must fit the height reserved by pagination',
        );
      }
      expect(tester.takeException(), isNull);
    }

    expectNoClipping();
    final next = controller.next();
    await tester.pumpAndSettle();
    await next;
    expectNoClipping();
    final previous = controller.previous();
    await tester.pumpAndSettle();
    await previous;
    expectNoClipping();
  });
}
