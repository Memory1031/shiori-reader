import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/local_books/local_catalog.dart';
import 'package:shiori/features/reader/reader_contents.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

class _Navigation implements LocalNavigationRepository {
  final result = Completer<Result<List<LocalNavigationEntry>>>();
  @override
  Future<Result<List<LocalNavigationEntry>>> loadNavigation(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => result.future;
}

void main() {
  final novel = NovelKey(sourceId: SourceId('local'), novelId: 'book');
  ChapterKey chapter(int i) => ChapterKey(novelKey: novel, chapterId: '$i');
  final entries = List.generate(
    100,
    (volume) => LocalNavigationEntry(
      title: 'Volume $volume',
      chapterKey: chapter(volume * 30),
      children: List.generate(
        30,
        (i) => LocalNavigationEntry(
          title:
              'Chapter ${volume * 30 + i} ${'Long chapter title ' * (i % 3)}',
          chapterKey: chapter(volume * 30 + i),
          blockKey: 'anchor-$i',
        ),
      ),
    ),
  );
  Widget app(Widget home) => MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: home,
  );

  testWidgets('body files anchor to nested targets by spine order', (
    tester,
  ) async {
    // Deliberately reverse TOC order and nest A. Chapter IDs carry no ordering.
    final a = LocalNavigationEntry(
      title: 'Section A',
      chapterKey: chapter(30),
      blockKey: 'a-start',
    );
    final b = LocalNavigationEntry(
      title: 'Section B',
      chapterKey: chapter(10),
      children: [a],
    );
    final order = [
      chapter(0),
      chapter(30),
      chapter(20),
      chapter(10),
      chapter(40),
    ];
    for (final (current, expected) in [
      (chapter(30), a),
      (chapter(20), a),
      (chapter(10), b),
      (chapter(40), b),
      (chapter(20), a),
      (chapter(0), null),
      (chapter(99), null),
      (null, null),
    ]) {
      LocalNavigationEntry? tapped;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: LocalNavigationView(
              entries: [b],
              readingOrder: order,
              current: current,
              onSelect: (entry) => tapped = entry,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selected = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .where((tile) => tile.selected)
          .toList();
      expect(selected, hasLength(expected == null ? 0 : 1));
      expect(
        find.byIcon(Icons.bookmark),
        expected == null ? findsNothing : findsOneWidget,
      );
      if (expected != null) {
        expect((selected.single.title! as Text).data, expected.title);
        final label = find.text(expected.title);
        expect(label.hitTestable(), findsOneWidget);
        final listTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
        expect(
          tester
              .getTopLeft(
                find.ancestor(
                  of: find.text('Section B'),
                  matching: find.byType(ListTile),
                ),
              )
              .dy,
          listTop,
        );
        await tester.tap(label);
        expect(tapped, same(expected));
      }
    }
  });

  testWidgets('short contents stay at the start without a scroll range', (
    tester,
  ) async {
    final shortEntries = List.generate(
      5,
      (i) => LocalNavigationEntry(title: 'Chapter $i', chapterKey: chapter(i)),
    );
    final wrappedEntries = [
      for (final entry in shortEntries)
        LocalNavigationEntry(
          title: '${entry.title} ${'Long title ' * 12}',
          chapterKey: entry.chapterKey,
        ),
    ];
    Future<void> show({
      required double height,
      double scale = 1,
      bool longTitles = false,
    }) async {
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                height: height,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: LocalNavigationView(
                    entries: longTitles ? wrappedEntries : shortEntries,
                    current: chapter(3),
                    onSelect: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ScrollPosition position() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    await show(height: 500);
    expect(find.text('Chapter 0').hitTestable(), findsOneWidget);
    expect(find.text('Chapter 4').hitTestable(), findsOneWidget);
    expect(position().pixels, 0);
    expect(position().maxScrollExtent - position().minScrollExtent, 0);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey(('local-toc', 3))))
          .selected,
      isTrue,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(position().pixels, 0);
    await show(height: 120);
    expect(
      position().maxScrollExtent - position().minScrollExtent,
      greaterThan(0),
    );
    expect(find.text('Chapter 3').hitTestable(), findsOneWidget);
    await show(height: 500);
    expect(position().pixels, 0);
    expect(position().maxScrollExtent - position().minScrollExtent, 0);
    // Real overflow still locates the current row, including wrapped titles
    // and accessibility text scaling. Enlarging the panel removes the range.
    await show(height: 250, scale: 2, longTitles: true);
    expect(
      position().maxScrollExtent - position().minScrollExtent,
      greaterThan(0),
    );
    expect(
      find.byKey(const ValueKey(('local-toc', 3))).hitTestable(),
      findsOneWidget,
    );
    await show(height: 580, scale: 2, longTitles: true);
    // Changing only text scale can make the same directory fit again.
    await show(height: 580, longTitles: true);
    expect(position().pixels, 0);
    expect(position().maxScrollExtent - position().minScrollExtent, 0);
    await show(height: 580);
    expect(position().pixels, 0);
    expect(position().maxScrollExtent - position().minScrollExtent, 0);
    expect(find.text('Chapter 0').hitTestable(), findsOneWidget);
    expect(find.text('Chapter 4').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'open contents updates when reading order arrives after navigation',
    (tester) async {
      final navigation = ValueNotifier<Result<List<LocalNavigationEntry>>?>(
        null,
      );
      final order = ValueNotifier<List<ChapterKey>>([]);
      addTearDown(navigation.dispose);
      addTearDown(order.dispose);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) {
                return localContentsLayer(
                  context,
                  navigation: navigation,
                  current: chapter(20),
                  readingOrder: () => order.value,
                  readingOrderChanges: order,
                  onRetry: () {},
                  onSelect: (_) {},
                ).build(context, ([then]) => then?.call());
              },
            ),
          ),
        ),
      );
      navigation.value = Success([
        LocalNavigationEntry(title: 'B', chapterKey: chapter(10)),
        LocalNavigationEntry(title: 'A', chapterKey: chapter(30)),
      ]);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark), findsNothing);
      order.value = [chapter(30), chapter(20), chapter(10)];
      await tester.pumpAndSettle();
      expect(find.text('A').hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.ancestor(
                of: find.text('A'),
                matching: find.byType(ListTile),
              ),
            )
            .selected,
        isTrue,
      );
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
    },
  );

  testWidgets('offscreen selection shows context and respects the list end', (
    tester,
  ) async {
    final rows = List.generate(
      50,
      (i) => LocalNavigationEntry(title: 'Entry $i', chapterKey: chapter(i)),
    );
    Future<void> show(int current, {int count = 50}) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                height: 400,
                child: LocalNavigationView(
                  entries: rows.take(count).toList(),
                  current: chapter(current),
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Rect row(int index) =>
        tester.getRect(find.byKey(ValueKey(('local-toc', index))));
    Rect viewport() => tester.getRect(find.byType(CustomScrollView));
    ScrollPosition position() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;

    // A visible selection does not move, even in an overflowing directory.
    await show(2);
    expect(position().pixels, 0);
    expect(find.text('Entry 0').hitTestable(), findsOneWidget);

    // Exercise both a cached row just below the screen and a distant row that
    // requires an indexed anchor. Their final placement must be identical.
    for (final current in [8, 30]) {
      await show(current);
      expect(
        row(current).top - viewport().top,
        closeTo((viewport().height - row(current).height) / 3, 1),
      );
      expect(find.text('Entry ${current - 1}').hitTestable(), findsOneWidget);
      expect(find.text('Entry ${current + 1}').hitTestable(), findsOneWidget);
      expect(find.byType(ListTile).evaluate().length, lessThan(30));
    }

    // The natural list and the distant anchor both clamp at the actual end.
    for (final (current, count) in [(8, 10), (48, 50), (49, 50)]) {
      await show(current, count: count);
      expect(find.text('Entry $current').hitTestable(), findsOneWidget);
      expect(row(count - 1).bottom, closeTo(viewport().bottom, 1));
      expect(position().pixels, closeTo(position().maxScrollExtent, 1));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(row(count - 1).bottom, closeTo(viewport().bottom, 1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'async nested catalog opens at deep current chapter and scrolls both ways',
    (tester) async {
      tester.view.physicalSize = const Size(390, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Navigation();
      Widget screen() => app(
        LocalCatalogScreen(
          novel: novel,
          repository: repo,
          current: chapter(2714),
        ),
      );
      await tester.pumpWidget(screen());
      expect(find.byType(LocalNavigationView), findsNothing);
      repo.result.complete(Success(entries));
      await tester.pumpAndSettle();
      final current = find.textContaining('Chapter 2714 ');
      expect(current.hitTestable(), findsOneWidget);
      final tile = find.ancestor(of: current, matching: find.byType(ListTile));
      expect(tester.widget<ListTile>(tile).selected, isTrue);
      expect(find.byType(ListTile).evaluate().length, lessThan(40));
      final list = find.byType(CustomScrollView);
      await tester.drag(list, const Offset(0, 350));
      await tester.pumpAndSettle();
      final previous = find.textContaining('Chapter 2713 ');
      expect(previous.hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(previous).dy,
        lessThan(tester.getTopLeft(current).dy),
      );
      await tester.drag(list, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Chapter 2715 ').hitTestable(),
        findsOneWidget,
      );
      final offset = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        offset,
      );
      // A fresh directory visit anchors again, independently of manual scrolling.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(current.hitTestable(), findsOneWidget);
    },
  );

  testWidgets('first, last and missing chapters stay usable with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final index in [0, 2999, -1]) {
      LocalNavigationEntry? selected;
      await tester.pumpWidget(
        app(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: LocalNavigationView(
                entries: entries,
                current: chapter(index),
                onSelect: (entry) => selected = entry,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = index == 2999
          ? find.textContaining('Chapter 2999 ')
          : find.text('Volume 0');
      expect(label.hitTestable(), findsOneWidget);
      await tester.tap(label);
      expect(selected!.chapterKey, chapter(index == 2999 ? 2999 : 0));
      if (index == 2999) expect(selected!.blockKey, 'anchor-29');
      expect(tester.takeException(), isNull);
    }
  });
}
