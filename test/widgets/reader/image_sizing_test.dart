import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_margin.dart';
import 'package:shiori/features/reader/reader_image_preview.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/shared/source_image.dart';
import 'settings_test.dart' show Store;
import '../../data/local/epub_image_sizing_test.dart' as sizing show book;

class Images implements ImageRepository {
  Images(this.bytes);
  final Uint8List bytes;
  Completer<void>? gate;
  int loads = 0, closed = 0;
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    loads++;
    await gate?.future;
    return Success(
      LoadResult(
        value: Lease(
          MemoryMedia(
            bytes: bytes,
            info: MediaInfo(format: MediaFormat.png),
          ),
          () => closed++,
        ),
        origin: LoadOrigin.memory,
        fetchedAt: DateTime.utc(2026),
      ),
    );
  }
}

class Lease implements MediaLease {
  Lease(this.data, this.release);
  @override
  final MediaData data;
  final void Function() release;
  @override
  bool isClosed = false;
  @override
  MediaPersistence get persistence => MediaPersistence.memoryOnly;
  @override
  AppFailure? get persistenceFailure => null;
  @override
  Future<void> close() async {
    if (!isClosed) {
      isClosed = true;
      release();
    }
  }
}

Widget app(Widget child) => ShioriApp(
  locale: const Locale('en'),
  routes: AppRoutes(home: (_) => SourceImageDecodeScope(child: child)),
);
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

ChapterContent content({bool unknown = false, bool axes = false}) =>
    ChapterContent(
      key: fixtureChapterKey(FixtureScenario.longChapter),
      title: 'Original image fixture',
      blocks: [
        ParagraphBlock(text: 'Opening original text.'),
        ImageBlock(
          media: fixtureMediaRef(0),
          width: unknown ? null : 32,
          height: unknown ? null : 32,
          sizing: ImageSizing(
            alignment: ParagraphAlignment.center,
            height: axes ? LayoutLength(60) : null,
          ),
          layout: axes ? BlockBox(group: 0, width: 120) : null,
          caption: 'Original caption',
        ),
        ParagraphBlock(text: 'Following original prose. ' * 100),
      ],
    );

