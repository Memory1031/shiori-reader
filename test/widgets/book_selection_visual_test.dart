import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/bookshelf/book_selection_widgets.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/widgets/desktop_content_frame.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

import 'local_books/harness.dart';

const capturePreview = bool.fromEnvironment('MULTI_SELECT_SCREENSHOTS');
bool fontsLoaded = false;

Future<void> loadFonts(WidgetTester tester) async {
  final font = Platform.environment['SHIORI_SELECTION_FONT'];
  if (!capturePreview || fontsLoaded || font == null) return;
  await tester.runAsync(() async {
    final bytes = ByteData.sublistView(await File(font).readAsBytes());
    await (FontLoader('SelectionPreview')..addFont(Future.value(bytes))).load();
    await (FontLoader(
      'Microsoft YaHei UI',
    )..addFont(Future.value(bytes))).load();
    await (FontLoader('Microsoft YaHei')..addFont(Future.value(bytes))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  fontsLoaded = true;
}

class VisualHarness extends LocalHarness {
  VisualHarness(super.tester, this.capture, {int count = 12})
    : super(
        store: LocalStore(count: count),
        preview: (context, child) {
          final theme = Theme.of(context);
          return RepaintBoundary(
            key: capture,
            child: Theme(
              data: fontsLoaded
                  ? theme.copyWith(
                      appBarTheme: theme.appBarTheme.copyWith(
                        titleTextStyle: theme.appBarTheme.titleTextStyle
                            ?.copyWith(fontFamily: 'SelectionPreview'),
                      ),
                      textTheme: theme.textTheme.apply(
                        fontFamily: 'SelectionPreview',
                      ),
                      primaryTextTheme: theme.primaryTextTheme.apply(
                        fontFamily: 'SelectionPreview',
                      ),
                    )
                  : theme,
              child: child,
            ),
          );
        },
      );
  final GlobalKey capture;
  @override
  AppLocalizations get l =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).last));

  Future<void> seedShelf() async {
    for (final info in store.books) {
      await library.putBookshelf(
        BookshelfEntry(
          snapshot: NovelSummary(key: info.key, title: info.title),
          addedAt: info.importedAt,
        ),
        cancellation: CancellationSource().token,
      );
    }
  }

  Future<void> shot(String name) async {
    if (!capturePreview) return;
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/brand/shiori.png'),
        capture.currentContext!,
      ),
    );
    await tester.pump();
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = Directory(
        Platform.environment['SHIORI_SELECTION_SCREENSHOTS'] ??
            '.tooling/multi-select-visual',
      );
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    });
  }
}

void main() {
  testWidgets(
    'phone real home preserves app bar height and book geometry in selection',
    (tester) async {
      await loadFonts(tester);
      final h = VisualHarness(tester, GlobalKey());
      addTearDown(h.close);
      await h.seedShelf();
      await h.pump(width: 390, height: 844, shell: true, lang: 'zh');
      h.navigation.select(HomeSection.shelf);
      await tester.pumpAndSettle();
      final normalBar = tester.getRect(find.byType(AppBar));
      final controller = tester
          .widget<BookshelfView>(find.byType(BookshelfView))
          .controller;
      final book = find.byKey(ValueKey(controller.sorted.first.snapshot.key));
      final normalSize = tester.getSize(book);
      await h.shot('phone-grid-normal');
      await tester.tap(find.byTooltip(h.l.moreActions).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(h.l.bookMultiSelect));
      await tester.pumpAndSettle();
      final shelf = tester.widget<BookshelfView>(find.byType(BookshelfView));
      for (final item in shelf.batchActions!.selection.visible.take(3)) {
        shelf.batchActions!.selection.toggle(item.key);
      }
      await tester.pumpAndSettle();
      final selectedBar = tester.getRect(find.byType(BookSelectionAppBar));
      await h.shot('phone-grid-three-selected');
      expect(tester.getSize(book), normalSize);
      expect(selectedBar.height, normalBar.height);
      final exit = tester.getRect(
        find.byKey(const ValueKey('book-selection-exit')),
      );
      final all = tester.getRect(
        find.byKey(const ValueKey('book-selection-all')),
      );
      shelf.batchActions!.selection.toggleAll();
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('book-selection-exit'))),
        exit,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('book-selection-all'))),
        all,
      );
      shelf.layout!.value = false;
      await tester.pumpAndSettle();
      final view = find
          .descendant(
            of: find.byType(BookshelfView),
            matching: find.byType(Scrollable),
          )
          .first;
      final last = shelf.batchActions!.selection.visible.last;
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(last.key)),
        400,
        scrollable: view,
      );
      await tester.ensureVisible(find.byKey(ValueKey(last.key)));
      await tester.pumpAndSettle();
      await h.shot('phone-list-all-last-row');
      expect(
        tester.getRect(find.byKey(ValueKey(last.key))).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byType(BookSelectionBottomBar)).top,
        ),
      );
    },
  );

  testWidgets(
    'local English 2x selection keeps app bar and SafeArea last row',
    (tester) async {
      await loadFonts(tester);
      tester.view.padding = const FakeViewPadding(bottom: 34, top: 24);
      addTearDown(tester.view.resetPadding);
      final h = VisualHarness(tester, GlobalKey());
      addTearDown(h.close);
      await h.pump(width: 390, height: 844, scale: 2, lang: 'en');
      final normalBar = tester.getRect(find.byType(AppBar));
      await h.shot('local-phone-en-2x-normal');
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-selection-all')));
      await tester.pumpAndSettle();
      final selectedBar = tester.getRect(find.byType(BookSelectionAppBar));
      await h.shot('local-phone-en-2x-selection');
      expect(selectedBar.height, normalBar.height);
      final last = h.store.books.last;
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(last.key)),
        500,
        scrollable: find
            .descendant(of: h.view, matching: find.byType(Scrollable))
            .first,
      );
      await tester.ensureVisible(find.byKey(ValueKey(last.key)));
      await tester.pumpAndSettle();
      await h.shot('local-phone-en-2x-last-row');
      expect(
        tester.getRect(find.byKey(ValueKey(last.key))).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byType(BookSelectionBottomBar)).top,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Windows real Workspace selection matches page chrome at 1280 and 840',
    (tester) async {
      await loadFonts(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final h = VisualHarness(tester, GlobalKey(), count: 35);
      addTearDown(h.close);
      await h.seedShelf();
      await h.pump(width: 1280, height: 844, shell: true, lang: 'zh');
      await h.shot('windows-local-normal');
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-selection-all')));
      await tester.pumpAndSettle();
      await h.shot('windows-local-selection');
      h.navigation.select(HomeSection.shelf);
      await tester.pumpAndSettle();
      final normalBar = tester.getRect(find.byType(DesktopPageToolbar));
      await h.shot('windows-shelf-normal');
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-selection-all')));
      await tester.pumpAndSettle();
      await h.shot('windows-shelf-selection');
      final selectedBar = tester.getRect(find.byType(BookSelectionToolbar));
      expect(selectedBar.height, normalBar.height);
      expect(selectedBar.left, normalBar.left);
      await h.resize(840);
      await h.shot('windows-shelf-840');
      expect(find.text(h.l.bookSelectedCount(35)), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
