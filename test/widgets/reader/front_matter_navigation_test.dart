import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/local_books/local_catalog.dart';
import 'package:shiori/features/reader/reader_progress_panel.dart';
import '../../data/local/epub_front_matter_test.dart'
    show frontMatterFiles, page, picture;
import '../../data/local/epub_structure_test.dart' show parse;
import 'logical_progress_test.dart' show mount, openProgress, closeOverlay;

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'supplemented contents and progress navigate on $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final content = parse(
          frontMatterFiles({
            'cover': page('Cover', picture),
            'a': page('A', '<p>A_START</p><p>A_END</p>'),
            'continuation': page('离线星空', '<p>CONTINUATION_END</p>'),
            'cover2': page('Cover', picture),
            'summary': page('简介', '<p>SUMMARY_MARKER</p>'),
            'b': page('B', '<p>B_START</p>'),
          }),
        ).content;
        final reader = await mount(tester, content: content);
        expect(find.text('Chapter 100%'), findsOneWidget);
        expect(find.text('Document 100%'), findsNothing);

        Future<void> contents() async {
          if (find.byIcon(Icons.list).evaluate().isEmpty) {
            await tester.sendKeyEvent(LogicalKeyboardKey.f2);
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byIcon(Icons.list));
          await tester.pumpAndSettle();
          expect(find.byType(LocalNavigationView), findsOneWidget);
        }

        await contents();
        final tree = tester.widget<LocalNavigationView>(
          find.byType(LocalNavigationView),
        );
        expect(tree.entries.map((e) => e.title), [
          'Cover',
          'First',
          'Cover',
          '简介',
          'Second',
        ]);
        await tester.tap(
          find.descendant(
            of: find.byType(LocalNavigationView),
            matching: find.text('First'),
          ),
        );
        await tester.pumpAndSettle();
        expect(reader.view(tester).content.key, content.chapters[1].key);
        await openProgress(tester);
        final panel = tester.widget<ReaderProgressPanel>(
          find.byType(ReaderProgressPanel),
        );
        expect(panel.chapterTitle, 'First');
        tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(1);
        await tester.pumpAndSettle();
        expect(reader.view(tester).content.key, content.chapters[2].key);
        expect(reader.view(tester).completion, isNull);
        expect(
          reader.view(tester).viewportController!.capture()!.blockFraction,
          1,
        );
        expect(find.byType(ReaderProgressPanel), findsNothing);

        await contents();
        await tester.tap(
          find
              .descendant(
                of: find.byType(LocalNavigationView),
                matching: find.text('Cover'),
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(reader.view(tester).content.key, content.chapters[3].key);
        await openProgress(tester);
        expect(
          tester
              .widget<ReaderProgressPanel>(find.byType(ReaderProgressPanel))
              .chapterTitle,
          'Cover',
        );
        await closeOverlay(tester);
        await contents();
        await tester.tap(
          find.descendant(
            of: find.byType(LocalNavigationView),
            matching: find.text('简介'),
          ),
        );
        await tester.pumpAndSettle();
        expect(reader.view(tester).content.key, content.chapters[4].key);
        await openProgress(tester);
        expect(
          tester
              .widget<ReaderProgressPanel>(find.byType(ReaderProgressPanel))
              .chapterTitle,
          '简介',
        );
        expect(find.text('Document 100%'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