void main() {
  for (final wide in [false, true]) {
    testWidgets(
      'parsed fill page and HTML ornament paint their measured size ($wide)',
      (tester) async {
        tester.view.physicalSize = Size(wide ? 1280 : 500, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final store = Store()..value = ReaderSettings(controlsHintSeen: true);
        final parsed = sizing.book(
          '<div style="width:100%"><img src="../images/ornament.png"/></div>',
          size: 512,
        );
        final c = parsed.content.chapters.first;
        final images = Images(fixturePng(512, 512, 2));
        final controller = PagedReaderController();
        await tester.pumpWidget(
          app(
            ReaderContentView(
              content: c,
              images: images,
              settings: store,
              viewportController: controller,
            ),
          ),
        );
        await frames(tester);
        final picture = tester.getRect(find.byType(RawImage));
        final viewport = tester.getRect(find.byType(PagedReaderViewport));
        expect(picture.center.dx, closeTo(viewport.center.dx, .01));
        expect(picture.center.dy, closeTo(viewport.center.dy, .01));
        expect(picture.width, greaterThan(300));
        expect(picture.width, closeTo(picture.height, .01));
        expect(controller.inspectDisplayedPage()!.page.centered, isTrue);
        final ornament = sizing
            .book(
              '<p>Before</p><div style="text-align:center"><img width="40" height="20" src="../images/ornament.png"/></div><p>After</p>',
              size: 512,
            )
            .content
            .chapters
            .first;
        await tester.pumpWidget(
          app(
            ReaderContentView(
              key: const ValueKey('ornament'),
              content: ornament,
              images: images,
              settings: store,
            ),
          ),
        );
        await frames(tester);
        expect(tester.getSize(find.byType(RawImage)), const Size(40, 20));
        final reader = tester.widget<PagedReaderViewport>(
          find.byType(PagedReaderViewport),
        );
        final area = tester.getRect(find.byType(PagedReaderViewport));
        final columnWidth =
            (area.width - (reader.columns - 1) * readerColumnGap) /
            reader.columns;
        expect(
          tester.getRect(find.byType(RawImage)).center.dx,
          closeTo(area.left + columnWidth / 2, .01),
        );
        expect(tester.widget<RawImage>(find.byType(RawImage)).fit, BoxFit.fill);
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        expect(images.closed, images.loads);
      },
    );
  }
  for (final dpr in [1.0, 2.0]) {
    testWidgets(
      'Reader paints natural pixels, caption and preview without DPR sizing ($dpr)',
      (tester) async {
        tester.view.physicalSize = Size(900 * dpr, 700 * dpr);
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.reset);
        final images = Images(fixturePng(32, 32, 3));
        final store = Store()..value = ReaderSettings(controlsHintSeen: true);
        await tester.pumpWidget(
          app(
            ReaderContentView(
              content: content(),
              images: images,
              settings: store,
            ),
          ),
        );
        await frames(tester);
        final raw = tester.widget<RawImage>(find.byType(RawImage));
        expect(tester.getSize(find.byType(RawImage)), const Size(32, 32));
        expect((raw.image!.width, raw.image!.height), (32, 32));
        final picture = tester.getRect(find.byType(RawImage));
        final reader = tester.getRect(find.byType(ReaderImage));
        expect(picture.center.dx, closeTo(reader.center.dx, .01));
        expect(reader.height, greaterThan(32));
        expect(find.text('Original caption'), findsOneWidget);
        final viewport = tester.widget<PagedReaderViewport>(
          find.byType(PagedReaderViewport),
        );
        final anchor = viewport.controller.capture();
        await tester.tapAt(picture.center);
        await frames(tester);
        expect(find.byType(ReaderImagePreview), findsOneWidget);
        Navigator.of(tester.element(find.byType(ReaderImagePreview))).pop();
        await frames(tester);
        expect(viewport.controller.capture(), anchor);
        // Preview owns a second, independent media lease.
        expect(images.loads, 2);
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        expect(images.closed, images.loads);
      },
    );
  }
  testWidgets(
    'two authored axes paint the same shape measured for pagination',
    (tester) async {
      final images = Images(fixturePng(32, 32, 4));
      final store = Store()..value = ReaderSettings(controlsHintSeen: true);
      await tester.pumpWidget(
        app(
          ReaderContentView(
            content: content(axes: true),
            images: images,
            settings: store,
          ),
        ),
      );
      await frames(tester);
      expect(tester.getSize(find.byType(RawImage)), const Size(120, 60));
      expect(tester.widget<RawImage>(find.byType(RawImage)).fit, BoxFit.fill);
      final geometry = tester
          .widget<ReaderImage>(find.byType(ReaderImage))
          .geometry!;
      expect(tester.getSize(find.byType(ReaderImage)).height, geometry.height);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(images.closed, images.loads);
    },
  );
  testWidgets(
    'late dimensions wait for cancelled drag, retain anchor and reuse decoded image',
    (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final images = Images(fixturePng(32, 32, 2))..gate = Completer<void>();
      final store = Store()..value = ReaderSettings(controlsHintSeen: true);
      await tester.pumpWidget(
        app(
          ReaderContentView(
            content: content(unknown: true),
            images: images,
            settings: store,
          ),
        ),
      );
      await frames(tester);
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      final controller = viewport.controller;
      final anchor = controller.capture();
      final before = tester
          .widget<ReaderImage>(find.byType(ReaderImage))
          .geometry!
          .size;
      expect(before.width, 180);
      final rect = tester.getRect(find.byType(PagedReaderViewport));
      final gesture = await tester.startGesture(
        Offset(rect.right - 40, rect.center.dy),
      );
      await gesture.moveBy(const Offset(-24, 0));
      await tester.pump(const Duration(milliseconds: 30));
      await gesture.moveBy(const Offset(-76, 0));
      await tester.pump();
      expect(controller.isTurning, isTrue);
      images.gate!.complete();
      await frames(tester);
      expect(
        tester.widget<ReaderImage>(find.byType(ReaderImage)).geometry!.size,
        before,
      );
      await gesture.cancel();
      await frames(tester);
      await tester.pumpAndSettle();
      expect(controller.capture(), anchor);
      expect(tester.getSize(find.byType(RawImage)), const Size(32, 32));
      expect(images.loads, 1);
      final state = tester.state(find.byType(SourceImage));
      tester.view.physicalSize = const Size(700, 600);
      await tester.pumpAndSettle();
      await frames(tester);
      expect(controller.capture(), anchor);
      expect(identical(tester.state(find.byType(SourceImage)), state), isTrue);
      expect(images.loads, 1);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(images.closed, 1);
    },
  );
}
