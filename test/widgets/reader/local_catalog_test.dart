import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/local_books/local_catalog.dart';
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
