import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
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
      previewImage.onIntrinsicSize?.call(const Size(500, 500));
      await tester.pump();
      expect(controller.capture(), position);
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
      expect(route.isCurrent, isTrue);
      await tester.pump(kDoubleTapTimeout - const Duration(milliseconds: 1));
      expect(route.isCurrent, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
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
      expect(blankRoute.isCurrent, isTrue);
      await tester.pump(kDoubleTapTimeout);
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

  for (final (kind, reducedMotion) in [
    (PointerDeviceKind.touch, false),
    (PointerDeviceKind.mouse, false),
    (PointerDeviceKind.touch, true),
  ]) {
    testWidgets('$kind double tap zooms and resets, reduced=$reducedMotion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reducedMotion);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final env = FixtureEnvironment();
      final repo = MemoryImageRepository(resolve: (_) => env.source);
      addTearDown(() async {
        repo.close();
        await env.close();
      });
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showReaderImagePreview(
                context,
                block: ImageBlock(media: fixtureMediaRef(0)),
                repository: repo,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await frames(tester);
      final viewer = find.byType(InteractiveViewer);
      final transform = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!;
      final route = ModalRoute.of(tester.element(viewer))!;
      final local = tester.getSize(viewer).center(Offset.zero) / 2;
      final position = tester.getTopLeft(viewer) + local;
      Future<void> doubleTap() async {
        await tester.tapAt(position, kind: kind);
        await tester.pump(const Duration(milliseconds: 250));
        expect(route.isCurrent, isTrue);
        await tester.tapAt(position, kind: kind);
        await tester.pump();
      }

      await doubleTap();
      if (!reducedMotion) {
        expect(transform.value.getMaxScaleOnAxis(), 1);
        await tester.pump(ShioriMotion.feedback ~/ 2);
        expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
        expect(transform.value.getMaxScaleOnAxis(), lessThan(2));
        expect((transform.toScene(local) - local).distance, lessThan(.001));
        await tester.pump(ShioriMotion.feedback ~/ 2);
      }
      expect(transform.value.getMaxScaleOnAxis(), 2);
      expect((transform.toScene(local) - local).distance, lessThan(.001));
      await tester.pump(kDoubleTapTimeout);
      expect(route.isCurrent, isTrue);
      await doubleTap();
      if (!reducedMotion) {
        expect(transform.value.getMaxScaleOnAxis(), 2);
        await tester.pump(ShioriMotion.feedback ~/ 2);
        expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
        expect(transform.value.getMaxScaleOnAxis(), lessThan(2));
        await tester.pump(ShioriMotion.feedback ~/ 2);
      }
      expect(transform.value, Matrix4.identity());
      await tester.pump(kDoubleTapTimeout);
      expect(route.isCurrent, isTrue);

      // Direct manipulation takes over without the animation snapping back.
      await doubleTap();
      await tester.pump(ShioriMotion.feedback ~/ 2);
      final beforeInteraction = transform.value.clone();
      final pointers = <TestGesture>[];
      if (kind == PointerDeviceKind.touch) {
        for (final (id, direction) in [(1, -1.0), (2, 1.0)]) {
          pointers.add(
            await tester.startGesture(
              position + Offset(direction * 30, 0),
              pointer: id,
            ),
          );
        }
        for (final delta in [40.0, 30.0]) {
          await pointers[0].moveBy(Offset(-delta, 0));
          await pointers[1].moveBy(Offset(delta, 0));
          await tester.pump();
        }
      } else {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: position,
            scrollDelta: const Offset(0, -40),
          ),
        );
      }
      final interrupted = transform.value.clone();
      expect(interrupted, isNot(beforeInteraction));
      await tester.pump(ShioriMotion.feedback);
      expect(transform.value, interrupted);
      for (final pointer in pointers) {
        await pointer.up();
      }
      await tester.pumpAndSettle();

      // Esc during animation also retires a queued tap without popping Reader.
      await doubleTap();
      await tester.pump(ShioriMotion.feedback ~/ 4);
      await tester.tapAt(position, kind: kind);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(route.isCurrent, isFalse);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(repo.retainedBytes, 0);
    });
  }

  testWidgets('single-finger drag takes over an in-progress zoom', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: false);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final env = FixtureEnvironment();
    final repo = MemoryImageRepository(resolve: (_) => env.source);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      repo.close();
      await env.close();
    });
    await tester.pumpWidget(
      app(
        ReaderImagePreview(
          block: ImageBlock(media: fixtureMediaRef(0)),
          repository: repo,
        ),
      ),
    );
    await frames(tester);
    final viewer = find.byType(InteractiveViewer);
    final transform = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    final center = tester.getCenter(viewer);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(ShioriMotion.feedback ~/ 2);
    final midZoom = transform.value.clone();
    final scale = midZoom.getMaxScaleOnAxis();
    expect(scale, greaterThan(1));
    expect(scale, lessThan(2));

    final finger = await tester.startGesture(center);
    await finger.moveBy(const Offset(40, 24));
    await tester.pump();
    await finger.moveBy(const Offset(32, 20));
    await tester.pump();
    final dragged = transform.value.clone();
    expect(dragged.getMaxScaleOnAxis(), closeTo(scale, .001));
    expect(dragged.getTranslation().x, greaterThan(midZoom.getTranslation().x));
    expect(dragged.getTranslation().y, greaterThan(midZoom.getTranslation().y));

    // Hold the finger down beyond the zoom deadline to exclude release inertia.
    await tester.pump(ShioriMotion.feedback);
    expect(transform.value, dragged);
    await finger.moveBy(const Offset(24, 16));
    await tester.pump();
    final continued = transform.value.clone();
    expect(continued.getMaxScaleOnAxis(), closeTo(scale, .001));
    expect(
      continued.getTranslation().x,
      greaterThan(dragged.getTranslation().x),
    );
    expect(
      continued.getTranslation().y,
      greaterThan(dragged.getTranslation().y),
    );
    await tester.pump(ShioriMotion.feedback);
    expect(transform.value, continued);
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImagePreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
