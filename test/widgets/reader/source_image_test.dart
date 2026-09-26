import '../../support/reader_actions.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_image_preview.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/dev/viewport/reader_viewport.dart';
import 'package:shiori/shared/source_image.dart';
import 'settings_test.dart' show Store;

Widget app(Widget child) => ShioriApp(
  locale: const Locale('en'),
  routes: AppRoutes(home: (_) => child),
);
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  testWidgets(
    'wide late intrinsic size pairs illustration without losing anchor or lease',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final env = FixtureEnvironment(
        scenario: FixtureScenario.unknownImageSize,
      );
      env.source.controls.delays[Operation.media] = const Duration(seconds: 2);
      final repo = MemoryImageRepository(resolve: (_) => env.source);
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.unknownImageSize),
        title: 'Late illustration',
        blocks: [
          ParagraphBlock(text: 'Before illustration.'),
          ImageBlock(media: fixtureMediaRef(1), caption: 'Retained caption'),
          ParagraphBlock(text: 'Following numbered prose. ' * 90),
        ],
      );
      final store = Store()..value = ReaderSettings(controlsHintSeen: true);
      await tester.pumpWidget(
        app(ReaderContentView(content: content, images: repo, settings: store)),
      );
      await tester.pump();
      PagedReaderViewport viewport() =>
          tester.widget(find.byType(PagedReaderViewport));
      String visible() => tester
          .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
          .map((w) => w.text)
          .join();
      final controller = viewport().controller;
      final anchor = controller.capture()!;
      final oldImage = tester.getRect(find.byType(ReaderImage));
      final imageState = tester.state(find.byType(SourceImage));
      final bounds = tester.getRect(find.byType(PagedReaderViewport));
      expect(viewport().columns, 2);
      expect(oldImage.center.dx, lessThan(bounds.center.dx));
      expect(visible(), contains('Following numbered prose.'));
      env.source.controls.delays.clear();
      await tester.pump(const Duration(seconds: 2));
      await frames(tester);
      expect(find.byType(RawImage), findsOneWidget);
      expect(
        identical(tester.state(find.byType(SourceImage)), imageState),
        isTrue,
      );
      final image = tester.getRect(find.byType(ReaderImage));
      final gutter = tester.getRect(
        find.byKey(const ValueKey('reader-spread-gutter')),
      );
      expect(image.left, greaterThanOrEqualTo(gutter.right));
      expect(image.center.dy, closeTo(bounds.center.dy, .01));
      expect(image.height, greaterThan(oldImage.height));
      expect(controller.capture(), anchor);
      expect(visible(), 'Before illustration.');
      expect(env.source.controls.calls[Operation.media], 1);
      expect(find.text('Retained caption'), findsOneWidget);
      expect(env.source.controls.calls[Operation.media], 1);

      // The paired image still opens the existing preview and returns to the
      // same spread, sharing the repository rather than re-fetching the image.
      await tester.tap(find.byType(ReaderImage));
      await frames(tester);
      expect(find.byType(ReaderImagePreview), findsOneWidget);
      Navigator.of(tester.element(find.byType(ReaderImagePreview))).pop();
      await frames(tester);
      expect(controller.capture(), anchor);
      expect(visible(), 'Before illustration.');
      final next = controller.next();
      await frames(tester);
      await next;
      expect(visible(), startsWith('Following numbered prose.'));
      expect(find.byType(ReaderImage), findsNothing);
      final previous = controller.previous();
      await frames(tester);
      await previous;
      expect(visible(), 'Before illustration.');
      expect(find.text('Retained caption'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(repo.retainedBytes, 0);
      expect(repo.pendingCount, 0);
      repo.close();
      await env.close();
    },
  );

  for (final decodeScale in [1.0, 2.0]) {
    testWidgets(
      'DPR and scale $decodeScale set decode width; late completion releases lease',
      (tester) async {
        final env = FixtureEnvironment();
        final repo = MemoryImageRepository(resolve: (_) => env.source);
        final pending = Completer<DecodedSourceImage>();
        var requestedWidth = 0;
        late MediaData data;
        await tester.pumpWidget(
          app(
            MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 3),
              child: Center(
                child: SizedBox(
                  width: 120,
                  height: 200,
                  child: SourceImage(
                    decodeScale: decodeScale,
                    media: fixtureMediaRef(0),
                    repository: repo,
                    decoder: (value, width) {
                      data = value;
                      requestedWidth = width;
                      return pending.future;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await frames(tester);
        expect(requestedWidth, (360 * decodeScale).toInt());
        expect(repo.retainedBytes, greaterThan(0));
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          pending.complete(await decodeSourceImage(data, requestedWidth));
        });
        await frames(tester);
        expect(repo.retainedBytes, 0);
        expect(tester.takeException(), isNull);
        repo.close();
        await env.close();
      },
    );
  }
  test(
    'decode budget caps both axes without upscaling and rejects extreme originals',
    () {
      expect(imageDecodeSize(64, 48, 800), (width: 64, height: 48));
      expect(imageDecodeSize(1000, 2000, 250), (width: 250, height: 500));
      final tall = imageDecodeSize(4000, 20000, 4000);
      expect(tall.width * tall.height, lessThanOrEqualTo(4000000));
      expect(
        () => imageDecodeSize(40000, 10, 100),
        throwsA(isA<ImageDecodeLimit>()),
      );
      expect(
        () => imageDecodeSize(20000, 20000, 100),
        throwsA(isA<ImageDecodeLimit>()),
      );
    },
  );
  testWidgets('real codec reports original size and decodes a thumbnail', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final decoded = await decodeSourceImage(
        MemoryMedia(
          bytes: fixturePng(400, 800, 7),
          info: MediaInfo(format: MediaFormat.png),
        ),
        100,
      );
      expect(decoded.intrinsicSize, const Size(400, 800));
      expect(decoded.image.width, 100);
      expect(decoded.image.height, 200);
      decoded.image.dispose();
    });
  });
  testWidgets(
    'local failure retry succeeds and unmount releases encoded memory',
    (tester) async {
      final env = FixtureEnvironment();
      env.source.controls.failNext(
        AppFailure(
          kind: FailureKind.network,
          operation: Operation.media,
          retryPolicy: RetryPolicy.manual,
        ),
      );
      final repo = MemoryImageRepository(resolve: (_) => env.source);
      await tester.pumpWidget(
        app(
          Center(
            child: SizedBox(
              width: 100,
              height: 150,
              child: SourceImage(media: fixtureMediaRef(0), repository: repo),
            ),
          ),
        ),
      );
      await frames(tester);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      await tester.tap(find.byTooltip('Retry'));
      await frames(tester);
      expect(find.byType(RawImage), findsOneWidget);
      expect(repo.retainedBytes, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(repo.retainedBytes, 0);
      expect(repo.pendingCount, 0);
      repo.close();
      await env.close();
    },
  );
  testWidgets('slow request is cancelled when its view leaves', (tester) async {
    final env = FixtureEnvironment();
    env.source.controls.delays[Operation.media] = const Duration(seconds: 20);
    final repo = MemoryImageRepository(resolve: (_) => env.source);
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 100,
          height: 150,
          child: SourceImage(media: fixtureMediaRef(0), repository: repo),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(repo.pendingCount, 0);
    expect(repo.retainedBytes, 0);
    repo.close();
    await env.close();
  });
  for (final paged in [true]) {
    testWidgets(
      'unknown dimensions preserve anchor and caption in ${paged ? 'paged' : 'scroll'} reader',
      (tester) async {
        final env = FixtureEnvironment();
        env.source.controls.delays[Operation.media] = const Duration(
          seconds: 2,
        );
        final repo = MemoryImageRepository(resolve: (_) => env.source);
        final content = ChapterContent(
          key: fixtureChapterKey(FixtureScenario.unknownImageSize),
          title: 'Mixed',
          blocks: [
            ImageBlock(
              media: fixtureMediaRef(0),
              caption: 'Illustration caption',
            ),
            for (var i = 0; i < 30; i++)
              ParagraphBlock(
                text: 'Paragraph $i. Reading text remains available.',
              ),
          ],
        );
        await tester.pumpWidget(
          app(ReaderContentView(content: content, images: repo)),
        );
        await tester.pump();
        if (!paged) {
          await chooseReaderMode(tester, 'Scroll');
          await tester.pump();
        }
        ReaderPosition? position() => paged
            ? tester
                  .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
                  .controller
                  .capture()
            : tester
                  .widget<ReaderViewport>(find.byType(ReaderViewport))
                  .controller
                  .capture();
        if (!paged) {
          await tester.drag(find.byType(ReaderViewport), const Offset(0, -70));
          await tester.pump(const Duration(milliseconds: 300));
        }
        final before = position()!;
        expect(find.text('Illustration caption'), findsWidgets);
        env.source.controls.delays.clear();
        await tester.pump(const Duration(seconds: 3));
        await frames(tester);
        expect(find.byType(RawImage), findsWidgets);
        expect(position()!.blockKey, before.blockKey);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        expect(repo.retainedBytes, 0);
        repo.close();
        await env.close();
      },
    );
  }
  testWidgets(
    'twenty images load only a bounded neighborhood and release after far jump',
    (tester) async {
      final env = FixtureEnvironment(scenario: FixtureScenario.twentyImages);
      final repo = MemoryImageRepository(resolve: (_) => env.source);
      await tester.pumpWidget(
        app(
          ReaderContentView(
            content: const FixtureData().content(FixtureScenario.twentyImages),
            images: repo,
          ),
        ),
      );
      await frames(tester);
      expect(env.source.controls.calls[Operation.media]!, lessThan(20));
      final controller = tester
          .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
          .controller;
      for (var i = 0; i < 8; i++) {
        final turn = controller.next();
        await frames(tester);
        await turn;
      }
      expect(find.byType(SourceImage).evaluate().length, lessThan(10));
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(repo.retainedBytes, 0);
      expect(repo.pendingCount, 0);
      repo.close();
      await env.close();
    },
  );
}
