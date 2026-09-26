import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/home/desktop_shell.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/novel_detail/detail_screen.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/search/search_screen.dart';
import 'package:shiori/shared/widgets/book_cover.dart';
import 'package:shiori/shared/widgets/desktop_content_frame.dart';

import '../desktop_shell_test.dart' show ShellHarness;
import 'search_controller_test.dart' show Repository;
import 'search_screen_test.dart' show input, submit;

final windows = TargetPlatformVariant.only(TargetPlatform.windows);

/// Only search is controlled; real fixture Detail/Catalog/Reader still run.
class WorkspaceRepository implements NovelRepository {
  WorkspaceRepository(this.inner);
  final NovelRepository inner;
  final searchRequests = Repository();
  @override
  Future<Result<SearchPage>> search(
    SourceId source,
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) => searchRequests.search(
    source,
    query,
    cursor: cursor,
    cancellation: cancellation,
  );
  @override
  Future<Result<List<DiscoverSection>>> discover(
    SourceId source, {
    required CancellationToken cancellation,
  }) => inner.discover(source, cancellation: cancellation);
  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => inner.loadDetail(key, mode: mode, cancellation: cancellation);
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => inner.loadCatalog(key, mode: mode, cancellation: cancellation);
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => inner.loadChapter(key, mode: mode, cancellation: cancellation);
  @override
  Stream<Result<LoadResult<NovelDetail>>> detailUpdates(NovelKey key) =>
      inner.detailUpdates(key);
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      inner.catalogUpdates(key);
  @override
  Stream<Result<LoadResult<ChapterContent>>> chapterUpdates(ChapterKey key) =>
      inner.chapterUpdates(key);
}

