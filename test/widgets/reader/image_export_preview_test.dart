import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/image_export.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_image_preview.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/shared/image_export_scope.dart';
import 'package:shiori/shared/source_image.dart';

import 'source_image_test.dart' show frames;
import 'settings_test.dart' show Store;
import 'completion_test.dart' show CompletionRepository;
import '../../data/media/image_export_test.dart' show ExportRepository;

class _Exporter implements ImageExporter {
  int calls = 0;
  final asFiles = <bool>[];
  CancellationToken? token;
  ImageRepository? repository;
  Completer<ImageExportResult>? gate;
  ImageExportResult result = ImageExportResult.savedFile;
  bool acquireLease = false;
  @override
  Future<ImageExportResult> save({
    required ImageRepository repository,
    required MediaRef media,
    required CancellationToken cancellation,
    bool asFile = false,
  }) async {
    calls++;
    asFiles.add(asFile);
    token = cancellation;
    this.repository = repository;
    if (acquireLease) {
      final loaded = await repository.load(
        media,
        mode: ReadMode.cacheFirst,
        cancellation: cancellation,
      );
      if (loaded case Success(:final value)) {
        await value.value.close();
      } else {
        return ImageExportResult.sourceUnavailable;
      }
    }
    return gate == null ? result : await gate!.future;
  }
}

class _OfflineRepository extends ExportRepository {
  _OfflineRepository()
    : super(
        MemoryMedia(
          bytes: fixturePng(4, 4, 3),
          info: MediaInfo(format: MediaFormat.png),
        ),
      );
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    if (mode != ReadMode.cacheOnly) {
      throw StateError('Network must never be reached');
    }
    return super.load(ref, mode: mode, cancellation: cancellation);
  }
}

class _Book extends CompletionRepository {
  int chapterLoads = 0;
  @override
  ChapterContent content(ChapterKey key) => ChapterContent(
    key: key,
    title: 'Book',
    blocks: [
      ImageBlock(
        media: MediaRef(
          sourceId: key.novelKey.sourceId,
          mediaId: 'offline-image',
        ),
        width: 40,
        height: 40,
      ),
      ParagraphBlock(text: 'After'),
    ],
  );
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    chapterLoads++;
    return super.loadChapter(key, mode: mode, cancellation: cancellation);
  }
}

