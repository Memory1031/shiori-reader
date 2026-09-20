import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import 'settings_test.dart' show Store;

void main() {
  testWidgets(
    'wheel up at book start keeps the reader route open',
    (tester) async {
      final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ShioriApp(
          navigatorKey: navigator,
          routes: AppRoutes(home: (_) => const Scaffold()),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => BookReaderScreen(
            chapter: fixtureChapterKey(FixtureScenario.multiVolume),
            repository: env.novels,
            library: env.library,
            settings: Store()..value = ReaderSettings(controlsHintSeen: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reader = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView),
      );
      expect(reader.onPreviousChapter, isNull);
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      final start = viewport.controller.capture();
      for (var i = 0; i < 3; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: tester.getCenter(find.byType(PagedReaderViewport)),
            scrollDelta: const Offset(0, -120),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsOneWidget);
      expect(navigator.currentState!.canPop(), isTrue);
      expect(viewport.controller.capture(), start);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final size in [const Size(1920, 1080), const Size(2560, 1440)]) {
    testWidgets(
      'desktop input and overlays preserve position at $size',
      (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final pages = PagedReaderController();
        final content = ChapterContent(
          key: fixtureChapterKey(FixtureScenario.longChapter),
          title: 'Desktop input',
          blocks: [
            HeadingBlock(text: 'Chapter one', level: 1),
            for (var i = 0; i < 80; i++)
              ParagraphBlock(text: '$i ${'中文与 English desktop reading。' * 35}'),
          ],
        );
        await tester.pumpWidget(
          ShioriApp(
            routes: AppRoutes(
              home: (_) => ReaderContentView(
                content: content,
                viewportController: pages,
                settings: Store()
                  ..value = ReaderSettings(controlsHintSeen: true),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final start = pages.capture()!;
        Future<void> key(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        await key(LogicalKeyboardKey.pageDown);
        final next = pages.capture()!;
        expect(next.chapterFraction, greaterThan(start.chapterFraction));
        await key(LogicalKeyboardKey.pageUp);
        expect(pages.capture(), start);
        await key(LogicalKeyboardKey.arrowRight);
        expect(pages.capture(), next);
        await key(LogicalKeyboardKey.arrowLeft);
        expect(pages.capture(), start);

        Future<void> wheel(Offset delta, {Offset? position}) async {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              kind: PointerDeviceKind.mouse,
              position:
                  position ??
                  tester.getCenter(find.byType(PagedReaderViewport)),
              scrollDelta: delta,
            ),
          );
        }

        for (var i = 0; i < 8; i++) {
          await wheel(const Offset(0, 120));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(
          pages.capture(),
          next,
          reason: 'wheel burst must not skip pages',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await wheel(const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(pages.capture(), start);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await wheel(const Offset(0, 120));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await wheel(const Offset(120, 0));
        await tester.pumpAndSettle();
        expect(pages.capture(), start);

        await key(LogicalKeyboardKey.f2);
        for (final control in [
          find.byTooltip('Reading settings'),
          find.byIcon(Icons.list),
          find.text('Chapter 0%'),
        ]) {
          await tester.tap(control);
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsOneWidget);
          await key(LogicalKeyboardKey.pageDown);
          await wheel(const Offset(0, 120), position: const Offset(100, 100));
          await tester.pumpAndSettle();
          expect(
            pages.capture(),
            start,
            reason: 'modal must isolate reader input',
          );
          await key(LogicalKeyboardKey.escape);
          expect(find.byType(BottomSheet), findsNothing);
          expect(pages.capture(), start);
        }
        await key(LogicalKeyboardKey.pageDown);
        expect(
          pages.capture(),
          next,
          reason: 'focus returns after closing sheets',
        );
        for (final width in [850.0, size.width]) {
          tester.view.physicalSize = Size(width, size.height);
          await tester.pumpAndSettle();
          expect(pages.capture(), next);
          expect(
            tester
                .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
                .columns,
            width == 850 ? 1 : 2,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
