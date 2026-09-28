import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_image_preview.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/shared/source_image.dart';
import 'source_image_test.dart' show app, frames;

void main() {
  testWidgets(
    'image tap previews without turning; zoom, pan and close preserve position',
    (tester) async {
      final env = FixtureEnvironment();
      final repo = MemoryImageRepository(resolve: (_) => env.source);
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.singleImage),
        title: 'Illustration',
        blocks: [
          ImageBlock(
            media: fixtureMediaRef(0),
            width: 400,
            height: 600,
            caption: 'Caption',
          ),
          ParagraphBlock(text: 'Following page'),
        ],
      );
      var boundaries = 0;
      await tester.pumpWidget(
        app(
          ReaderContentView(
            content: content,
            images: repo,
            actions: ReaderActions(
              nextChapter: () => boundaries++,
              previousChapter: () => boundaries++,
            ),
          ),
        ),
      );
      await frames(tester);
      final controller = tester
          .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
          .controller;
      final position = controller.capture();
      await tester.tap(find.byType(SourceImage).first);
      await frames(tester);
      expect(find.byType(ReaderImagePreview), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(boundaries, 0);
      expect(controller.capture(), position);
      final previewImage = tester.widget<SourceImage>(
        find.descendant(
          of: find.byType(ReaderImagePreview),
          matching: find.byType(SourceImage),
        ),
      );
      expect(previewImage.decodeScale, 2);
      expect(previewImage.onIntrinsicSize, isNull);
      final viewer = find.byType(InteractiveViewer);
      final transform = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!;
      final center = tester.getCenter(viewer);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pump();
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
      expect(find.byType(ReaderImagePreview), findsOneWidget);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, 100)),
      );
      await tester.pump();
      expect(transform.value.getMaxScaleOnAxis(), closeTo(1, .001));
      final first = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveTo(center - const Offset(80, 0));
      await second.moveTo(center + const Offset(80, 0));
      await tester.pump();
      await first.moveTo(center - const Offset(130, 0));
      await second.moveTo(center + const Offset(130, 0));
      await tester.pump();
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
      expect(transform.value.getMaxScaleOnAxis(), lessThanOrEqualTo(4));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final beforePan = transform.value.clone();
      await tester.drag(viewer, const Offset(60, 40));
      await tester.pumpAndSettle();
      expect(transform.value, isNot(beforePan));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, -40)),
      );
      await tester.pump();
      expect(find.byType(ReaderImagePreview), findsOneWidget);
      // An independent tap still dismisses after scale/pan/scroll.
      final route = ModalRoute.of(
        tester.element(find.byType(ReaderImagePreview)),
      )!;
      await tester.tapAt(center);
      // Pop is synchronous on tap release, without pumping a double-tap timeout.
      expect(route.isCurrent, isFalse);

      await frames(tester);
      expect(find.byType(ReaderImagePreview), findsNothing);
      expect(controller.capture(), position);
      expect(boundaries, 0);
      await tester.tap(find.byType(SourceImage).first);
      await frames(tester);
      // A tap released after Esc must not pop the Reader a second time.
      final pendingTap = await tester.startGesture(
        tester.getCenter(find.byType(InteractiveViewer)),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pendingTap.up();
      await tester.pump();
      await frames(tester);
      expect(find.byType(ReaderImagePreview), findsNothing);
      expect(controller.capture(), position);
      await tester.tap(find.byType(SourceImage).first);
      await frames(tester);
      await tester.binding.handlePopRoute();
      await frames(tester);
      expect(find.byType(ReaderImagePreview), findsNothing);
      expect(controller.capture(), position);
      await tester.tap(find.byType(SourceImage).first);
      await frames(tester);
      final stage = tester.getRect(find.byType(InteractiveViewer));
      final blankRoute = ModalRoute.of(
        tester.element(find.byType(ReaderImagePreview)),
      )!;
      await tester.tapAt(stage.topLeft + const Offset(3, 3));
      expect(blankRoute.isCurrent, isFalse);
      await frames(tester);
      expect(find.byType(ReaderImagePreview), findsNothing);
      expect(controller.capture(), position);
      await tester.tap(find.byType(SourceImage).first);
      await frames(tester);
      await tester.tap(find.byType(CloseButton));
      await frames(tester);
      expect(find.byType(ReaderImagePreview), findsNothing);
      expect(controller.capture(), position);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(repo.retainedBytes, 0);
      expect(repo.pendingCount, 0);
      expect(tester.takeException(), isNull);
      repo.close();
      await env.close();
    },
  );

  testWidgets('caption does not activate image tap', (tester) async {
    final env = FixtureEnvironment();
    final repo = MemoryImageRepository(resolve: (_) => env.source);
    var taps = 0;
    await tester.pumpWidget(
      app(
        Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: ReaderImage(
              block: ImageBlock(
                media: fixtureMediaRef(0),
                caption: 'Caption only',
              ),
              repository: repo,
              captionHeight: 40,
              onIntrinsicSize: (_) {},
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    await frames(tester);
    await tester.tap(find.text('Caption only'));
    expect(taps, 0);
    await tester.tap(find.byType(SourceImage));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    repo.close();
    await env.close();
  });
}