void main() {
  late FixtureEnvironment env;
  late MemoryImageRepository images;
  late _Exporter exporter;
  setUp(() {
    env = FixtureEnvironment();
    images = MemoryImageRepository(resolve: (_) => env.source);
    exporter = _Exporter();
  });
  tearDown(() async {
    images.close();
    await env.close();
  });
  Future<void> mount(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1,
    TargetPlatform platform = TargetPlatform.android,
    bool caption = true,
  }) async {
    await tester.pumpWidget(
      ShioriApp(
        locale: locale,
        overlayBuilder: (_, child) => ImageExportScope(
          exporter: exporter,
          child: Theme(
            data: ThemeData(platform: platform),
            child: MediaQuery(
              data: MediaQueryData(
                size: tester.view.physicalSize,
                textScaler: TextScaler.linear(textScale),
              ),
              child: child,
            ),
          ),
        ),
        routes: AppRoutes(
          home: (context) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () => showReaderImagePreview(
                  context,
                  block: ImageBlock(
                    media: fixtureMediaRef(0),
                    caption: caption ? 'Caption' : null,
                  ),
                  repository: images,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await frames(tester);
  }

  Future<void> zoom(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -100)),
    );
    await tester.pump();
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      greaterThan(1),
    );
  }

  testWidgets(
    'single flight, feedback and retry retain image/zoom; cancel silent',
    (tester) async {
      await mount(tester);
      await zoom(tester);
      final transform = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final matrix = transform.value.clone();
      final imageState = tester.state(find.byType(SourceImage));
      exporter.gate = Completer<ImageExportResult>();
      final save = find.byTooltip('Save original image');
      await tester.tap(save);
      await tester.tap(
        save,
      ); // Before rebuild too: method guard is synchronous.
      await tester.pump();
      expect(exporter.calls, 1);
      expect(find.byType(ReaderImagePreview), findsOneWidget);
      expect(find.byTooltip('Saving image…'), findsOneWidget);
      exporter.gate!.complete(ImageExportResult.storageFailure);
      await tester.pumpAndSettle();
      expect(transform.value, matrix);
      expect(
        identical(tester.state(find.byType(SourceImage)), imageState),
        isTrue,
      );
      exporter.gate = null;
      exporter.result = ImageExportResult.cancelled;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(exporter.calls, 2);
      expect(find.textContaining('Could not write'), findsNothing);
      expect(find.textContaining('Saved to'), findsNothing);
      expect(find.byType(ReaderImagePreview), findsOneWidget);
      expect(transform.value, matrix);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'late saved callback after pop cannot show feedback or pop Reader',
    (tester) async {
      await mount(tester);
      exporter.gate = Completer<ImageExportResult>();
      await tester.tap(find.byTooltip('Save original image'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      // PopScope cancels at pop, before the exit transition/dispose completes.
      expect(exporter.token!.isCancelled, isTrue);
      await tester.pumpAndSettle();
      exporter.gate!.complete(ImageExportResult.savedPhotos);
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.textContaining('Saved'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unsupported album format offers explicit file fallback only', (
    tester,
  ) async {
    await mount(tester);
    exporter.result = ImageExportResult.unsupportedFormat;
    await tester.tap(find.byTooltip('Save original image'));
    await tester.pumpAndSettle();
    expect(exporter.asFiles, [false]);
    expect(find.text('Save as file'), findsOneWidget);
    exporter.result = ImageExportResult.savedFile;
    await tester.tap(find.text('Save as file'));
    await tester.pumpAndSettle();
    expect(exporter.asFiles, [false, true]);
    expect(find.text('Saved to file'), findsOneWidget);
    expect(find.byType(ReaderImagePreview), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('SourceImage retry and trackpad gesture never dismiss preview', (
    tester,
  ) async {
    env.source.controls.failNext(
      AppFailure(
        kind: FailureKind.network,
        operation: Operation.media,
        retryPolicy: RetryPolicy.manual,
      ),
    );
    await mount(tester);
    final before = env.source.controls.calls[Operation.media]!;
    await tester.tap(find.byTooltip('Retry'));
    await tester.pump();
    await frames(tester);
    expect(env.source.controls.calls[Operation.media], before + 1);
    expect(find.byType(ReaderImagePreview), findsOneWidget);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, scale: 1.5, pan: const Offset(60, 20));
    await gesture.panZoomUpdate(center, scale: 2, pan: const Offset(80, 30));
    await gesture.panZoomEnd();
    await tester.pump();
    expect(find.byType(ReaderImagePreview), findsOneWidget);
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      greaterThan(1),
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    for (final language in ['en', 'zh']) {
      testWidgets(
        '$platform $language small screen / large type / accessible save',
        (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();
          await mount(
            tester,
            locale: Locale(language),
            textScale: 2.5,
            platform: platform,
            caption: language == 'en',
          );
          final label = language == 'en' ? 'Save original image' : '保存原图';
          expect(find.bySemanticsLabel(label), findsOneWidget);
          exporter.result = ImageExportResult.permissionDenied;
          await tester.tap(find.byTooltip(label));
          await tester.pumpAndSettle();
          expect(find.byType(ReaderImagePreview), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('Open'), findsOneWidget);
          semantics.dispose();
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  }
  testWidgets(
    'Reader saves share cached original and preserve both spread anchors',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      exporter.acquireLease = true;
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          overlayBuilder: (_, child) =>
              ImageExportScope(exporter: exporter, child: child),
          routes: AppRoutes(
            home: (_) => ReaderContentView(
              images: images,
              settings: Store()..value = ReaderSettings(controlsHintSeen: true),
              content: ChapterContent(
                key: fixtureChapterKey(FixtureScenario.singleImage),
                title: 'Spread',
                blocks: [
                  ImageBlock(
                    media: fixtureMediaRef(0),
                    width: 400,
                    height: 600,
                  ),
                  ImageBlock(
                    media: fixtureMediaRef(1),
                    width: 400,
                    height: 600,
                  ),
                  ParagraphBlock(text: 'Following'),
                ],
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      expect(viewport.columns, 2);
      final anchor = viewport.controller.capture();
      final requests = env.source.controls.calls[Operation.media];
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byType(ReaderImage).at(i));
        await frames(tester);
        await tester.tap(find.byTooltip('Save original image'));
        await tester.pumpAndSettle();
        expect(find.text('Saved to file'), findsOneWidget);
        await tester.tap(find.byType(CloseButton));
        await tester.pumpAndSettle();
        expect(viewport.controller.capture(), anchor);
        expect(env.source.controls.calls[Operation.media], requests);
      }
      expect(exporter.calls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'real offline Reader wrapper governs preview and export; no chapter reload',
    (tester) async {
      final offline = _OfflineRepository();
      final book = _Book();
      exporter.acquireLease = true;
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          overlayBuilder: (_, child) =>
              ImageExportScope(exporter: exporter, child: child),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: book.order.first,
              repository: book,
              images: offline,
              offline: true,
              settings: Store()..value = ReaderSettings(controlsHintSeen: true),
            ),
          ),
        ),
      );
      await frames(tester);
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      final anchor = viewport.controller.capture();
      final chapterLoads = book.chapterLoads;
      await tester.tap(find.byType(ReaderImage).first);
      await frames(tester);
      await tester.tap(find.byTooltip('Save original image'));
      await tester.pumpAndSettle();
      expect(find.text('Saved to file'), findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(offline.modes.length, greaterThanOrEqualTo(3));
      expect(offline.modes.every((mode) => mode == ReadMode.cacheOnly), isTrue);
      expect(viewport.controller.capture(), anchor);
      expect(book.chapterLoads, chapterLoads);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(offline.leases.every((lease) => lease.isClosed), isTrue);
    },
  );
}
