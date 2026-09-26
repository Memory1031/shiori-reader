import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/search/search_screen.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/widgets/book_cover.dart';
import 'package:shiori/shared/widgets/book_list_tile.dart';
import 'package:shiori/shared/widgets/desktop_content_frame.dart';

import 'search_controller_test.dart' show Repository, sourceId, page;
import 'search_screen_test.dart' show input, submit, more;

final windows = TargetPlatformVariant.only(TargetPlatform.windows);

// Flutter 3.38's legacy Windows test key map omits numpad Enter. Dispatch the
// Android event encoding supplies that logical key to the same Windows widget
// tree; this is a framework key test, not native Windows keyboard/IME evidence.
Future<void> numpadEnter(WidgetTester tester) => tester.sendKeyEvent(
  LogicalKeyboardKey.numpadEnter,
  physicalKey: PhysicalKeyboardKey.numpadEnter,
  platform: 'android',
);

class SearchHarness {
  SearchHarness(this.tester);
  final WidgetTester tester;
  final repository = Repository();
  final navigator = GlobalKey<NavigatorState>();
  int opened = 0;

  Future<void> mount({
    double width = 1280,
    double height = 720,
    double scale = 1,
    String locale = 'en',
    bool dark = false,
    Widget? home,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: shioriTheme(dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home ?? screen(),
      ),
    );
    await tester.pump();
  }

  SearchScreen screen() => SearchScreen(
    repository: repository,
    sourceId: sourceId,
    sourceName: 'Synthetic library',
    routes: AppRoutes(
      novel: (_, key) {
        opened++;
        return const Scaffold(body: Text('Detail activation'));
      },
    ),
  );

  TextField get field => tester.widget<TextField>(input);
  CustomScrollView get viewport =>
      tester.widget<CustomScrollView>(find.byType(CustomScrollView));

  Future<void> resize(double width) async {
    tester.view.physicalSize = Size(width, tester.view.physicalSize.height);
    await tester.pumpAndSettle();
  }

