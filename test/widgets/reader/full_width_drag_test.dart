import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/page_turn.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import 'settings_test.dart' show Store;
import 'cross_chapter_drag_test.dart' as book;
import 'completion_interaction_test.dart' as end;

class DragReader {
  DragReader({ChapterContent? content})
    : content =
          content ??
          ChapterContent(
            key: fixtureChapterKey(FixtureScenario.longChapter),
            title: 'Synthetic full width reader',
            blocks: [
              for (var i = 0; i < 60; i++)
                ParagraphBlock(
                  text: 'Paragraph $i ${'中文 synthetic reading。' * 20}',
                ),
            ],
          );
  final pages = PagedReaderController();
  final chrome = ValueNotifier(false);
  final navigator = GlobalKey<NavigatorState>();
  final ChapterContent content;
  final settings = Store();
  final shot = GlobalKey();

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double margin = 30,
    FakeViewPadding insets = const FakeViewPadding(),
    Offset offset = Offset.zero,
    book.Images? images,
  }) async {
    settings.value = ReaderSettings(
      controlsHintSeen: true,
      horizontalPadding: margin,
    );
    tester.view
      ..physicalSize = offset == Offset.zero
          ? size
          : Size(size.width + offset.dx + 80, size.height + offset.dy + 80)
      ..devicePixelRatio = 1
      ..padding = insets;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShioriApp(
        navigatorKey: navigator,
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => Stack(
            children: [
              Positioned(
                left: offset.dx,
                top: offset.dy,
                width: offset == Offset.zero ? null : size.width,
                height: offset == Offset.zero ? null : size.height,
                right: offset == Offset.zero ? 0 : null,
                bottom: offset == Offset.zero ? 0 : null,
                child: RepaintBoundary(
                  key: shot,
                  child: ReaderContentView(
                    content: content,
                    viewportController: pages,
                    chrome: chrome,
                    settings: settings,
                    images: images,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(pages.isRestoring, isFalse);
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('SHIORI_DRAG_EVIDENCE')) return;
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(shot))
          .toImage();
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final file = File('.tooling/full-width-drag/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    chrome.dispose();
  }
}

PageTurnFrame nativeFrame(WidgetTester tester) => tester
    .widget<PageTurnSlot>(
      find
          .descendant(
            of: find.byType(PagedReaderViewport),
            matching: find.byType(PageTurnSlot),
          )
          .first,
    )
    .frame;

List<(int, String)> sourceFragments(WidgetTester tester) => tester
    .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
    .map((text) => (text.blockOffset, text.text))
    .toList();

Future<TestGesture> heldDrag(
  WidgetTester tester,
  Offset start, {
  double delta = -140,
}) async {
  final gesture = await tester.startGesture(start);
  await gesture.moveBy(Offset(delta.sign * 24, 0));
  await tester.pump(const Duration(milliseconds: 30));
  await gesture.moveBy(Offset(delta / 2, 0));
  await tester.pump(const Duration(milliseconds: 30));
  await gesture.moveBy(Offset(delta / 2, 0));
  await tester.pump();
  return gesture;
}

Future<void> primeOffline(book.Harness h) async {
  final token = CancellationSource().token;
  await h.env.novels.loadCatalog(
    h.key(0).novelKey,
    mode: ReadMode.cacheFirst,
    cancellation: token,
  );
  await h.env.novels.loadDetail(
    h.key(0).novelKey,
    mode: ReadMode.cacheFirst,
    cancellation: token,
  );
}

void main() {
  testWidgets(
    'phone edge drag holds then commits exactly one native page',
    (tester) async {
      final h = DragReader();
      await h.open(tester);
      final surface = tester.getRect(find.byType(ReaderContentView));
      final content = tester.getRect(find.byType(PagedReaderViewport));
      final start = Offset(surface.right - 1, surface.center.dy);
      expect(surface.contains(start), isTrue);
      expect(content.contains(start), isFalse);
      expect(surface, const Rect.fromLTWH(0, 0, 390, 844));
      expect(content, const Rect.fromLTWH(30, 44, 330, 756));
      final owners = find.ancestor(
        of: find.byType(PagedReaderViewport),
        matching: find.byWidgetPredicate(
          (w) =>
              w is RawGestureDetector &&
              w.gestures.containsKey(HorizontalDragGestureRecognizer),
        ),
      );
      expect(owners, findsOneWidget);
      expect(tester.getRect(owners), surface);
      expect(
        tester
            .hitTestOnBinding(start)
            .path
            .any((entry) => entry.target == tester.renderObject(owners)),
        isTrue,
      );
      final before = h.pages.capture();
      final fragments = sourceFragments(tester);
      await h.screenshot(tester, 'phone-rest');
      var toggles = 0;
      h.chrome.addListener(() => toggles++);
      final gesture = await heldDrag(tester, start);
      expect(nativeFrame(tester).progress, greaterThan(0));
      expect(h.pages.capture(), before);
      await h.screenshot(tester, 'phone-edge-held');
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.up();
      await tester.pumpAndSettle();
      final next = h.pages.capture();
      expect(next, isNot(before));
      expect(sourceFragments(tester), isNot(fragments));
      expect(toggles, 0);
      // The same semantic next page as the existing controller, not two turns.
      final back = h.pages.previous();
      await tester.pumpAndSettle();
      await back;
      expect(h.pages.capture(), before);
      final forward = h.pages.next();
      await tester.pumpAndSettle();
      await forward;
      expect(h.pages.capture(), next);
      final previous = await heldDrag(
        tester,
        Offset(surface.left + 1, surface.center.dy),
        delta: 140,
      );
      expect(nativeFrame(tester).progress, greaterThan(0));
      expect(h.pages.capture(), next);
      await tester.pump(const Duration(milliseconds: 120));
      await previous.up();
      await tester.pumpAndSettle();
      expect(h.pages.capture(), before);
      expect(sourceFragments(tester), fragments);
      expect(toggles, 0);
      await h.close(tester);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  for (final geometry in [
    (
      name: 'large margins',
      size: const Size(390, 844),
      margin: 48.0,
      offset: Offset.zero,
      insets: const FakeViewPadding(),
      content: const Rect.fromLTWH(50, 44, 290, 756),
      columns: 1,
    ),
    (
      name: 'capped tablet',
      size: const Size(1000, 700),
      margin: 30.0,
      offset: Offset.zero,
      insets: const FakeViewPadding(),
      content: const Rect.fromLTWH(160, 44, 680, 612),
      columns: 1,
    ),
    (
      name: 'desktop spread',
      size: const Size(1920, 1080),
      margin: 30.0,
      offset: Offset.zero,
      insets: const FakeViewPadding(),
      content: const Rect.fromLTWH(244, 44, 1432, 992),
      columns: 2,
    ),
    (
      name: 'global offset',
      size: const Size(390, 844),
      margin: 30.0,
      offset: const Offset(80, 70),
      insets: const FakeViewPadding(),
      content: const Rect.fromLTWH(110, 114, 330, 756),
      columns: 1,
    ),
    (
      name: 'asymmetric landscape',
      size: const Size(980, 520),
      margin: 30.0,
      offset: Offset.zero,
      insets: const FakeViewPadding(left: 44, right: 12, top: 18, bottom: 8),
      content: const Rect.fromLTWH(166, 62, 680, 406),
      columns: 1,
    ),
  ]) {
    testWidgets(
      '${geometry.name}: unchanged layout, continuous edge/content drag and page grip',
      (tester) async {
        final h = DragReader();
        await h.open(
          tester,
          size: geometry.size,
          margin: geometry.margin,
          offset: geometry.offset,
          insets: geometry.insets,
        );
        final view = tester.widget<PagedReaderViewport>(
          find.byType(PagedReaderViewport),
        );
        final surface = tester.getRect(find.byType(PagedReaderDragSurface));
        final content = tester.getRect(find.byType(PagedReaderViewport));
        final page = tester.getRect(find.byType(ReaderContentView));
        expect(content, geometry.content);
        expect(
          surface,
          Rect.fromLTRB(
            page.left + geometry.insets.left,
            page.top + geometry.insets.top,
            page.right - geometry.insets.right,
            page.bottom - geometry.insets.bottom,
          ),
        );
        expect(view.columns, geometry.columns);
        expect(view.pageSize, geometry.size);
        expect(view.contentOrigin, content.topLeft - page.topLeft);
        final before = h.pages.capture();
        final fragments = sourceFragments(tester);
        final generation = h.pages.layoutGeneration;
        for (final y in [surface.top + 3, surface.bottom - 3]) {
          final gesture = await heldDrag(tester, Offset(surface.right - 1, y));
          final edgeFrame = nativeFrame(tester);
          expect(edgeFrame.progress, closeTo(140 / geometry.size.width, 1e-9));
          expect(edgeFrame.grip, pageTurnGrip(y - page.top, page.height));
          expect(h.pages.capture(), before);
          expect(tester.getRect(find.byType(PagedReaderViewport)), content);
          expect(h.pages.layoutGeneration, generation);
          await gesture.cancel();
          await tester.pumpAndSettle();
          final inside = await heldDrag(
            tester,
            Offset(
              content.left + 5,
              y.clamp(content.top + 3, content.bottom - 3),
            ),
          );
          // This sequence leaves the content for the left blank without restarting.
          expect(nativeFrame(tester).progress, edgeFrame.progress);
          await inside.cancel();
          await tester.pumpAndSettle();
          expect(nativeFrame(tester).progress, 0);
          expect(h.pages.capture(), before);
          expect(sourceFragments(tester), fragments);
          expect(h.pages.layoutGeneration, generation);
        }
        await h.close(tester);
      },
    );
  }

  for (final stop in [
    'small',
    'reverse',
    'pointer cancel',
    'resize',
    'route cover',
    'extra pointer',
  ]) {
    testWidgets('edge $stop retires one gesture; next drag still works', (
      tester,
    ) async {
      final h = DragReader();
      await h.open(tester);
      final before = h.pages.capture();
      final gesture = await heldDrag(
        tester,
        const Offset(389, 400),
        delta: stop == 'small' ? -50 : -160,
      );
      expect(nativeFrame(tester).progress, greaterThan(0));
      if (stop == 'reverse') {
        for (var i = 0; i < 5; i++) {
          await gesture.moveBy(
            const Offset(8, 0),
            timeStamp: Duration(milliseconds: 100 + i * 10),
          );
        }
        expect(nativeFrame(tester).progress, greaterThan(.28));
      } else if (stop == 'resize') {
        tester.view.physicalSize = const Size(420, 844);
        await tester.pump();
      } else if (stop == 'route cover') {
        unawaited(
          h.navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covered')),
            ),
          ),
        );
        await tester.pumpAndSettle();
      } else if (stop == 'extra pointer') {
        final extra = await tester.startGesture(const Offset(200, 450));
        await extra.cancel();
        await tester.pump();
        expect(nativeFrame(tester).progress, greaterThan(0));
      }
      if (stop == 'pointer cancel' || stop == 'extra pointer') {
        await gesture
            .cancel(); // Sends a real PointerCancel through hit testing.
      } else {
        if (stop == 'small') {
          await tester.pump(const Duration(milliseconds: 200));
        }
        await gesture.up(
          timeStamp: stop == 'reverse'
              ? const Duration(milliseconds: 145)
              : Duration.zero,
        );
      }
      await tester.pumpAndSettle();
      if (stop == 'route cover') {
        h.navigator.currentState!.pop();
        await tester.pumpAndSettle();
      }
      final actual = h.pages.capture()!;
      expect(
        (
          actual.blockKey,
          actual.blockIndex,
          actual.blockFraction,
          actual.chapterFraction,
        ),
        (
          before!.blockKey,
          before.blockIndex,
          before.blockFraction,
          before.chapterFraction,
        ),
      );
      expect(nativeFrame(tester).progress, 0);
      final surface = tester.getRect(find.byType(PagedReaderDragSurface));
      final next = await heldDrag(
        tester,
        Offset(surface.right - 1, surface.center.dy),
        delta: -160,
      );
      await tester.pump(const Duration(milliseconds: 140));
      await next.up();
      await tester.pumpAndSettle();
      expect(h.pages.capture(), isNot(before));
      final back = h.pages.previous();
      await tester.pumpAndSettle();
      await back;
      expect(h.pages.capture(), before);
      await h.close(tester);
    });
  }

  testWidgets(
    'moving second finger PointerCancel retires turn while first stays down',
    (tester) async {
      final h = DragReader();
      await h.open(tester);
      final before = h.pages.capture();
      final first = await heldDrag(tester, const Offset(389, 400), delta: -60);
      final firstProgress = nativeFrame(tester).progress;
      expect(firstProgress, lessThan(.28));
      final second = await tester.startGesture(const Offset(250, 450));
      for (var i = 0; i < 2; i++) {
        await second.moveBy(
          const Offset(-40, 0),
          timeStamp: Duration(milliseconds: 120 + i * 30),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(nativeFrame(tester).progress, greaterThan(firstProgress));
      expect(nativeFrame(tester).progress, greaterThan(.28));
      expect(h.pages.capture(), before);
      await second.cancel();
      await tester.pumpAndSettle();
      await first.up(timeStamp: const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(h.pages.capture(), before);
      expect(nativeFrame(tester).progress, 0);
      final next = await heldDrag(tester, const Offset(389, 400), delta: -160);
      await tester.pump(const Duration(milliseconds: 140));
      await next.up();
      await tester.pumpAndSettle();
      expect(h.pages.capture(), isNot(before));
      await h.close(tester);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'remaining finger PointerCancel never commits after first finger lifts',
    (tester) async {
      final h = DragReader();
      await h.open(tester);
      final before = h.pages.capture();
      final first = await heldDrag(tester, const Offset(389, 400), delta: -160);
      final second = await tester.startGesture(const Offset(250, 450));
      await first.up();
      await tester.pump();
      expect(h.pages.capture(), before);
      await second.cancel();
      await tester.pumpAndSettle();
      expect(h.pages.capture(), before);
      expect(nativeFrame(tester).progress, 0);
      await h.close(tester);
    },
  );

  for (final direction in [1, -1]) {
    testWidgets(
      'offline BookReader edge $direction continues after input locks and swaps once',
      (tester) async {
        final h = book.Harness();
        h.repository.forbidOnline = true;
        h.images.forbidOnline = true;
        await primeOffline(h);
        await h.open(tester, index: direction > 0 ? 0 : 1, offline: true);
        final original = book.active(tester);
        final before = original.viewportController!.capture();
        final sessions = h.library.sessions;
        final surface = tester.getRect(
          find.descendant(
            of: find.byWidgetPredicate((w) => identical(w, original)),
            matching: find.byType(PagedReaderDragSurface),
          ),
        );
        final gesture = await heldDrag(
          tester,
          Offset(
            direction > 0 ? surface.right - 1 : surface.left + 1,
            surface.center.dy,
          ),
          delta: -direction * 240,
        );
        await book.layoutFrames(tester);
        expect(book.frame(tester).progress, closeTo(.4, 1e-9));
        expect(book.active(tester).active, isFalse);
        expect(book.active(tester).session, same(original.session));
        expect(original.viewportController!.capture(), before);
        final extra = await tester.startGesture(surface.center);
        await extra.moveBy(Offset(-direction * 120, 0));
        await extra.cancel();
        await book.layoutFrames(tester);
        expect(book.frame(tester).progress, closeTo(.4, 1e-9));
        // The accepted ancestor recognizer survives the host's active=false.
        await gesture.moveBy(Offset(-direction * 60, 0));
        await book.layoutFrames(tester);
        expect(book.frame(tester).progress, closeTo(.5, 1e-9));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(book.active(tester).content.key, h.key(direction > 0 ? 1 : 0));
        expect(h.library.sessions, sessions + 1);
        expect(
          h.repository.requests.every((r) => r.$2 == ReadMode.cacheOnly),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await h.close(tester);
      },
    );
  }

  for (final waitingRelease in [false, true]) {
    testWidgets(
      'edge loading ${waitingRelease ? "wait bar" : "PointerCancel"} ignores late chapter',
      (tester) async {
        final h = book.Harness();
        final pending = Completer<Result<LoadResult<ChapterContent>>>();
        h.repository.holds[h.key(1)] = pending;
        h.repository.forbidOnline = true;
        await primeOffline(h);
        await h.open(tester, offline: true);
        final original = book.active(tester);
        final before = original.viewportController!.capture();
        final gesture = await heldDrag(
          tester,
          const Offset(599, 400),
          delta: -240,
        );
        await book.layoutFrames(tester);
        expect(book.frame(tester).progress, 0);
        if (waitingRelease) {
          await gesture.up();
          await book.layoutFrames(tester);
          expect(
            find.byKey(const ValueKey('cancel-chapter-turn')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('cancel-chapter-turn')));
        } else {
          await gesture.cancel();
        }
        await tester.pumpAndSettle();
        pending.complete(h.repository.result(h.key(1)));
        await tester.pumpAndSettle();
        expect(book.active(tester).session, same(original.session));
        expect(original.viewportController!.capture(), before);
        expect(h.library.sessions, 1);
        expect(
          h.library.writes.every(
            (p) => p.chapterKey == original.content.key && p.position == before,
          ),
          isTrue,
        );
        expect(book.frame(tester).progress, 0);
        await h.close(tester);
      },
    );
  }

  testWidgets(
    'last native edge reaches completion once; completion edge cancels and returns',
    (tester) async {
      final h = end.Harness();
      await h.open(tester, size: const Size(390, 844));
      final original = h.view(tester).session;
      final before = h.view(tester).viewportController!.capture();
      final gesture = await heldDrag(tester, const Offset(389, 690));
      expect(end.frame(tester).progress, closeTo(140 / 390, 1e-9));
      expect(end.frame(tester).grip, pageTurnGrip(690, 844));
      expect(h.view(tester).completion, isNull);
      expect(end.terminals(h), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(h.view(tester).completion, BookTerminalState.caughtUp);
      expect(end.terminals(h), 1);
      final cancelled = await heldDrag(
        tester,
        const Offset(1, 150),
        delta: 140,
      );
      expect(end.frame(tester).progress, closeTo(140 / 390, 1e-9));
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(h.view(tester).completion, BookTerminalState.caughtUp);
      final back = await heldDrag(tester, const Offset(1, 150), delta: 140);
      await back.up();
      await tester.pumpAndSettle();
      expect(h.view(tester).completion, isNull);
      expect(h.view(tester).session, same(original));
      expect(h.view(tester).viewportController!.capture(), before);
      expect(h.library.sessions, 1);
      expect(end.terminals(h), 1);
      await h.close(tester);
    },
  );
}
