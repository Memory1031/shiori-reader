import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_completion_page.dart';
import 'package:shiori/features/reader/reader_screen.dart';

import 'completion_test.dart' show CompletionRepository;
import 'settings_test.dart' show Store;

/// Online book whose chapters carry recognisable headings, and whose
/// catalog responses can be scripted per call.
class _HeadingRepository extends CompletionRepository {
  _HeadingRepository({
    Iterable<Result<LoadResult<Catalog>>> scripted = const [],
  }) : catalogResults = [...scripted];

  /// Consumed front first; once empty, loads succeed.
  final List<Result<LoadResult<Catalog>>> catalogResults;
  final catalogModes = <ReadMode>[];
  final chapterModes = <ReadMode>[];

  static const headingIndex = 30;

  @override
  ChapterContent content(ChapterKey key) => ChapterContent(
    key: key,
    title: 'Chapter ${key.chapterId}',
    blocks: [
      HeadingBlock(text: '第一话 开端', level: 2),
      for (var i = 1; i < headingIndex; i++)
        ParagraphBlock(text: 'Opening paragraph $i with words to fill it.'),
      HeadingBlock(text: '第二话 目标', level: 2),
      for (var i = 0; i < 30; i++)
        ParagraphBlock(text: 'Later paragraph $i with words to fill it.'),
    ],
  );

  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    chapterModes.add(mode);
    return super.loadChapter(key, mode: mode, cancellation: cancellation);
  }

  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    catalogModes.add(mode);
    if (catalogResults.isNotEmpty) return catalogResults.removeAt(0);
    return super.loadCatalog(key, mode: mode, cancellation: cancellation);
  }
}

AppFailure _manual(FailureKind kind) => AppFailure(
  kind: kind,
  operation: Operation.catalog,
  retryPolicy: RetryPolicy.manual,
);

Future<void> _pumpReader(
  WidgetTester tester,
  _HeadingRepository repo, {
  LibraryRepository? library,
  bool offline = false,
}) async {
  await tester.pumpWidget(
    ShioriApp(
      locale: const Locale('en'),
      routes: AppRoutes(
        home: (_) => BookReaderScreen(
          chapter: repo.order.last,
          repository: repo,
          library: library,
          offline: offline,
          settings: Store()..value = ReaderSettings(controlsHintSeen: true),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openVolumes(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.f2);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('In-volume contents'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Volumes'));
  await tester.pumpAndSettle();
}

ReaderContentView _view(WidgetTester tester) =>
    tester.widget<ReaderContentView>(find.byType(ReaderContentView));

void main() {
  testWidgets('offline catalog retry stays cache-only', (tester) async {
    final repo = _HeadingRepository(
      scripted: [Failure(_manual(FailureKind.database))],
    );
    await _pumpReader(tester, repo, offline: true);
    await _openVolumes(tester);
    // Offline readers expose no refresh control, only retry.
    expect(find.byIcon(Icons.refresh), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 1'), findsWidgets);
    expect(repo.catalogModes, hasLength(2));
    expect(repo.catalogModes, everyElement(ReadMode.cacheOnly));
    expect(repo.chapterModes, everyElement(ReadMode.cacheOnly));
    await tester.pumpWidget(const SizedBox());
    await repo.updates.close();
  });

  testWidgets('a failed refresh keeps the catalog and shows why', (
    tester,
  ) async {
    final repo = _HeadingRepository();
    await _pumpReader(tester, repo);
    await _openVolumes(tester);
    expect(find.text('Chapter 1'), findsWidgets);
    expect(find.byKey(const ValueKey('catalog-refresh-failure')), findsNothing);

    repo.catalogResults.add(Failure(_manual(FailureKind.network)));
    await tester.tap(find.byTooltip('Refresh details'));
    await tester.pumpAndSettle();
    expect(repo.catalogModes.last, ReadMode.refresh);
    // The loaded catalog stays usable with the failure shown above it.
    expect(find.byKey(const ValueKey('catalog-refresh-failure')), findsOne);
    expect(find.text('Chapter 1'), findsWidgets);

    // Retrying from the banner refreshes again and clears it on success.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('catalog-refresh-failure')),
        matching: find.text('Retry'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.catalogModes.last, ReadMode.refresh);
    expect(find.byKey(const ValueKey('catalog-refresh-failure')), findsNothing);
    expect(find.text('Chapter 1'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await repo.updates.close();
  });

  testWidgets(
    'an in-chapter heading chosen from the completion page leaves it and '
    'persists the new position',
    (tester) async {
      final repo = _HeadingRepository();
      final library = FixtureLibraryRepository();
      await _pumpReader(tester, repo, library: library);
      final pages = _view(tester).viewportController!;
      // Read to the end of the final chapter, then turn once more.
      // A turn's future completes only once its frames are pumped.
      for (var i = 0; i < 80; i++) {
        if (find.byType(ReaderCompletionPage).evaluate().isNotEmpty) break;
        final turn = pages.next();
        await tester.pumpAndSettle();
        await turn;
      }
      expect(find.byType(ReaderCompletionPage), findsOneWidget);

      await tester.tap(find.text('View contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('In-volume contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第二话 目标'));
      await tester.pumpAndSettle();

      expect(find.byType(ReaderCompletionPage), findsNothing);
      final landed = pages.capture()!;
      expect(
        landed.blockIndex,
        lessThanOrEqualTo(_HeadingRepository.headingIndex),
      );
      expect(landed.blockIndex, greaterThan(0));

      await tester.pump(const Duration(seconds: 1));
      await _view(tester).session!.flushProgress();
      final saved =
          (await library.getProgress(
                    repo.key,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value!;
      expect(saved.position.blockIndex, landed.blockIndex);
      expect(saved.bookProgress?.terminal, BookTerminalState.reading);

      // Reopening resumes at the heading, not on the completion page.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await _pumpReader(tester, repo, library: library);
      expect(find.byType(ReaderCompletionPage), findsNothing);
      expect(_view(tester).initialPosition!.blockIndex, landed.blockIndex);
      await tester.pumpWidget(const SizedBox());
      await repo.updates.close();
      await library.close();
    },
  );
}
