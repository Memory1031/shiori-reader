import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_image_preview.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import '../../data/local/epub_authored_layout_test.dart' show authoredContent;
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import 'local_reading_test.dart' show MemoryBooks;
import 'settings_test.dart' show Store;
import 'cross_chapter_drag_test.dart' show Images, Lease;
import 'full_width_drag_test.dart'
    show DragReader, heldDrag, nativeFrame, sourceFragments;

class PictureLease extends Lease {
  PictureLease(super.ref);
  final _picture = MemoryMedia(
    bytes: fixturePng(100, 160, 3),
    info: MediaInfo(format: MediaFormat.png, width: 100, height: 160),
  );
  @override
  MemoryMedia get data => _picture;
}

class PictureImages extends Images {
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    requests.add((ref, mode, cancellation));
    final lease = PictureLease(ref);
    leases.add(lease);
    return Success(
      LoadResult(
        value: lease,
        origin: LoadOrigin.memory,
        fetchedAt: DateTime.utc(2026),
      ),
    );
  }
}

Future<void> decoded(WidgetTester tester, {Finder? within}) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump();
    if (tester
        .widgetList<RawImage>(
          within == null
              ? find.byType(RawImage)
              : find.descendant(of: within, matching: find.byType(RawImage)),
        )
        .any((w) => w.image != null)) {
      return;
    }
  }
  fail('Synthetic image must decode');
}

