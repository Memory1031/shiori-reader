import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/features/bookshelf/book_selection_widgets.dart';
import 'package:shiori/shared/widgets/book_list_tile.dart';
import 'package:shiori/shared/widgets/state_views.dart';

import 'harness.dart';

Future<void> screenshot(GlobalKey boundary, String name) async {
  final directory = Platform.environment['SHIORI_REPARSE_SCREENSHOTS'];
  if (directory == null) return;
  final image =
      await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  await Directory(directory).create(recursive: true);
  await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
}

Widget preview(BuildContext context, Widget child, GlobalKey boundary) {
  if (Platform.environment['SHIORI_REPARSE_FONT'] != null) {
    final theme = Theme.of(context);
    child = Theme(
      data: theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
            fontFamily: 'Roboto',
          ),
        ),
      ),
      child: child,
    );
  }
  return RepaintBoundary(key: boundary, child: child);
}

void main() {
  setUpAll(() async {
    final font = Platform.environment['SHIORI_REPARSE_FONT'];
    if (font == null) return;
    final bytes = ByteData.sublistView(await File(font).readAsBytes());
    for (final family in [
      'Roboto',
      'Microsoft YaHei UI',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });

  testWidgets(
    'TXT recovery previews only this book and hides advanced choices',
    (tester) async {
      final store = LocalStore(count: 2);
      final boundary = GlobalKey();
      final h = LocalHarness(
        tester,
        store: store,
        preview: (context, child) => preview(context, child, boundary),
      );
      addTearDown(h.close);
      await h.pump(width: 320, height: 780, scale: 1.6);
      final key = store.books.last.key;
      final menu = find.byKey(ValueKey(('local-book-actions', key)));
      final l = h.l;
      Future<void> openRecovery() async {
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.localTextDisplay));
        await tester.pumpAndSettle();
      }

      await openRecovery();
      expect(find.byType(DropdownButton<TxtEncoding?>), findsNothing);
      expect(store.calls, isEmpty);
      await tester.runAsync(() => screenshot(boundary, 'txt-recovery-ready'));
      await tester.tap(find.widgetWithText(FilledButton, l.localTextPreview));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.calls.single.key, key);
      expect(store.calls.single.reviewText, isTrue);
      expect(store.calls.single.encoding, isNull);
      expect(find.text('Sample'), findsOneWidget);
      expect(find.text('Other sample'), findsOneWidget);
      expect(find.text('UTF-8'), findsNothing);
      await tester.runAsync(() => screenshot(boundary, 'txt-recovery-preview'));
      await tester.tap(find.widgetWithText(OutlinedButton, l.importCancel));
      await tester.pumpAndSettle();
      expect(store.calls.single.token.isCancelled, isTrue);
      expect(store.revision, 0);

      await openRecovery();
      await tester.tap(find.text(l.localTextAdvanced));
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButton<TxtEncoding?>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GB18030 / GBK').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l.localTextPreview));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.calls.map((c) => c.key), [key, key]);
      expect(store.calls.last.encoding, TxtEncoding.gb18030);
      expect(find.text('Sample'), findsNothing);
      await tester.tap(find.text(l.importUseText));
      await tester.pumpAndSettle();
      expect(store.revision, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (name, platform, width, lang, scale, dark, format, count) in [
    (
      'phone-epub',
      TargetPlatform.android,
      390.0,
      'zh',
      1.0,
      false,
      LocalBookFormat.epub,
      2,
    ),
    (
      'phone-txt',
      TargetPlatform.android,
      390.0,
      'en',
      1.0,
      false,
      LocalBookFormat.txt,
      2,
    ),
    ('phone-dark-large', TargetPlatform.iOS, 390.0, 'en', 1.8, true, null, 3),
    (
      'desktop-light',
      TargetPlatform.windows,
      1280.0,
      'en',
      1.0,
      false,
      null,
      3,
    ),
    (
      'desktop-dark-large',
      TargetPlatform.windows,
      900.0,
      'zh',
      2.0,
      true,
      null,
      3,
    ),
    ('phone-empty', TargetPlatform.android, 390.0, 'zh', 1.0, false, null, 0),
  ]) {
    testWidgets('quiet local library $name', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = dark
          ? Brightness.dark
          : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final store = LocalStore(count: count);
      if (format != null) {
        for (var i = 0; i < count; i++) {
          final b = store.books[i];
          store.books[i] = LocalBookInfo(
            key: b.key,
            title: b.title,
            format: format,
            importedAt: b.importedAt,
          );
        }
      }
      final boundary = GlobalKey();
      final h = LocalHarness(
        tester,
        store: store,
        preview: (context, child) => preview(context, child, boundary),
      );
      await h.pump(width: width, height: 900, lang: lang, scale: scale);
      final card = find.byKey(const ValueKey('local-library-summary'));
      expect(
        find.byKey(const ValueKey('local-books-reparse-all')),
        findsNothing,
      );
      expect(find.byIcon(Icons.autorenew), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      if (count == 0) {
        expect(card, findsNothing);
        expect(find.text(h.l.localBooksEmpty), findsOneWidget);
      } else {
        if (format == null) {
          expect(card, findsNothing);
          expect(find.byType(ChoiceChip), findsNWidgets(3));
          expect(
            find.widgetWithText(ChoiceChip, '${h.l.localFilterAll} $count'),
            findsOneWidget,
          );
        } else {
          expect(find.byType(ChoiceChip), findsNothing);
          expect(
            find.descendant(
              of: card,
              matching: find.text(h.l.localBooksCount(count)),
            ),
            findsOneWidget,
          );
          final decoration =
              tester.widget<DecoratedBox>(card).decoration as BoxDecoration;
          final context = tester.element(card);
          expect(
            decoration.color,
            summarySurfaceColor(Theme.of(context).colorScheme),
          );
          expect(
            decoration.borderRadius,
            BorderRadius.circular(ShioriShape.card),
          );
        }
        expect(find.byIcon(Icons.more_horiz), findsNWidgets(count));
        await tester.tap(find.text(store.books.first.title));
        expect(h.reads, 1);
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => screenshot(boundary, name));
      if (count == 3 && platform == TargetPlatform.android) {
        await tester.tap(find.widgetWithText(ChoiceChip, 'TXT 1'));
        await tester.pumpAndSettle();
        expect(find.text(store.books[0].title), findsNothing);
        expect(find.text(store.books[1].title), findsOneWidget);
        expect(
          find.widgetWithText(ChoiceChip, '${h.l.localFilterAll} 3'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('book-multi-select')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('book-selection-all')));
        await tester.pumpAndSettle();
        expect(find.text(h.l.bookSelectedCount(1)), findsOneWidget);
        expect(find.byType(BookSelectionCheck), findsOneWidget);
        expect(find.byIcon(Icons.more_horiz), findsNothing);
        await tester.runAsync(() => screenshot(boundary, 'phone-selected-txt'));
        await tester.tap(
          find.widgetWithText(ChoiceChip, '${h.l.localFilterAll} 3'),
        );
        await tester.pumpAndSettle();
        // Returning to all formats does not silently select the other books.
        expect(find.text(h.l.bookSelectedCount(1)), findsOneWidget);
      }
      await h.close();
    }, variant: TargetPlatformVariant.only(platform));
  }

  for (final outcome in ['success', 'failure', 'cancel']) {
    testWidgets(
      'single reparse replaces menu without moving row: $outcome',
      (tester) async {
        final store = LocalStore(count: 2)
          ..gate = Completer<Result<LocalReparseResult>>();
        final boundary = GlobalKey();
        final h = LocalHarness(
          tester,
          store: store,
          preview: (context, child) => preview(context, child, boundary),
        );
        await h.pump(width: 390, height: 900, lang: 'zh');
        final key = store.books.first.key;
        final menu = find.byKey(ValueKey(('local-book-actions', key)));
        final beforeMenu = tester.getRect(menu);
        final beforeTitle = tester.getRect(find.text(store.books.first.title));
        final beforeCover = tester.getRect(find.byType(BookListTile).first);
        final card = find.byKey(const ValueKey('local-library-summary'));
        expect(card, findsNothing);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text(h.l.localReparse));
        await tester.pumpAndSettle();
        expect(store.calls, isEmpty);
        await tester.tap(find.widgetWithText(FilledButton, h.l.localReparse));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final loading = find.byKey(ValueKey(('local-book-reparsing', key)));
        expect(loading, findsOneWidget);
        expect(menu, findsNothing);
        expect(tester.getRect(loading).size, beforeMenu.size);
        expect(tester.getRect(loading).left, beforeMenu.left);
        expect(
          tester.getRect(loading).top -
              tester.getRect(find.byType(BookListTile).first).top,
          beforeMenu.top - beforeCover.top,
        );
        expect(
          tester.getRect(find.text(store.books.first.title)).left,
          beforeTitle.left,
        );
        // The summary gains existing operation feedback, shifting rows vertically only.
        expect(
          tester.getSize(find.byType(BookListTile).first),
          beforeCover.size,
        );
        expect(
          tester.getSize(find.text(store.books.first.title)),
          beforeTitle.size,
        );
        expect(
          tester
              .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator),
              )
              .semanticsLabel,
          h.l.localReparseAllProgress(1, 1, store.books.first.title),
        );
        final otherMenu = find.byKey(
          ValueKey(('local-book-actions', store.books.last.key)),
        );
        expect(otherMenu, findsOneWidget);
        expect(
          tester.widget<PopupMenuButton<String>>(otherMenu).enabled,
          isFalse,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.byType(LinearProgressIndicator),
          ),
          findsOneWidget,
        );
        await tester.runAsync(
          () => screenshot(
            boundary,
            'phone-reparsing-$outcome-${defaultTargetPlatform.name}',
          ),
        );
        final failure = AppFailure(
          kind: FailureKind.parse,
          operation: Operation.libraryWrite,
        );
        if (outcome == 'cancel') {
          await tester.tap(find.widgetWithText(TextButton, h.l.importCancel));
          await tester.pump();
          expect(store.calls.single.token.isCancelled, isTrue);
          store.gate!.complete(
            Failure(AppFailure.cancelled(Operation.libraryWrite)),
          );
        } else {
          store.gate!.complete(
            outcome == 'success'
                ? Success(LocalReparseResult(approximate: false))
                : Failure(failure),
          );
        }
        await tester.pumpAndSettle();
        expect(loading, findsNothing);
        expect(menu, findsOneWidget);
        expect(tester.widget<PopupMenuButton<String>>(menu).enabled, isTrue);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(
          tester.getSize(find.byType(BookListTile).first),
          beforeCover.size,
        );
        if (outcome == 'failure') {
          expect(
            find.descendant(
              of: card,
              matching: find.text(failureMessage(h.l, failure)),
            ),
            findsOneWidget,
          );
        } else {
          expect(card, findsNothing);
          expect(tester.getRect(menu), beforeMenu);
        }
        expect(tester.takeException(), isNull);
        await tester.runAsync(
          () => screenshot(
            boundary,
            'phone-finished-$outcome-${defaultTargetPlatform.name}',
          ),
        );
        await h.close();
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }
}