void main() {
  testWidgets(
    'bounded Shell uses its layout width instead of outer MediaQuery',
    (tester) async {
      final h = ShellHarness(tester);
      await h.pump(size: const Size(1600, 720), shellWidth: 839);
      await h.select(h.l.searchTitle);
      final workspace = h.workspace;
      await tester.enterText(input, 'draft');
      final text = tester.widget<TextField>(input).controller;
      expect(MediaQuery.sizeOf(tester.element(input)).width, 1600);
      expect(h.layout, ShellLayout.bar);
      expect(find.byType(DesktopPageToolbar), findsNothing);
      await h.pump(size: const Size(1600, 720), shellWidth: 840);
      expect(h.workspace, same(workspace));
      expect(h.layout, ShellLayout.rail);
      expect(find.byType(DesktopPageToolbar), findsOneWidget);
      expect(tester.widget<TextField>(input).controller, same(text));
      expect(text!.text, 'draft');
      expect(
        tester.getRect(input).left,
        ShioriLayout.rail + ShioriLayout.gutter(840),
      );
      expect(
        tester.getSize(input).width,
        840 - ShioriLayout.rail - 2 * ShioriLayout.gutter(840),
      );
      await h.close();
    },
    variant: windows,
  );

  testWidgets(
    'Shell width enables Search at 840 before rail takes its space',
    (tester) async {
      final h = ShellHarness(tester);
      await h.pump(size: const Size(900, 720));
      await h.select(h.l.searchTitle);
      final workspace = h.workspace;
      final text = tester.widget<TextField>(input).controller!;
      final focus = tester.widget<TextField>(input).focusNode!;
      final viewport = tester.element(find.byType(CustomScrollView));
      await tester.enterText(input, '中文 draft');
      const value = TextEditingValue(
        text: '中文 draft',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
      for (final width in [
        900.0,
        839.0,
        840.0,
        839.0,
        840.0,
        1199.0,
        1200.0,
        1199.0,
        1280.0,
        1600.0,
        1920.0,
      ]) {
        await h.resize(width);
        expect(h.workspace, same(workspace));
        expect(tester.element(find.byType(CustomScrollView)), same(viewport));
        expect(text.value, value);
        expect(focus.hasFocus, isTrue);
        expect(
          find.byType(DesktopPageToolbar),
          width >= 840 ? findsOneWidget : findsNothing,
        );
        expect(find.byType(BackButton), findsNothing);
        if (width >= 840) {
          final navWidth = width < 1200
              ? ShioriLayout.rail
              : ShioriLayout.sidebar;
          final gutter = ShioriLayout.gutter(width);
          final available = width - navWidth;
          final content = (available - 2 * gutter).clamp(
            0,
            ShioriLayout.shelfList,
          );
          expect(
            tester.getRect(input).left,
            closeTo(navWidth + (available - content) / 2, .01),
          );
          expect(
            tester.getSize(find.byType(CustomScrollView)).width,
            closeTo(available, .01),
          );
          expect(tester.getRect(find.byType(CustomScrollView)).left, navWidth);
          expect(tester.getRect(find.byType(CustomScrollView)).right, width);
        } else {
          expect(h.layout, ShellLayout.bar);
        }
      }
      await h.close();
    },
    variant: windows,
  );

  testWidgets(
    'real Search Detail Reader round trip keeps results, row focus and position',
    (tester) async {
      final h = ShellHarness(tester);
      final repository = WorkspaceRepository(h.env.novels);
      await h.pump(repository: repository);
      await h.select(h.l.searchTitle);
      await tester.enterText(input, 'query');
      await tester.pump();
      await tester.tap(submit);
      final books = <NovelSummary>[
        for (var i = 0; i < 16; i++)
          NovelSummary(
            key: NovelKey(
              sourceId: h.book.key.sourceId,
              novelId: 'synthetic-$i',
            ),
            title: 'Synthetic result $i',
          ),
        h.book,
        for (var i = 16; i < 40; i++)
          NovelSummary(
            key: NovelKey(
              sourceId: h.book.key.sourceId,
              novelId: 'synthetic-$i',
            ),
            title: 'Synthetic result $i',
          ),
      ];
      repository.searchRequests.calls.single.pending.complete(
        Success(SearchPage(sourceId: h.book.key.sourceId, items: books)),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(input);
      final text = field.controller!;
      field.focusNode!.unfocus();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(2200);
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey(h.book.key));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final rowFocus = Focus.of(
        tester.element(
          find.descendant(of: row, matching: find.byType(BookCover)),
        ),
      );
      rowFocus.requestFocus();
      await tester.pumpAndSettle();
      final position = scroll.offset;
      final value = text.value;
      final workspace = h.workspace;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(DetailScreen))),
        same(workspace),
      );
      final detail = tester.element(find.byType(DetailScreen));
      await tester.tap(find.byKey(const ValueKey('detail-read')));
      await tester.pumpAndSettle();
      expect(
        Navigator.of(tester.element(find.byType(BookReaderScreen))),
        same(h.root),
      );
      for (final width in [839.0, 840.0, 1199.0, 1200.0, 1280.0]) {
        await h.resize(width);
        expect(h.workspace, same(workspace));
        expect(
          tester.element(find.byType(DetailScreen, skipOffstage: false)),
          same(detail),
        );
        expect(text.value, value);
      }
      await h.key(LogicalKeyboardKey.escape);
      expect(find.byType(BookReaderScreen), findsNothing);
      expect(find.byType(DetailScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(rowFocus.hasFocus, isTrue);
      expect(scroll.offset, closeTo(position, 1));
      expect(
        tester
            .getRect(row)
            .overlaps(tester.getRect(find.byType(CustomScrollView))),
        isTrue,
      );
      expect(text.value, value);
      expect(repository.searchRequests.calls.length, 1);

      // Reselecting the same section removes Detail, without clearing Search.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      h.navigation.select(HomeSection.search);
      await tester.pumpAndSettle();
      expect(h.workspace.canPop(), isFalse);
      expect(scroll.offset, closeTo(position, 1));
      expect(repository.searchRequests.calls.length, 1);
      // The header is lazily disposed while offscreen; its page-owned editing
      // resource must be reused when it is visible again.
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller, same(text));
      expect(text.value, value);
      await h.close();
    },
    variant: windows,
  );

  testWidgets(
    'leaving Search cancels request; no-source root creates no controller',
    (tester) async {
      final h = ShellHarness(tester);
      final repository = WorkspaceRepository(h.env.novels);
      await h.pump(repository: repository);
      await h.select(h.l.searchTitle);
      await tester.enterText(input, 'query');
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      final call = repository.searchRequests.calls.single;
      h.navigation.select(HomeSection.shelf);
      await tester.pumpAndSettle();
      expect(call.token.isCancelled, isTrue);
      call.pending.complete(
        Success(SearchPage(sourceId: h.book.key.sourceId, items: [h.book])),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen, skipOffstage: false), findsNothing);
      await h.select(h.l.searchTitle);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(repository.searchRequests.calls.length, 1);
      await h.close();

      final empty = ShellHarness(tester);
      final noRequests = Repository();
      await empty.pump(repository: noRequests, noSources: true);
      await empty.select(empty.l.searchTitle);
      expect(find.text(empty.l.noSources), findsOneWidget);
      expect(find.byType(DesktopPageToolbar), findsOneWidget);
      expect(find.byType(SearchScreen), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await empty.resize(839);
      expect(find.byType(DesktopPageToolbar), findsNothing);
      expect(find.text(empty.l.noSources), findsOneWidget);
      expect(noRequests.calls, isEmpty);
      await empty.close();
    },
    variant: windows,
  );
}
