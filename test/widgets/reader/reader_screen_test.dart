import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/reader_viewport.dart';
import 'package:shiori/shared/widgets/state_views.dart';

class PendingRepository implements NovelRepository {
  final requests = <Completer<Result<LoadResult<ChapterContent>>>>[];
  final tokens = <CancellationToken>[];
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    expect(mode, ReadMode.cacheFirst);
    tokens.add(cancellation);
    final request = Completer<Result<LoadResult<ChapterContent>>>();
    requests.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Success<LoadResult<ChapterContent>> loaded(ChapterContent content) => Success(
  LoadResult(
    value: content,
    origin: LoadOrigin.memory,
    fetchedAt: DateTime.utc(2026),
  ),
);

void main() {
  testWidgets(
    'hidden chrome, visible chrome and progress sheet share decimal progress',
    (tester) async {
      final content = const FixtureData().content(FixtureScenario.longChapter);
      final settings = FixtureSettingsStore();
      await settings.save(
        ReaderSettings(controlsHintSeen: true),
        cancellation: CancellationSource().token,
      );
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) =>
                ReaderContentView(content: content, settings: settings),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      viewport.onPosition!(
        ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks.first.blockKey,
          blockIndex: 0,
          blockFraction: .267899,
          chapterFraction: .267899,
        ),
        false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      final center = tester.getCenter(find.byType(ReaderContentView));
      if (find
          .byKey(const ValueKey('reader-chapter-title'))
          .evaluate()
          .isEmpty) {
        await tester.tapAt(center);
        await tester.pumpAndSettle();
      }
      expect(find.text('Chapter 26.78%'), findsOneWidget);
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(find.text('Chapter 26.78%'), findsOneWidget);
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(find.text('Chapter 26.78%'), findsOneWidget);
      await tester.tap(find.text('Chapter 26.78%'));
      await tester.pumpAndSettle();
      expect(find.text('26.78%'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, .267899);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  test(
    'wrong chapter is rejected and non-retryable failures cannot reload',
    () async {
      final repository = PendingRepository();
      final controller = ReaderController(
        repository: repository,
        chapter: fixtureChapterKey(FixtureScenario.shortChapter),
      );
      final request = controller.load();
      repository.requests.first.complete(
        loaded(const FixtureData().content(FixtureScenario.longChapter)),
      );
      await request;
      expect(controller.status, ReaderStatus.error);
      expect(controller.failure!.context, FailureContext.invalidContent);
      expect(controller.content, isNull);
      await controller.load();
      expect(repository.requests, hasLength(1));
      controller.onDelete();
      controller.dispose();
    },
  );

  testWidgets(
    'image-only fixture stays readable as a placeholder without media IO',
    (tester) async {
      final env = FixtureEnvironment(scenario: FixtureScenario.singleImage);
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('zh'),
          routes: AppRoutes(
            home: (_) => ReaderScreen(
              chapter: fixtureChapterKey(FixtureScenario.singleImage),
              repository: env.novels,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PagedReaderViewport), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(env.source.controls.calls[Operation.media] ?? 0, 0);
      expect(find.byType(ReaderViewport), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await env.close();
    },
  );

  testWidgets('progress panel surface follows the reader paper', (
    tester,
  ) async {
    final env = FixtureEnvironment(scenario: FixtureScenario.shortChapter);
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('zh'),
        routes: AppRoutes(
          home: (_) => ReaderScreen(
            chapter: fixtureChapterKey(FixtureScenario.shortChapter),
            repository: env.novels,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('本章 0.00%'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material && widget.color == const Color(0xfffffcf8),
        ),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await env.close();
  });

  test(
    'controller rejects old completions and cancels owned requests on close',
    () async {
      final repository = PendingRepository();
      final content = FixtureData().content(FixtureScenario.shortChapter);
      final controller = ReaderController(
        repository: repository,
        chapter: content.key,
      );
      final first = controller.load();
      final second = controller.load();
      expect(repository.tokens.first.isCancelled, isTrue);
      repository.requests[1].complete(loaded(content));
      await second;
      repository.requests.first.complete(
        Failure(
          AppFailure(
            kind: FailureKind.timeout,
            operation: Operation.chapter,
            retryPolicy: RetryPolicy.manual,
          ),
        ),
      );
      await first;
      expect(controller.status, ReaderStatus.ready);
      expect(controller.content, same(content));
      final third = controller.load();
      controller.onDelete();
      expect(repository.tokens.last.isCancelled, isTrue);
      repository.requests.last.complete(loaded(content));
      await third;
      expect(controller.status, ReaderStatus.loading);
      controller.dispose();
    },
  );

  testWidgets('loading, typed failure, retry, ready and route disposal', (
    tester,
  ) async {
    final repository = PendingRepository();
    final content = FixtureData().content(FixtureScenario.shortChapter);
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) =>
              ReaderScreen(chapter: content.key, repository: repository),
        ),
      ),
    );
    expect(find.byType(LoadingView), findsOneWidget);
    repository.requests.first.complete(
      Failure(
        AppFailure(
          kind: FailureKind.timeout,
          operation: Operation.chapter,
          retryPolicy: RetryPolicy.manual,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FailureView), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    repository.requests.last.complete(loaded(content));
    await tester.pumpAndSettle();
    expect(find.byType(PagedReaderViewport), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(repository.tokens.last.isCancelled, isTrue);
  });

  testWidgets(
    'Chrome toggles without rebuilding body, drag turns and modes preserve anchor',
    (tester) async {
      final content = FixtureData().content(FixtureScenario.longChapter);
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(home: (_) => ReaderContentView(content: content)),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      final first = viewport.controller.capture()!;
      await tester.tapAt(tester.getCenter(find.byType(PagedReaderViewport)));
      await tester.pumpAndSettle();
      expect(find.text('Scroll'), findsNothing);
      expect(
        tester.widget<PagedReaderViewport>(find.byType(PagedReaderViewport)),
        same(viewport),
      );
      await tester.drag(
        find.byType(PagedReaderViewport),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(
        viewport.controller.capture()!.chapterFraction,
        greaterThan(first.chapterFraction),
      );
      expect(find.text('Scroll'), findsNothing);
      await tester.tapAt(tester.getCenter(find.byType(PagedReaderViewport)));
      await tester.pumpAndSettle();
      final anchor = viewport.controller.capture()!;
      expect(viewport.controller.capture()!.blockKey, anchor.blockKey);
      expect(viewport.controller.cachedPages, lessThanOrEqualTo(7));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long title, big text, blank blocks, headings and images in both modes',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final content = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.shortChapter),
        title: List.filled(50, 'Long title 标题').join(),
        blocks: [
          HeadingBlock(text: 'Heading', level: 1),
          ParagraphBlock(text: '', leadingIndent: 2),
          ParagraphBlock(
            text: 'Centered',
            alignment: ParagraphAlignment.center,
          ),
          DividerBlock(),
          ParagraphBlock(text: 'Indented words', leadingIndent: 2),
          ImageBlock(media: fixtureMediaRef(0), alt: 'Picture'),
        ],
      );
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(2),
              ),
              child: ReaderContentView(content: content),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final paged = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      paged.controller.next();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderViewport), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