  Future<void> search(SearchPage result) async {
    await tester.enterText(input, 'query');
    await tester.pump();
    await tester.tap(submit);
    repository.calls.last.pending.complete(Success(result));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'Search scrollbar stays on the Workspace edge and outer margin scrolls',
    (tester) async {
      addTearDown(tester.view.reset);
      final h = SearchHarness(tester);
      await h.mount(width: 1920);
      await h.search(page(List.generate(60, (i) => 'Book $i')));
      h.field.focusNode!.unfocus();
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(CustomScrollView));
      expect(rect.left, 0);
      expect(rect.right, 1920);
      final position = h.viewport.controller!.position;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(1900, rect.center.dy),
          scrollDelta: const Offset(0, 500),
        ),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, 500);
      position.jumpTo(0);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset(rect.right - 4, rect.top + 15));
      await mouse.moveTo(Offset(rect.right - 4, rect.top + 16));
      await tester.pumpAndSettle();
      await mouse.down(Offset(rect.right - 4, rect.top + 16));
      await mouse.moveBy(const Offset(0, 150));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(h.repository.calls.length, 1);
      await mouse.removePointer();
    },
    variant: windows,
  );

  for (final width in [900.0, 1280.0, 1600.0, 1920.0]) {
    testWidgets(
      'root layout $width centers input and insets lazy row content',
      (tester) async {
        addTearDown(tester.view.reset);
        final h = SearchHarness(tester);
        await h.mount(width: width);
        expect(find.byType(DesktopPageToolbar), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);
        expect(h.repository.calls, isEmpty);
        final results = page(List.generate(40, (i) => 'Book $i'));
        await h.search(results);
        final title = find.descendant(
          of: find.byType(DesktopPageToolbar),
          matching: find.byType(Text),
        );
        final gutter = ShioriLayout.gutter(width);
        final frameWidth = (width - 2 * gutter).clamp(
          0,
          ShioriLayout.shelfList,
        );
        final inset = (width - frameWidth) / 2;
        expect(tester.getRect(title).left, closeTo(gutter, .01));
        expect(tester.getRect(input).center.dx, closeTo(width / 2, .01));
        expect(
          tester.getRect(find.byType(BookCover).first).left,
          closeTo(inset + BookListItem.inset, .01),
        );
        final result = find.byKey(ValueKey(results.items.first.key));
        final surface = tester.getRect(
          find.descendant(of: result, matching: find.byType(InkWell)),
        );
        final rowContent = tester.getRect(
          find.descendant(of: result, matching: find.byType(Row)),
        );
        expect(surface.left, closeTo(inset, .01));
        expect(surface.width, closeTo(frameWidth, .01));
        expect(tester.getRect(input).left, surface.left);
        expect(tester.getRect(input).right, surface.right);
        expect(rowContent.left - surface.left, BookListItem.inset);
        expect(surface.right - rowContent.right, BookListItem.inset);
        expect(tester.getSize(input).width, closeTo(frameWidth, .01));
        expect(
          tester.getSize(find.byType(CustomScrollView)).width,
          closeTo(width, .01),
        );
        expect(
          find.byType(Scrollable),
          findsNWidgets(2),
        ); // Input and content only.
        expect(find.text('Book 39'), findsNothing);
        final toolbar = tester.getRect(find.byType(DesktopPageToolbar));
        final viewport = tester.getRect(find.byType(CustomScrollView));
        expect(viewport.left, closeTo(width - viewport.right, .01));
        expect(viewport.left, 0);
        expect(viewport.right, width);
        expect(toolbar.left, gutter);
        expect(toolbar.width, width - 2 * gutter);
        final scrollbar = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollbar),
        );
        expect(scrollbar, findsOneWidget);
        expect(tester.getRect(scrollbar), viewport);
        h.field.focusNode!.unfocus();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(DesktopPageToolbar)), toolbar);
        expect(h.repository.calls.length, 1);
      },
      variant: windows,
    );
  }

  for (final locale in ['en', 'zh']) {
    testWidgets('$locale short large-text desktop keeps actions usable', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      final h = SearchHarness(tester);
      await h.mount(
        width: 900,
        height: 360,
        scale: 2,
        locale: locale,
        dark: locale == 'zh',
      );
      final result = SearchPage(
        sourceId: sourceId,
        items: [
          NovelSummary(
            key: NovelKey(sourceId: sourceId, novelId: 'long'),
            title: List.filled(20, '很长的书名 Long title ').join(),
            authors: [List.filled(10, 'Author 作者 ').join()],
          ),
        ],
      );
      await tester.enterText(input, 'long');
      await tester.pump();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      expect(h.repository.calls.length, 1);
      h.repository.calls.single.pending.complete(Success(result));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ValueKey(result.items.single.key)));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(BookCover)).width, 68);
      await tester.tap(find.byType(BookCover));
      await tester.pumpAndSettle();
      expect(h.opened, 1);
      expect(tester.takeException(), isNull);
    }, variant: windows);
  }

  testWidgets(
    'full editing value, focus, viewport and controller survive breakpoints and theme',
    (tester) async {
      addTearDown(tester.view.reset);
      final h = SearchHarness(tester);
      await h.mount(width: 839);
      await tester.enterText(input, '中文 draft');
      const value = TextEditingValue(
        text: '中文 draft',
        selection: TextSelection(baseOffset: 1, extentOffset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
      expect(h.field.controller!.value, value);
      final text = h.field.controller;
      final focus = h.field.focusNode;
      final editable = tester.state(find.byType(EditableText));
      final viewport = tester.element(find.byType(CustomScrollView));
      final scroll = h.viewport.controller;
      // The public callback keeps the same controller receiver throughout.
      final edit = h.field.onChanged;
      for (final width in [
        840.0,
        839.0,
        840.0,
        1199.0,
        1200.0,
        1199.0,
        1920.0,
      ]) {
        await h.resize(width);
        expect(h.field.controller, same(text));
        expect(h.field.controller!.value, value);
        expect(h.field.focusNode, same(focus));
        expect(focus!.hasFocus, isTrue);
        expect(h.field.onChanged, edit);
        expect(tester.state(find.byType(EditableText)), same(editable));
        expect(tester.element(find.byType(CustomScrollView)), same(viewport));
        expect(h.viewport.controller, same(scroll));
      }
      await h.mount(width: 1920, dark: true);
      await tester.pumpAndSettle();
      expect(h.field.controller!.value, value);
      expect(h.field.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await numpadEnter(tester);
      expect(h.repository.calls, isEmpty);
    },
    variant: windows,
  );

  testWidgets(
    'mid-list result and scroll identity survive repeated presentation changes',
    (tester) async {
      addTearDown(tester.view.reset);
      final h = SearchHarness(tester);
      await h.mount(width: 900);
      final result = page(
        List.generate(80, (i) => 'Book $i with a moderately long title'),
      );
      await h.search(result);
      h.field.focusNode!.unfocus();
      final scroll = h.viewport.controller!;
      scroll.jumpTo(2400);
      await tester.pumpAndSettle();
      final viewportRect = tester.getRect(find.byType(CustomScrollView));
      final visible = result.items.firstWhere((book) {
        final row = find.byKey(ValueKey(book.key));
        return row.evaluate().isNotEmpty &&
            tester.getRect(row).top >= viewportRect.top &&
            tester.getRect(row).bottom <= viewportRect.bottom;
      });
      final row = find.byKey(ValueKey(visible.key));
      for (final width in [839.0, 840.0, 1199.0, 1200.0, 1920.0, 900.0]) {
        await h.resize(width);
        expect(h.viewport.controller, same(scroll));
        expect(
          tester
              .getRect(row)
              .overlaps(tester.getRect(find.byType(CustomScrollView))),
          isTrue,
          reason: '$width keeps ${visible.title} visible',
        );
        expect(h.repository.calls.length, 1);
      }
      expect(scroll.offset, closeTo(2400, 1));
    },
    variant: windows,
  );

  for (final activation in ['enter', 'numpad', 'ime', 'button']) {
    testWidgets(
      '$activation submits once, preserves desktop focus and completion does not steal it',
      (tester) async {
        addTearDown(tester.view.reset);
        final h = SearchHarness(tester);
        await h.mount();
        await tester.enterText(input, 'query');
        await tester.pump();
        switch (activation) {
          case 'enter':
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          case 'numpad':
            await numpadEnter(tester);
          case 'ime':
            await tester.testTextInput.receiveAction(TextInputAction.search);
          case 'button':
            await tester.tap(submit);
        }
        await tester.pump();
        expect(h.repository.calls.length, 1);
        expect(h.field.focusNode!.hasFocus, isTrue);
        h.field.focusNode!.unfocus();
        await tester.pump();
        h.repository.calls.single.pending.complete(Success(page(['one'])));
        await tester.pumpAndSettle();
        expect(h.field.focusNode!.hasFocus, isFalse);
        expect(h.repository.calls.length, 1);
      },
      variant: windows,
    );
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform wide keeps mobile presentation and submit unfocus',
      (tester) async {
        addTearDown(tester.view.reset);
        final h = SearchHarness(tester);
        await h.mount(width: 1600);
        expect(find.byType(DesktopContentFrame), findsNothing);
        expect(find.byType(AppBar), findsOneWidget);
        await tester.enterText(input, 'query');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        expect(h.field.focusNode!.hasFocus, isFalse);
        expect(h.repository.calls.length, 1);
        h.repository.calls.single.pending.complete(Success(page([])));
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'Tab traversal, Enter, Space and semantics activate each row once',
    (tester) async {
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      final h = SearchHarness(tester);
      await h.mount();
      final result = page(['one']);
      await h.search(result);
      final row = find.byKey(ValueKey(result.items.single.key));
      h.field.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(
          tester.element(
            find.descendant(of: submit, matching: find.byType(Text)),
          ),
        ).hasFocus,
        isTrue,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(h.field.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final rowFocus = Focus.of(
        tester.element(
          find.descendant(of: row, matching: find.byType(BookCover)),
        ),
      );
      expect(rowFocus.hasFocus, isTrue);
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        final before = h.opened;
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(h.opened, before + 1);
        h.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(rowFocus.hasFocus, isTrue);
      }
      final node = tester.getSemantics(row);
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pumpAndSettle();
      expect(h.opened, 3);
      expect(h.repository.calls.length, 1);
      semantics.dispose();
    },
    variant: windows,
  );

  testWidgets(
    'desktop states retain submitted query and cancel pending paging on edit',
    (tester) async {
      addTearDown(tester.view.reset);
      final h = SearchHarness(tester);
      await h.mount();
      expect(find.text('Enter a keyword, then choose Search.'), findsOneWidget);
      await tester.enterText(input, 'query');
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      h.repository.calls.last.pending.complete(
        Failure(
          AppFailure(
            kind: FailureKind.network,
            operation: Operation.search,
            retryPolicy: RetryPolicy.manual,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      h.repository.calls.last.pending.complete(Success(page([])));
      await tester.pumpAndSettle();
      expect(
        find.text('No novels found. Try another keyword.'),
        findsOneWidget,
      );
      await tester.tap(submit);
      h.repository.calls.last.pending.complete(
        Success(page(['one'], next: 'next')),
      );
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pump();
      expect(find.text('one'), findsOneWidget);
      h.repository.calls.last.pending.complete(
        Failure(
          AppFailure(
            kind: FailureKind.network,
            operation: Operation.search,
            retryPolicy: RetryPolicy.manual,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      final pending = h.repository.calls.last;
      expect(
        pending.cursor,
        h.repository.calls[h.repository.calls.length - 2].cursor,
      );
      await tester.enterText(input, 'edited');
      await tester.pump();
      expect(pending.token.isCancelled, isTrue);
      expect(find.text('Results for “query”'), findsOneWidget);
      expect(
        find.text(AppLocalizations.of(tester.element(input)).searchDraftNotice),
        findsOneWidget,
      );
      expect(more, findsNothing);
      await tester.enterText(input, 'query');
      pending.pending.complete(Success(page(['outdated'])));
      await tester.pumpAndSettle();
      expect(more, findsNothing);
      expect(find.text('outdated'), findsNothing);
      expect(find.text('one'), findsOneWidget);
      expect(h.repository.calls.length, 5);
    },
    variant: windows,
  );

  testWidgets('standalone pushed Search has a real back button', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final h = SearchHarness(tester);
    await h.mount(home: const Scaffold(body: Text('Root')));
    h.navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => h.screen()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);
    expect(h.repository.calls, isEmpty);
  }, variant: windows);

  testWidgets(
    'toolbar wraps long title and actions without a fixed height',
    (tester) async {
      addTearDown(tester.view.reset);
      final h = SearchHarness(tester);
      var activated = 0;
      final title = List.filled(3, 'A longer workspace page title').join(' ');
      await h.mount(
        width: 900,
        height: 500,
        scale: 2,
        home: Scaffold(
          body: DesktopContentFrame(
            maxWidth: 600,
            child: DesktopPageToolbar(
              title: title,
              actions: [
                TextButton(
                  onPressed: () => activated++,
                  child: const Text('First action'),
                ),
                TextButton(
                  onPressed: () => activated++,
                  child: const Text('Second action'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byType(DesktopPageToolbar)).height,
        greaterThan(kToolbarHeight),
      );
      expect(
        tester.getRect(find.text('First action')).top,
        greaterThan(tester.getRect(find.text(title)).bottom),
      );
      await tester.tap(find.text('Second action'));
      expect(activated, 1);
      expect(tester.takeException(), isNull);
    },
    variant: windows,
  );

  testWidgets(
    'variable-height author rows keep the visible result when reflowing',
    (tester) async {
      addTearDown(tester.view.reset);
      final h = SearchHarness(tester);
      await h.mount(width: 900, scale: 1.5);
      final result = SearchPage(
        sourceId: sourceId,
        items: [
          for (var i = 0; i < 60; i++)
            NovelSummary(
              key: NovelKey(sourceId: sourceId, novelId: 'long-$i'),
              title: 'Book $i',
              authors: [List.filled(12, 'Long author name 作者').join(', ')],
            ),
        ],
      );
      await h.search(result);
      h.field.focusNode!.unfocus();
      final scroll = h.viewport.controller!;
      scroll.jumpTo(2800);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(CustomScrollView));
      final book = result.items.firstWhere((book) {
        final row = find.byKey(ValueKey(book.key));
        return row.evaluate().isNotEmpty &&
            tester
                .getRect(row)
                .contains(Offset(bounds.center.dx, bounds.center.dy));
      });
      final row = find.byKey(ValueKey(book.key));
      final originalHeight = tester.getSize(row).height;
      await h.resize(1920);
      expect(tester.getSize(row).height, lessThan(originalHeight));
      expect(
        tester
            .getRect(row)
            .overlaps(tester.getRect(find.byType(CustomScrollView))),
        isTrue,
      );
      await h.resize(839);
      expect(
        tester
            .getRect(row)
            .overlaps(tester.getRect(find.byType(CustomScrollView))),
        isTrue,
      );
      expect(h.repository.calls.length, 1);
    },
    variant: windows,
  );

  testWidgets(
    'desktop cancels old search and ignores completion after a newer result',
    (tester) async {
      addTearDown(tester.view.reset);
      final h = SearchHarness(tester);
      await h.mount();
      await tester.enterText(input, 'old');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final old = h.repository.calls.single;
      await tester.enterText(input, 'new');
      await tester.pump();
      expect(old.token.isCancelled, isTrue);
      await h.resize(900);
      await h.mount(width: 900, dark: true);
      expect(h.repository.calls.length, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      h.repository.calls.last.pending.complete(Success(page(['current'])));
      await tester.pumpAndSettle();
      old.pending.complete(Success(page(['outdated'])));
      await tester.pumpAndSettle();
      expect(find.text('current'), findsOneWidget);
      expect(find.text('outdated'), findsNothing);
      expect(find.text('Results for “new”'), findsOneWidget);
      expect(h.repository.calls.length, 2);
    },
    variant: windows,
  );
}
