import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/search/local_search_session.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_search_controller.dart';
import 'package:shiori/features/reader/reader_search_highlight.dart';
import 'package:shiori/features/reader/reader_search_panel.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'link_return_test.dart' as f;
import 'local_reading_test.dart' show MemoryBooks;

/// Real bounded production scanner, with only stored snapshot validation stubbed.
class ReaderSearchRepository extends f.ReturnRepository {
  ReaderSearchRepository(this.store) : super(store);
  final MemoryBooks store;
  final sessions = <LocalSearchSessionImpl>[];
  bool valid = true;
  ChapterKey? changingTarget;
  int targetLoads = 0, changeAfter = 3;
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    final result = await super.loadChapter(
      key,
      mode: mode,
      cancellation: cancellation,
    );
    if (key == changingTarget &&
        ++targetLoads >= changeAfter &&
        result is Success<LoadResult<ChapterContent>>) {
      return Success(
        LoadResult(
          value: ChapterContent(
            key: key,
            title: result.value.value.title,
            blocks: [
              ...result.value.value.blocks,
              ParagraphBlock(text: 'Changed after validation'),
            ],
          ),
          origin: result.value.origin,
          fetchedAt: result.value.fetchedAt,
        ),
      );
    }
    return result;
  }

  int released = 0;
  @override
  Future<Result<LocalSearchSession>> openLocalSearch(
    NovelKey book, {
    required CancellationToken cancellation,
  }) async {
    final session = LocalSearchSessionImpl(
      content: store.record.content,
      snapshot: LocalSearchSnapshotId('reader-snapshot'),
      sessionId: 'reader-${sessions.length}',
      check: (_) async => Success(valid),
      release: () {
        released++;
      },
    );
    sessions.add(session);
    return Success(session);
  }
}

ReaderSearchController search(f.ReturnReader reader, WidgetTester tester) =>
    reader.view(tester).search!;
Future<void> submit(
  WidgetTester tester,
  ReaderSearchController state,
  String text,
) async {
  if (find.byKey(const ValueKey('reader-search-input')).evaluate().isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('reader-search-input')),
      text,
    );
  }
  await tester.runAsync(() => state.submit(text));
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  expect(find.byType(ReaderSearchPanel), findsOneWidget);
}

