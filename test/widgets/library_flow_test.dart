import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/home/continue_reading_card.dart';
import 'package:shiori/features/home/continue_reading_row.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/novel_detail/detail_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/shared/widgets/book_cover.dart';
import 'reader/continue_test.dart' show seed;
import 'bookshelf_test.dart' show RemovalCache;

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      'unfinished resume priority reacts to writes and removals on $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(
          platform == TargetPlatform.windows
              ? const Size(1280, 720)
              : const Size(390, 844),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final env = FixtureEnvironment();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(env.close);
        });
        final token = CancellationSource().token;
        Future<ReadingProgress> save(
          FixtureScenario scenario,
          int day,
          BookTerminalState terminal,
        ) async {
          final key = fixtureChapterKey(scenario);
          final body =
              (await env.novels.loadChapter(
                        key,
                        mode: ReadMode.cacheFirst,
                        cancellation: token,
                      )
                      as Success<LoadResult<ChapterContent>>)
                  .value
                  .value;
          final block = body.blocks.length ~/ 2;
          final progress = ReadingProgress(
            snapshot: env.source.data.summary(scenario),
            chapterKey: key,
            chapterOrdinalSnapshot: 0,
            catalogRevision: 'fixture',
            position: ReaderPosition(
              contentRevision: body.contentRevision,
              blockKey: body.blocks[block].blockKey,
              blockIndex: block,
              blockFraction: .25,
              chapterFraction: ReaderPosition.fractionFor(
                blockIndex: block,
                blockFraction: .25,
                blockCount: body.blocks.length,
              ),
            ),
            completed: false,
            lastReadAt: DateTime.utc(2026, 1, day),
            bookProgress: BookProgressSnapshot(
              fraction: terminal == BookTerminalState.reading ? .45 : 1,
              chapterCount: 10,
              terminal: terminal,
            ),
          );
          final generation =
              (await env.library.beginProgressSession(
                        key.novelKey,
                        cancellation: token,
                      )
                      as Success<int>)
                  .value;
          expect(
            await env.library.saveProgress(
              progress,
              stamp: ProgressWriteStamp(generation: generation, sequence: 0),
              cancellation: token,
            ),
            const Success(true),
          );
          return progress;
        }

        final a = await save(
          FixtureScenario.shortChapter,
          1,
          BookTerminalState.reading,
        );
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            homeBuilder: (_, _) => ReadingHome(
              repository: env.novels,
              library: env.library,
              sources: [env.source.descriptor],
              settings: env.settings,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final controller = tester
            .widget<BookshelfView>(find.byType(BookshelfView))
            .controller;
        final resume = platform == TargetPlatform.windows
            ? find.byType(ContinueReadingRow)
            : find.byType(ContinueReadingCard);
        ReadingProgress displayed() => platform == TargetPlatform.windows
            ? tester.widget<ContinueReadingRow>(resume).progress
            : tester.widget<ContinueReadingCard>(resume).progress;
        void shows(ReadingProgress expected) {
          expect(resume, findsOneWidget);
          expect(displayed(), expected);
          expect(
            find.descendant(
              of: resume,
              matching: find.text(expected.snapshot.title),
            ),
            findsOneWidget,
          );
          expect(
            tester
                .widget<BookCover>(
                  find.descendant(of: resume, matching: find.byType(BookCover)),
                )
                .book,
            expected.snapshot,
          );
          expect(
            tester
                .widget<LinearProgressIndicator>(
                  find.descendant(
                    of: resume,
                    matching: find.byType(LinearProgressIndicator),
                  ),
                )
                .value,
            expected.bookProgress!.fraction,
          );
        }

        shows(a);
        final geometry = tester.getSize(resume);
        final b = await save(
          FixtureScenario.multiVolume,
          2,
          BookTerminalState.finished,
        );
        final unread = env.source.data.summary(FixtureScenario.longTitle);
        await env.library.putBookshelf(
          BookshelfEntry(snapshot: unread, addedAt: DateTime.utc(2026, 1, 3)),
          cancellation: token,
        );
        env.source.controls.calls.clear();
        await tester.pumpAndSettle();
        shows(a);
        expect(tester.getSize(resume), geometry);
        expect(controller.recent, [b, a]);
        expect(controller.sorted.map((e) => e.snapshot.key), [
          unread.key,
          b.novelKey,
          a.novelKey,
        ]);
        expect(env.source.controls.calls, isEmpty);
        expect(await controller.remove(b.novelKey), isTrue);
        await tester.pumpAndSettle();
        shows(a);
        await save(FixtureScenario.multiVolume, 2, BookTerminalState.finished);
        await tester.pumpAndSettle();
        shows(a);
        expect(await controller.remove(a.novelKey), isTrue);
        await tester.pumpAndSettle();
        shows(b);
        final resumed = await save(
          FixtureScenario.shortChapter,
          3,
          BookTerminalState.reading,
        );
        await tester.pumpAndSettle();
        shows(resumed);
        final ended = await save(
          FixtureScenario.shortChapter,
          4,
          BookTerminalState.finished,
        );
        await tester.pumpAndSettle();
        shows(ended);
        final updated = await save(
          FixtureScenario.multiVolume,
          5,
          BookTerminalState.reading,
        );
        await tester.pumpAndSettle();
        shows(updated);
        expect(await controller.remove(updated.novelKey), isTrue);
        await tester.pumpAndSettle();
        shows(ended);
        expect(await controller.remove(ended.novelKey), isTrue);
        await tester.pumpAndSettle();
        expect(resume, findsNothing);
        expect(controller.contains(unread.key), isTrue);
        final restored = await save(
          FixtureScenario.shortChapter,
          6,
          BookTerminalState.reading,
        );
        await tester.pumpAndSettle();
        shows(restored);
        expect(
          tester.widget<BookshelfView>(find.byType(BookshelfView)).controller,
          same(controller),
        );
        await tester.tap(
          find.descendant(of: resume, matching: find.text('Resume')),
        );
        await tester.pumpAndSettle();
        final reader = tester.widget<ReaderContentView>(
          find.byType(ReaderContentView),
        );
        expect(reader.content.key, restored.chapterKey);
        expect(reader.initialPosition, restored.position);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );

    testWidgets(
      'resume follows shelf removals on $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(
          platform == TargetPlatform.windows
              ? const Size(1280, 720)
              : const Size(390, 844),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final env = FixtureEnvironment();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(env.close);
        });
        final token = CancellationSource().token;
        final scenarios = [
          FixtureScenario.shortChapter,
          FixtureScenario.multiVolume,
        ];
        for (var i = 0; i < scenarios.length; i++) {
          final book = env.source.data.summary(scenarios[i]);
          await env.library.putBookshelf(
            BookshelfEntry(snapshot: book, addedAt: DateTime.utc(2026)),
            cancellation: token,
          );
          final generation =
              (await env.library.beginProgressSession(
                        book.key,
                        cancellation: token,
                      )
                      as Success<int>)
                  .value;
          await env.library.saveProgress(
            ReadingProgress(
              snapshot: book,
              chapterKey: fixtureChapterKey(scenarios[i]),
              chapterOrdinalSnapshot: 0,
              catalogRevision: 'fixture',
              position: ReaderPosition(
                contentRevision: 'fixture',
                blockKey: 'fixture',
                blockIndex: 0,
                blockFraction: 0,
                chapterFraction: 0,
              ),
              completed: false,
              lastReadAt: DateTime.utc(2026, 1, i + 1),
            ),
            stamp: ProgressWriteStamp(generation: generation, sequence: 0),
            cancellation: token,
          );
        }
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            homeBuilder: (_, _) => ReadingHome(
              repository: env.novels,
              library: env.library,
              sources: [env.source.descriptor],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final controller = tester
            .widget<BookshelfView>(find.byType(BookshelfView))
            .controller;
        final older = env.source.data.summary(scenarios.first);
        final latest = env.source.data.summary(scenarios.last);
        final resume = platform == TargetPlatform.windows
            ? find.byType(ContinueReadingRow)
            : find.byType(ContinueReadingCard);
        void shows(NovelSummary book) {
          expect(resume, findsOneWidget);
          expect(
            find.descendant(of: resume, matching: find.text(book.title)),
            findsOneWidget,
          );
        }

        shows(latest);
        expect(await controller.remove(latest.key), isTrue);
        await tester.pumpAndSettle();
        shows(older);
        expect(controller.progressFor(latest.key), isNull);

        expect(await controller.remove(older.key), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Your bookshelf is empty.'), findsOneWidget);
        expect(find.text('Continue reading'), findsNothing);
        expect(find.byType(ContinueReadingCard), findsNothing);
        expect(find.byType(ContinueReadingRow), findsNothing);
        expect(controller.recent, isEmpty);

        // Explicitly adding again does not restore the removed reading position.
        expect(await controller.add(older), isTrue);
        await tester.pumpAndSettle();
        expect(resume, findsNothing);
        expect(controller.contains(older.key), isTrue);
        expect(controller.progressFor(latest.key), isNull);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('continue reading can open details without stacking readers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
    final summary = env.source.data.summary(FixtureScenario.multiVolume);
    await env.library.putBookshelf(
      BookshelfEntry(snapshot: summary, addedAt: DateTime.now()),
      cancellation: CancellationSource().token,
    );
    await seed(env, fixtureChapterKey(FixtureScenario.multiVolume));
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => ReadingHome(
            repository: env.novels,
            library: env.library,
            sources: [env.source.descriptor],
            settings: env.settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    for (var cycle = 0; cycle < 2; cycle++) {
      expect(find.byType(ReaderContentView), findsOneWidget);
      if (find.text('Got it').evaluate().isNotEmpty) {
        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
      }
      if (find.byTooltip('More').evaluate().isEmpty) {
        await tester.tapAt(tester.getCenter(find.byType(ReaderContentView)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novel details'));
      await tester.pumpAndSettle();
      // Details open over the one reader.
      expect(
        find.byType(ReaderContentView, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('In bookshelf'), findsOneWidget);
      if (cycle == 0) {
        // Reading from details returns to that reader.
        await tester.ensureVisible(find.byKey(const ValueKey('detail-read')));
        await tester.tap(find.byKey(const ValueKey('detail-read')));
      } else {
        await tester.pageBack();
      }
      await tester.pumpAndSettle();
      expect(find.text('Add to bookshelf'), findsNothing);
    }
    expect(find.byType(ReaderContentView, skipOffstage: false), findsOneWidget);
    if (find.byTooltip('More').evaluate().isEmpty) {
      await tester.tapAt(tester.getCenter(find.byType(ReaderContentView)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novel details'));
    await tester.pumpAndSettle();
    // Choosing a chapter replaces both details and the reader beneath.
    tester.widget<DetailScreen>(find.byType(DetailScreen)).onChapter!(
      fixtureChapterKey(FixtureScenario.multiVolume),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen, skipOffstage: false), findsNothing);
    expect(find.byType(ReaderContentView, skipOffstage: false), findsOneWidget);
    if (find.byTooltip('More').evaluate().isEmpty) {
      await tester.tapAt(tester.getCenter(find.byType(ReaderContentView)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novel details'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('detail-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from bookshelf'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen, skipOffstage: false), findsNothing);
    expect(find.byType(ReaderContentView, skipOffstage: false), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(
      (await env.library.getProgress(
                summary.key,
                cancellation: CancellationSource().token,
              )
              as Success<ReadingProgress?>)
          .value,
      isNull,
    );
    expect(find.text('Your bookshelf is empty.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(env.close);
  });

  testWidgets(
    'detail removal confirms cache and progress loss without a history menu',
    (tester) async {
      final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
      final cache = RemovalCache();
      final summary = env.source.data.summary(FixtureScenario.multiVolume);
      await env.library.putBookshelf(
        BookshelfEntry(snapshot: summary, addedAt: DateTime.now()),
        cancellation: CancellationSource().token,
      );
      await seed(env, fixtureChapterKey(FixtureScenario.multiVolume));
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => ReadingHome(
              cache: cache,
              repository: env.novels,
              library: env.library,
              sources: [env.source.descriptor],
              settings: env.settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text(summary.title).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novel details'));
      await tester.pumpAndSettle();
      expect(find.text('In bookshelf'), findsOneWidget);
      expect(find.text('Remove from bookshelf'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('detail-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from bookshelf'));
      await tester.pumpAndSettle();
      expect(cache.cleared, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Add to bookshelf'), findsOneWidget);
      expect(cache.cleared, [summary.key]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Your bookshelf is empty.'), findsOneWidget);
      expect(find.text('Continue reading'), findsNothing);
      expect(find.byType(ContinueReadingCard), findsNothing);
      expect(find.text('Undo removal'), findsNothing);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Reading history'), findsNothing);
      await tester.runAsync(() async {
        expect(
          (await env.library.getProgress(
                    summary.key,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value,
          isNull,
        );
        expect(
          (await env.library.watchBookshelf().first
                  as Success<List<BookshelfEntry>>)
              .value
              .length,
          0,
        );
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(env.close);
    },
  );
}