void main() {
  for (final decorated in [false, true]) {
    testWidgets(
      '${decorated ? "decorated padding" : "plain text"} link taps once; hosted drag never taps',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final book = authoredContent(
          '<p style="text-align:center"><a href="#target" ${decorated ? 'style="background-color:#544f65;color:white;border-radius:30px;padding:.3em"' : ''}>Synthetic link</a></p>'
          '<p id="target">${'Following native text. ' * 150}</p>',
        );
        final repository = LocalReadingRepository(
          online: ForbiddenOnline(),
          local: MemoryBooks(
            LocalBookRecord(
              content: book,
              format: LocalBookFormat.epub,
              importedAt: DateTime.utc(2026),
            ),
          ),
        );
        final session = ReaderController(
          repository: repository,
          chapter: book.chapters.first.key,
        );
        await session.load();
        final pages = PagedReaderController();
        final chrome = ValueNotifier(false);
        var links = 0, toggles = 0;
        chrome.addListener(() => toggles++);
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (_) => ReaderContentView(
                content: book.chapters.first,
                session: session,
                viewportController: pages,
                chrome: chrome,
                settings: Store()
                  ..value = ReaderSettings(controlsHintSeen: true),
                actions: ReaderActions(
                  contentLink: (link) {
                    expect(
                      link.targetBlockKey,
                      book.chapters.first.blocks[1].blockKey,
                    );
                    links++;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = pages.capture();
        final rich = find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == 'Synthetic link',
        );
        final paragraph = tester.renderObject<RenderParagraph>(rich);
        final box = paragraph
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 14),
            )
            .first
            .toRect();
        final textPoint = paragraph.localToGlobal(box.center);
        await tester.tapAt(textPoint);
        await tester.pumpAndSettle();
        expect(links, 1);
        var dragPoint = textPoint;
        if (decorated) {
          final pill = find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color ==
                    const Color(0xff544f65),
          );
          dragPoint = tester.getRect(pill).topLeft + const Offset(2, 2);
          await tester.tapAt(dragPoint);
          await tester.pumpAndSettle();
          expect(links, 2);
        }
        final activations = links;
        expect(pages.capture(), before);
        expect(toggles, 0);
        final gesture = await heldDrag(tester, dragPoint);
        expect(nativeFrame(tester).progress, greaterThan(0));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(pages.capture(), isNot(before));
        expect(links, activations);
        expect(toggles, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        session.onDelete();
        await session.resourcesReleased;
        chrome.dispose();
      },
    );
  }

  for (final inline in [false, true]) {
    testWidgets(
      '${inline ? "inline" : "standalone"} picture preserves geometry and edge drag; preview isolates reader',
      (tester) async {
        final picture = fixtureMediaRef(0);
        final content = ChapterContent(
          key: fixtureChapterKey(FixtureScenario.singleImage),
          title: 'Synthetic illustration',
          blocks: [
            if (inline)
              ParagraphBlock(
                text: 'Inline \uFFFC text',
                inlineImages: [
                  InlineImage(
                    offset: 7,
                    media: picture,
                    widthEm: 2,
                    heightEm: 2,
                  ),
                ],
              )
            else
              ImageBlock(media: picture, width: 100, height: 160),
            for (var i = 0; i < 40; i++)
              ParagraphBlock(text: 'After image $i ${'synthetic text ' * 20}'),
          ],
        );
        final h = DragReader(content: content);
        final images = PictureImages();
        await h.open(tester, images: images);
        await decoded(tester);
        await tester.pumpAndSettle();
        final before = h.pages.capture();
        final fragments = sourceFragments(tester);
        final pictureFinder = inline
            ? find.byWidgetPredicate(
                (w) => w is ReaderLinkedText && w.text.contains('Inline'),
              )
            : find.byType(ReaderImage);
        final imageRect = tester.getRect(pictureFinder);
        if (!inline) {
          expect(imageRect.width, 330);
          expect(imageRect.height, 528);
          expect(imageRect.center.dy, 422);
        } else {
          expect(
            tester.getSize(
              find.byWidgetPredicate(
                (w) => w is SizedBox && w.width == 40 && w.height == 40,
              ),
            ),
            const Size(40, 40),
          );
        }
        final generation = h.pages.layoutGeneration;
        final edge = await heldDrag(tester, const Offset(389, 400));
        expect(nativeFrame(tester).progress, closeTo(140 / 390, 1e-9));
        expect(h.pages.capture(), before);
        expect(tester.getRect(pictureFinder), imageRect);
        expect(h.pages.layoutGeneration, generation);
        await edge.cancel();
        await tester.pumpAndSettle();
        expect(sourceFragments(tester), fragments);
        if (!inline) {
          // Image tap wins its normal arena, then the preview owns all new input.
          await tester.tap(pictureFinder);
          await decoded(tester, within: find.byType(ReaderImagePreview));
          await tester.pumpAndSettle();
          expect(find.byType(ReaderImagePreview), findsOneWidget);
          final previewDrag = await heldDrag(tester, const Offset(389, 400));
          await previewDrag.up();
          await tester.pumpAndSettle();
          expect(h.pages.capture(), before);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(ReaderImagePreview), findsNothing);
          final drag = await heldDrag(tester, imageRect.center);
          await drag.up();
          await tester.pumpAndSettle();
          expect(find.byType(ReaderImagePreview), findsNothing);
          expect(h.pages.capture(), isNot(before));
        }
        await h.close(tester);
      },
    );
  }

  testWidgets(
    'chrome progress slider and modal dismissal never drag the reader',
    (tester) async {
      final h = DragReader();
      await h.open(tester);
      final before = h.pages.capture();
      h.chrome.value = true;
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ReaderBottomBar),
          matching: find.text('Chapter 0%'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
      final gesture = await heldDrag(
        tester,
        tester.getCenter(find.byType(Slider)),
        delta: 80,
      );
      expect(nativeFrame(tester).progress, 0);
      expect(h.pages.capture(), before);
      await gesture.cancel();
      await tester.pumpAndSettle();
      final sliderPosition = h.pages.capture();
      expect(
        sliderPosition!.chapterFraction,
        greaterThan(before!.chapterFraction),
      );
      expect(nativeFrame(tester).progress, 0);
      await tester.tapAt(const Offset(389, 100));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      expect(h.pages.capture(), sliderPosition);
      expect(nativeFrame(tester).progress, 0);
      // Closing chrome through its original content tap consumes that one tap.
      await tester.tapAt(const Offset(350, 400));
      await tester.pumpAndSettle();
      expect(h.chrome.value, isFalse);
      expect(h.pages.capture(), sliderPosition);
      // A blank tap has no newly added page or chrome action.
      await tester.tapAt(const Offset(389, 400));
      await tester.pumpAndSettle();
      expect(h.chrome.value, isFalse);
      expect(h.pages.capture(), sliderPosition);
      await h.close(tester);
    },
  );

  testWidgets(
    'Windows blank right mouse never drags; wheel burst turns once',
    (tester) async {
      final h = DragReader();
      await h.open(tester, size: const Size(1000, 700));
      final before = h.pages.capture();
      final mouse = await tester.startGesture(
        const Offset(999, 350),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.moveBy(const Offset(-240, 0));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(h.pages.capture(), before);
      expect(nativeFrame(tester).progress, 0);
      final context = await tester.startGesture(
        const Offset(999, 350),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await context.up();
      await tester.pumpAndSettle();
      expect(find.text('Reading settings'), findsOneWidget);
      expect(h.pages.capture(), before);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.sendEventToBinding(
          const PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: Offset(999, 350),
            scrollDelta: Offset(0, 120),
          ),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
      expect(h.pages.capture(), isNot(before));
      final back = h.pages.previous();
      await tester.pumpAndSettle();
      await back;
      expect(h.pages.capture(), before);
      await h.close(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