Future<void> select(
  WidgetTester tester,
  ReaderSearchController state,
  int index,
) async {
  final panel = tester.widget<ReaderSearchPanel>(
    find.byType(ReaderSearchPanel),
  );
  unawaited(
    state.select(
      index,
      accepts: panel.accepts,
      closePanel: panel.closeForNavigation,
    ),
  );
  await tester.pumpAndSettle();
  // Repository/worker checks use the real event loop.
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Future<void> fonts(WidgetTester tester) async {
  if (Platform.environment['SHIORI_RETURN_SCREENSHOTS'] == null) return;
  await tester.runAsync(() async {
    final material = await File(
      '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(material)))).load();
    final cjk = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (await cjk.exists()) {
      final bytes = await cjk.readAsBytes();
      for (final family in ['Microsoft YaHei UI', 'Roboto']) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
  });
}

void main() {
  testWidgets(
    'toolbar, explicit submit, same/main navigation and independent original link history',
    (tester) async {
      await fonts(tester);
      final reader = await f.mount(
        tester,
        size: const Size(1040, 780),
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester);
      final origin = reader.position(tester);
      await reader.link(
        tester,
        'B',
      ); // Existing link history must survive search.
      final before = reader.position(tester),
          chapter = reader.view(tester).content.key;
      await f.toggle(tester);
      expect(find.byKey(const ValueKey('reader-search-open')), findsOneWidget);
      final top = tester.widget<ReaderTopBar>(find.byType(ReaderTopBar));
      expect(top.showSearch, isTrue);
      await open(tester);
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('reader-search-input')),
        'later',
      );
      expect(state.loadedCount, 0);
      await submit(tester, state, 'later');
      expect(reader.position(tester), before);
      expect(reader.view(tester).content.key, chapter);
      final same = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)!.chapter == chapter);
      await select(tester, state, same);
      expect(reader.view(tester).content.key, chapter);
      expect(state.highlight.value, state.hitAt(same));
      await open(tester);
      final hit = state.hitAt(0)!;
      await f.snapshot(tester, reader, 'desktop-search-results');
      await select(tester, state, 0);
      expect(state.selectedIndex, 0);
      expect(state.highlight.value, hit);
      expect(reader.view(tester).content.key, hit.chapter);
      final highlighted = reader.position(tester);
      final geometry = tester
          .renderObjectList<ReaderSearchTextRender>(
            find.byType(ReaderPaintedSearchText),
          )
          .expand((r) => r.selectedBoxes)
          .toList();
      expect(geometry, isNotEmpty);
      await f.snapshot(tester, reader, 'desktop-selected-highlight');
      state.clearHighlight();
      await tester.pump();
      expect(reader.position(tester), highlighted);
      expect(state.canReturn.value, isTrue);
      reader.view(tester).actions.previousLocation!();
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, chapter);
      expect(reader.position(tester), before);
      expect(state.canReturn.value, isFalse);
      await reader.back(tester);
      expect(reader.view(tester).content.key, reader.key('a'));
      expect(reader.position(tester), origin);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'multiple hits keep first origin, auxiliary route borrows session, footnote uses source marker',
    (tester) async {
      final reader = await f.mount(
        tester,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester),
          repository = reader.repository as ReaderSearchRepository;
      final origin = reader.position(tester);
      await open(tester);
      await submit(tester, state, 'later');
      final auxiliary = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)?.chapter == reader.key('notes'));
      await select(tester, state, 0);
      await open(tester);
      await select(tester, state, auxiliary);
      expect(reader.view(tester).content.key, reader.key('notes'));
      expect(identical(reader.view(tester).search, state), isTrue);
      expect(repository.sessions, hasLength(1));
      reader.view(tester).actions.previousLocation!();
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, reader.key('a'));
      expect(reader.position(tester), origin);
      await open(tester);
      await submit(tester, state, 'annotation');
      expect(state.hitAt(0), isA<LocalSearchFootnoteHit>());
      await select(tester, state, 0);
      expect(
        find.textContaining('Fixture annotation.', findRichText: true),
        findsOneWidget,
      );
      expect(state.highlight.value, isNull);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'late validation, failure and maintenance preserve source and retire highlights',
    (tester) async {
      final reader = await f.mount(
        tester,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester),
          repository = reader.repository as ReaderSearchRepository;
      final origin = reader.position(tester);
      await open(tester);
      await submit(tester, state, 'later');
      repository.valid = false;
      await select(tester, state, 0);
      expect(reader.position(tester), origin);
      expect(state.canReturn.value, isFalse);
      expect(state.error, ReaderSearchError.expired);
      repository.invalidationsController.add(reader.key('a').novelKey);
      await tester.pumpAndSettle();
      expect(state.highlight.value, isNull);
      expect(state.loadedCount, 0);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'failed target and invalidation during panel close cannot commit a search origin',
    (tester) async {
      final reader = await f.mount(
        tester,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester),
          repository = reader.repository as ReaderSearchRepository;
      final origin = reader.position(tester),
          chapter = reader.view(tester).content.key;
      await open(tester);
      await submit(tester, state, 'later');
      repository.blocked = state.hitAt(0)!.chapter;
      repository.fail = true;
      await select(tester, state, 0);
      expect(reader.view(tester).content.key, chapter);
      expect(reader.position(tester), origin);
      expect(state.canReturn.value, isFalse);
      expect(state.error, ReaderSearchError.failed);
      repository.blocked = null;
      repository.fail = false;
      await open(tester);
      final panel = tester.widget<ReaderSearchPanel>(
        find.byType(ReaderSearchPanel),
      );
      unawaited(
        state.select(
          0,
          accepts: panel.accepts,
          closePanel: panel.closeForNavigation,
        ),
      );
      await tester
          .pump(); // validate has returned; the close transition has not completed.
      repository.invalidationsController.add(chapter.novelKey);
      await tester.pumpAndSettle();
      expect(state.canReturn.value, isFalse);
      expect(state.selectedIndex, isNull);
      expect(state.highlight.value, isNull);
      expect(state.navigating, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'auxiliary target revision changes after validation settles failure and returns source',
    (tester) async {
      final reader = await f.mount(
        tester,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester),
          repository = reader.repository as ReaderSearchRepository;
      final origin = reader.position(tester),
          chapter = reader.view(tester).content.key;
      await open(tester);
      await submit(tester, state, 'later');
      final auxiliary = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)!.chapter == reader.key('notes'));
      repository.changingTarget = reader.key('notes');
      await select(tester, state, auxiliary);
      expect(state.navigating, isFalse);
      expect(state.canReturn.value, isFalse);
      expect(state.selectedIndex, isNull);
      expect(state.highlight.value, isNull);
      expect(reader.view(tester).content.key, chapter);
      expect(reader.position(tester), origin);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'search started inside auxiliary content restores its exact semantic origin',
    (tester) async {
      final reader = await f.mount(
        tester,
        repositoryFactory: ReaderSearchRepository.new,
      );
      await reader.link(tester, 'Auxiliary');
      final linkOrigin = reader.position(tester);
      await reader.link(tester, 'Same file');
      unawaited(reader.view(tester).viewportController!.next());
      await tester.pumpAndSettle();
      final origin = reader.position(tester),
          chapter = reader.view(tester).content.key;
      final state = search(reader, tester);
      await open(tester);
      await submit(tester, state, 'later');
      await select(tester, state, 0);
      expect(reader.view(tester).content.key, isNot(chapter));
      reader.view(tester).actions.previousLocation!();
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, chapter);
      expect(reader.position(tester), origin);
      expect(state.canReturn.value, isFalse);
      expect(state.highlight.value, isNull);
      await reader.back(tester);
      expect(reader.view(tester).content.key, chapter);
      expect(reader.position(tester), linkOrigin);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'failed main target restores the retired auxiliary source and its links',
    (tester) async {
      final reader = await f.mount(
        tester,
        repositoryFactory: ReaderSearchRepository.new,
      );
      await reader.link(tester, 'Auxiliary');
      await reader.link(tester, 'Same file');
      final source = reader.view(tester).content.key,
          position = reader.position(tester);
      final state = search(reader, tester),
          repository = reader.repository as ReaderSearchRepository;
      await open(tester);
      await submit(tester, state, 'later');
      repository.changingTarget = state.hitAt(0)!.chapter;
      repository.changeAfter = 2;
      await select(tester, state, 0);
      expect(state.navigating, isFalse);
      expect(state.selectedIndex, isNull);
      expect(state.canReturn.value, isFalse);
      expect(reader.view(tester).content.key, source);
      expect(reader.position(tester), position);
      expect(reader.view(tester).actions.previousLocation, isNotNull);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'narrow desktop keeps focus and search geometry while editing an IME draft',
    (tester) async {
      await fonts(tester);
      final reader = await f.mount(
        tester,
        size: const Size(460, 780),
        scale: 1.2,
        repositoryFactory: ReaderSearchRepository.new,
      );
      final origin = reader.position(tester), state = search(reader, tester);
      await open(tester);
      await submit(tester, state, 'later');
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('reader-search-input')),
      );
      input.controller!.value = const TextEditingValue(
        text: 'later中文',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 5, end: 7),
      );
      input.onChanged!(input.controller!.text);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSearchPanel), findsOneWidget);
      expect(find.textContaining('Showing results for'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(reader.position(tester), origin);
      await f.snapshot(tester, reader, 'narrow-desktop-search');
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'search from completion keeps completion and position until a confirmed result jump',
    (tester) async {
      final reader = await f.mount(
        tester,
        initial: 'd',
        repositoryFactory: ReaderSearchRepository.new,
      );
      final view = reader.view(tester),
          content = view.content,
          index = view.content.blocks.length - 1;
      final position = ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks[index].blockKey,
        blockIndex: index,
        blockFraction: 1,
        chapterFraction: 1,
      );
      view.viewportController!.restore(position);
      await tester.pumpAndSettle();
      view.actions.bookEnd!();
      await tester.pumpAndSettle();
      expect(reader.view(tester).completion, isNotNull);
      final saved = reader.position(tester), state = search(reader, tester);
      await open(tester);
      await submit(tester, state, 'later');
      expect(reader.view(tester).completion, isNotNull);
      expect(reader.position(tester), saved);
      await select(tester, state, 0);
      expect(state.selectedIndex, 0);
      expect(reader.view(tester).completion, isNull);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'touch sheet keyboard preserves underlying pagination and dismisses without navigation',
    (tester) async {
      await fonts(tester);
      final reader = await f.mount(
        tester,
        size: const Size(400, 800),
        repositoryFactory: ReaderSearchRepository.new,
      );
      final state = search(reader, tester), origin = reader.position(tester);
      await f.toggle(tester);
      await tester.tap(find.byKey(const ValueKey('reader-search-open')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSearchPanel), findsOneWidget);
      final size = tester.getSize(
        find.byKey(const ValueKey('reader-search-results')),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await submit(tester, state, 'later');
      await f.snapshot(tester, reader, 'mobile-keyboard-search');
      expect(reader.position(tester), origin);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('reader-search-results')))
            .height,
        lessThan(size.height),
      );
      final panel = tester.widget<ReaderSearchPanel>(
        find.byType(ReaderSearchPanel),
      );
      panel.onClose();
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(reader.position(tester), origin);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
