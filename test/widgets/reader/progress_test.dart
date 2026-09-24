import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/dev/ui/dev_reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/dev/viewport/reader_viewport.dart';

void main() {
  for (final mode in [ReaderMode.paged]) {
    testWidgets(
      'short chapter is saved as completed without gestures in ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final env = FixtureEnvironment(scenario: FixtureScenario.typography);
        await env.settings.save(
          ReaderSettings(mode: mode),
          cancellation: CancellationSource().token,
        );
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (_) => ReaderScreen(
                chapter: fixtureChapterKey(FixtureScenario.typography),
                repository: env.novels,
                library: env.library,
                settings: env.settings,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        final result = await env.library.getProgress(
          fixtureNovelKey(FixtureScenario.typography),
          cancellation: CancellationSource().token,
        );
        final progress = (result as Success<ReadingProgress?>).value!;
        expect(progress.completed, isTrue);
        expect(progress.position.blockIndex, 0);
        expect(progress.position.blockFraction, 0);
        expect(
          progress.snapshot,
          env.source.data.summary(FixtureScenario.typography),
        );
        if (mode == ReaderMode.scroll) {
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -450),
          );
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 400));
          final moved =
              (await env.library.getProgress(
                        fixtureNovelKey(FixtureScenario.typography),
                        cancellation: CancellationSource().token,
                      )
                      as Success<ReadingProgress?>)
                  .value!;
          expect(
            moved.position.chapterFraction,
            greaterThan(progress.position.chapterFraction),
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await env.close();
      },
    );
  }
  testWidgets(
    'restore emits only the stable semantic anchor and scrolling emits image height fractions',
    (tester) async {
      final key = fixtureChapterKey(FixtureScenario.singleImage);
      final content = ChapterContent(
        key: key,
        title: 'Image',
        blocks: [
          ImageBlock(media: fixtureMediaRef(0), width: 200, height: 2000),
        ],
      );
      final controller = ReaderViewportController();
      final samples = <ReaderPosition>[];
      var restoring = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 500,
            child: ReaderViewport(
              content: content,
              controller: controller,
              imageBuilder: (_, _) => const SizedBox(height: 2000),
              onRestoreStart: () => restoring = true,
              onPosition: (position, _) {
                restoring = false;
                samples.add(position);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks.first.blockKey,
        blockIndex: 0,
        blockFraction: .5,
        chapterFraction: .5,
      );
      samples.clear();
      controller.restore(target);
      expect(restoring, isTrue);
      await tester.pumpAndSettle();
      expect(samples, isNotEmpty);
      expect(samples.every((p) => (p.blockFraction - .5).abs() < .001), isTrue);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(samples.last.blockFraction, greaterThan(.5));
      expect(samples.last.blockFraction, lessThanOrEqualTo(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'paged restore is reported after layout, not with an intermediate start',
    (tester) async {
      final content = const FixtureData().content(
        FixtureScenario.extremeParagraph,
      );
      final controller = PagedReaderController();
      final samples = <ReaderPosition>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PagedReaderViewport(
            content: content,
            controller: controller,
            onPosition: (position, _) => samples.add(position),
          ),
        ),
      );
      await tester.pumpAndSettle();
      samples.clear();
      controller.restore(
        ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks.first.blockKey,
          blockIndex: 0,
          blockFraction: .7,
          chapterFraction: .7,
        ),
      );
      expect(samples, isEmpty);
      await tester.pumpAndSettle();
      expect(samples.every((p) => (p.blockFraction - .7).abs() < .001), isTrue);
      expect(samples, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
