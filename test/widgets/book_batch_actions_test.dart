import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/book_batch_actions.dart';
import 'package:shiori/features/bookshelf/book_batch_views.dart';
import 'package:shiori/features/bookshelf/book_selection_controller.dart';
import 'package:shiori/features/bookshelf/book_selection_widgets.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/bookshelf/library_controller.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/widgets/book_cover.dart';
import 'bookshelf_test.dart' show RemovalCache;
import 'local_books/harness.dart';

bool previewFontsLoaded = false;
bool get screenshots => const bool.fromEnvironment('MULTI_SELECT_SCREENSHOTS');
ThemeData previewTheme(Brightness brightness) {
  final theme = appTheme(brightness);
  return screenshots && previewFontsLoaded
      ? theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'BookSelectionPreview'),
          primaryTextTheme: theme.primaryTextTheme.apply(
            fontFamily: 'BookSelectionPreview',
          ),
        )
      : theme;
}

class QueuedStore extends LocalStore {
  QueuedStore({super.count = 3});
  LibraryRepository? library;
  final reparseGates = <Completer<Result<LocalReparseResult>>>[];
  final deleteCalls = <({NovelKey key, CancellationToken token})>[];
  final deleteGates = <Completer<Result<LocalBookDeletion>>>[];
  bool holdDeletes = false, holdReparse = true;
  @override
  Stream<Result<List<LocalBookInfo>>> watchBooks() => Stream.multi((sink) {
    final subscription = updates.stream.listen(sink.add);
    sink.add(Success(List.of(books)));
    sink.onCancel = subscription.cancel;
  });
  @override
  Future<Result<LocalReparseResult>> reparseBook(
    NovelKey key, {
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
    required CancellationToken cancellation,
  }) async {
    calls.add((key: key, token: cancellation, encoding: encoding));
    if (prompt &&
        books.any((b) => b.key == key && b.format == LocalBookFormat.txt)) {
      await chooseEncoding(
        TxtEncodingPreview({TxtEncoding.utf8: 'Synthetic sample'}),
      );
    }
    if (!holdReparse) return Success(LocalReparseResult(approximate: false));
    final gate = Completer<Result<LocalReparseResult>>();
    reparseGates.add(gate);
    return gate.future;
  }

  @override
  Future<Result<LocalBookDeletion>> deleteBook(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    deleteCalls.add((key: key, token: cancellation));
    final gate = Completer<Result<LocalBookDeletion>>();
    deleteGates.add(gate);
    final result = holdDeletes
        ? await gate.future
        : const Success(LocalBookDeletion());
    if (result is Success<LocalBookDeletion>) {
      books.removeWhere((book) => book.key == key);
      updates.add(Success(List.of(books)));
      await library?.removeFromBookshelf(
        key,
        cancellation: CancellationSource().token,
      );
    }
    return result;
  }
}

class ShelfBatchHarness {
  ShelfBatchHarness(this.tester, {QueuedStore? store})
    : store = store ?? QueuedStore();
  final WidgetTester tester;
  final QueuedStore store;
  final repository = FixtureLibraryRepository();
  final cache = RemovalCache();
  late final library = LibraryController(
    repository,
    cache: cache,
    localBooks: store,
  )..onStart();
  late final actions = BookBatchActions(
    library,
    reparse: store,
    bindShelf: true,
  );
  final layout = ValueNotifier(true);
  final storage = PageStorageBucket();
  final capture = GlobalKey();
  final online = List.generate(
    2,
    (i) => BookSelectionItem(
      NovelKey(sourceId: SourceId('fixture'), novelId: 'online-$i'),
      'Online $i',
    ),
  );
  int reads = 0, details = 0, imports = 0;
  bool desktop = false;
  String lang = 'en';
  double scale = 1;
  Brightness brightness = Brightness.light;
  late final Widget app = RepaintBoundary(
    key: capture,
    child: MaterialApp(
      locale: Locale(lang),
      theme: previewTheme(brightness),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ListenableBuilder(
        listenable: Listenable.merge([actions, library]),
        builder: (context, _) => Scaffold(
          appBar: desktop
              ? null
              : actions.selection.active
              ? BookSelectionAppBar(actions: actions)
              : AppBar(title: Text(AppLocalizations.of(context).homeShelf)),
          body: SafeArea(
            child: PageStorage(
              bucket: storage,
              child: BookshelfView(
                controller: library,
                batchActions: actions,
                localReparse: store,
                layout: layout,
                desktop: desktop,
                onSearch: () {},
                onImport: () => imports++,
                onOpen: (_) => reads++,
                onDetails: (_) => details++,
                header: TextButton(
                  onPressed: () => reads++,
                  child: const Text('Continue synthetic book'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> pump({
    bool desktop = false,
    double width = 390,
    double scale = 1,
    String lang = 'en',
    Brightness brightness = Brightness.light,
    int extra = 0,
  }) async {
    this.desktop = desktop;
    this.lang = lang;
    this.scale = scale;
    this.brightness = brightness;
    tester.view
      ..physicalSize = Size(width, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (screenshots && !previewFontsLoaded) {
      final font = Platform.environment['SHIORI_SELECTION_FONT'];
      if (font != null) {
        await tester.runAsync(() async {
          final bytes = ByteData.sublistView(await File(font).readAsBytes());
          await (FontLoader(
            'BookSelectionPreview',
          )..addFont(Future.value(bytes))).load();
          await (FontLoader(
            'Microsoft YaHei UI',
          )..addFont(Future.value(bytes))).load();
          await (FontLoader(
            'Microsoft YaHei',
          )..addFont(Future.value(bytes))).load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          previewFontsLoaded = true;
        });
      }
    }
    store.library = repository;
    final token = CancellationSource().token;
    for (final book in [
      ...store.books.map(
        (b) => BookSelectionItem(b.key, b.title, format: b.format),
      ),
      ...online,
      for (var i = 0; i < extra; i++)
        BookSelectionItem(
          NovelKey(sourceId: SourceId('fixture'), novelId: 'extra-$i'),
          'Extra $i',
        ),
    ]) {
      await repository.putBookshelf(
        BookshelfEntry(
          snapshot: NovelSummary(key: book.key, title: book.title),
          addedAt: DateTime.utc(2026),
        ),
        cancellation: token,
      );
    }
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  AppLocalizations get l =>
      AppLocalizations.of(tester.element(find.byType(BookshelfView)));
  Future<void> frame() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> selectAll() async {
    if (desktop) {
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
    } else {
      await tester.longPress(find.byKey(ValueKey(store.books.first.key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.bookMultiSelect));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('book-selection-all')));
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(String name) async {
    if (!const bool.fromEnvironment('MULTI_SELECT_SCREENSHOTS')) return;
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = Directory('.tooling/multi-select-screenshots');
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    });
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    actions.dispose();
    layout.dispose();
    await tester.pumpAndSettle();
    library.onDelete();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await library.resourcesReleased;
      library.dispose();
      await store.close();
      await repository.close();
    });
  }
}

final reparseSuccess = Success(
  LocalReparseResult(approximate: true, cleanupPending: true),
);
final parseFailure = Failure<LocalReparseResult>(
  AppFailure(kind: FailureKind.parse, operation: Operation.libraryWrite),
);

void main() {
  testWidgets(
    'desktop batch dialogs bound text width and collapse completed details',
    (tester) async {
      final h = ShelfBatchHarness(tester);
      addTearDown(h.close);
      await h.pump(desktop: true, width: 1440, lang: 'zh');
      final local = h.actions.selection.visible.where((b) => b.local).toList();
      h.actions.enter();
      for (final book in local.take(2)) {
        h.actions.selection.toggle(book.key);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-selection-remove')));
      await tester.pumpAndSettle();
      // A long notice widens the dialog; the book list follows it.
      expect(
        tester.getSize(find.byType(BookBatchPreview)).width,
        tester.getSize(find.text(h.l.bookBatchRemoveConfirm(2))).width,
      );
      await h.screenshot('15-windows-local-removal-confirmation');
      await tester.tap(find.widgetWithText(TextButton, h.l.importCancel).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-selection-reparse')));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      final surface = find.descendant(
        of: dialog,
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.type == MaterialType.card,
        ),
      );
      expect(tester.getSize(surface).width, lessThanOrEqualTo(560));
      expect(tester.getSize(surface).height, lessThan(440));
      expect(find.text(h.l.bookReparseSelectedConfirm(2, 0)), findsOneWidget);
      await h.screenshot('10-windows-reparse-confirmation');
      await tester.tap(find.widgetWithText(TextButton, h.l.importCancel).last);
      await tester.pumpAndSettle();
      expect(h.store.calls, isEmpty);
      h.actions.selection.toggle(local.last.key);
      h.store.holdReparse = false;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-selection-reparse')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, h.l.bookReparseSelected(3)),
      );
      await tester.pumpAndSettle();
      expect(find.text(h.l.bookBatchSummary(3, 0, 0, 0, 0)), findsOneWidget);
      expect(
        find.byKey(ValueKey(('batch-result', local.first.key))),
        findsNothing,
      );
      expect(tester.getSize(surface).height, lessThan(320));
      final collapsedWidth = tester.getSize(surface).width;
      await h.screenshot('11-windows-success-summary');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.text(h.l.bookBatchSuccessDetails(3))),
      );
      await tester.pumpAndSettle();
      await h.screenshot('13-windows-success-hover-collapsed');
      await tester.tap(find.text(h.l.bookBatchSuccessDetails(3)));
      await tester.pumpAndSettle();
      await mouse.moveTo(
        tester.getCenter(find.text(h.l.bookBatchSuccessDetails(3))),
      );
      await tester.pumpAndSettle();
      await h.screenshot('14-windows-success-hover-expanded');
      await mouse.removePointer();
      expect(
        find.byKey(ValueKey(('batch-result', local.first.key))),
        findsOneWidget,
      );
      await h.screenshot('12-windows-success-details');
      expect(tester.getSize(surface).width, collapsedWidth);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'mixed selected reparse confirms frozen local keys; serial failure retains only remaining keys',
    (tester) async {
      final h = ShelfBatchHarness(tester);
      await h.pump();
      await h.screenshot('01-phone-normal');
      final local = h.actions.selection.visible
          .where((b) => b.local)
          .map((b) => b.key)
          .toList();
      await h.selectAll();
      expect(h.actions.selection.selected, hasLength(5));
      expect(h.actions.eligible, 3);
      await h.screenshot('02-phone-selection');
      await tester.tap(find.byKey(const ValueKey('book-selection-reparse')));
      await tester.pumpAndSettle();
      expect(find.text(h.l.bookReparseSelectedConfirm(3, 2)), findsOneWidget);
      expect(h.store.calls, isEmpty);
      expect(h.library.writing, isTrue);
      await h.screenshot('03-mixed-reparse-confirmation');
      await tester.tap(
        find.widgetWithText(FilledButton, h.l.bookReparseSelected(3)),
      );
      await h.frame();
      expect(h.store.calls.map((c) => c.key), [local[0]]);
      await h.screenshot('04-batch-running');
      h.store.reparseGates[0].complete(reparseSuccess);
      await h.frame();
      expect(h.store.calls.map((c) => c.key), local.take(2));
      h.store.reparseGates[1].complete(parseFailure);
      await h.frame();
      expect(h.store.calls.map((c) => c.key), local);
      h.store.reparseGates[2].complete(reparseSuccess);
      await tester.pumpAndSettle();
      expect(find.text(h.l.bookBatchSummary(2, 1, 0, 0, 2)), findsOneWidget);
      expect(find.text(h.l.bookReparseCleanupPending), findsOneWidget);
      await h.screenshot('05-batch-partial-failure');
      await tester.tap(find.text(h.l.importDone));
      await tester.pumpAndSettle();
      expect(h.library.writing, isFalse);
      expect(h.actions.selection.selected, {
        local[1],
        ...h.online.map((b) => b.key),
      });
      expect(h.reads, 0);
      await tester.tap(find.byKey(const ValueKey('book-selection-reparse')));
      await tester.pumpAndSettle();
      expect(find.text(h.l.bookReparseSelectedConfirm(1, 2)), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, h.l.bookReparseSelected(1)),
      );
      await h.frame();
      expect(h.store.calls.last.key, local[1]);
      expect(h.store.calls, hasLength(4));
      h.store.reparseGates.last.complete(reparseSuccess);
      await tester.pumpAndSettle();
      await tester.tap(find.text(h.l.importDone));
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, h.online.map((b) => b.key).toSet());
      await h.close();
    },
  );

  testWidgets(
    'mixed removal cancel is zero calls; frozen denominator and distinct consequences',
    (tester) async {
      final h = ShelfBatchHarness(
        tester,
        store: QueuedStore()..holdDeletes = true,
      );
      await h.pump();
      await h.selectAll();
      final local = h.actions.selection.visible
          .where((b) => b.local)
          .map((b) => b.key)
          .toList();
      await tester.tap(find.byKey(const ValueKey('book-selection-remove')));
      await tester.pumpAndSettle();
      expect(find.text(h.l.bookBatchLocal(3)), findsOneWidget);
      expect(find.text(h.l.bookBatchOnline(2)), findsOneWidget);
      expect(h.store.deleteCalls, isEmpty);
      expect(h.cache.cleared, isEmpty);
      expect(await h.library.remove(local.first), isFalse);
      await h.screenshot('06-mixed-removal-confirmation');
      await tester.tap(
        find.descendant(
          of: find.byType(BookBatchPanel),
          matching: find.widgetWithText(OutlinedButton, h.l.importCancel),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, hasLength(5));
      await tester.tap(find.byKey(const ValueKey('book-selection-remove')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, h.l.bookRemoveSelected),
      );
      await h.frame();
      expect(h.store.deleteCalls, hasLength(1));
      h.store.deleteGates[0].complete(
        const Success(LocalBookDeletion(cleanupPending: true)),
      );
      await h.frame();
      expect(h.store.deleteCalls, hasLength(2));
      h.store.deleteGates[1].complete(
        Failure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.libraryWrite,
          ),
        ),
      );
      await h.frame();
      expect(h.store.deleteCalls, hasLength(3));
      h.store.deleteGates[2].complete(const Success(LocalBookDeletion()));
      await tester.pumpAndSettle();
      expect(find.text(h.l.bookBatchSummary(4, 1, 0, 0, 0)), findsOneWidget);
      expect(h.cache.cleared, h.online.map((b) => b.key).toList());
      expect(h.library.writing, isTrue);
      await tester.tap(find.text(h.l.importDone));
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, {local[1]});
      expect(h.library.writing, isFalse);
      await h.close();
    },
  );

  for (final operation in ['remove', 'reparse']) {
    testWidgets(
      '$operation Stop holds shared lock while committed success settles; no next dispatch',
      (tester) async {
        final h = ShelfBatchHarness(
          tester,
          store: QueuedStore()..holdDeletes = true,
        );
        await h.pump();
        await h.selectAll();
        if (operation == 'remove') {
          for (final book in h.online) {
            h.actions.selection.toggle(book.key);
          }
          await tester.pumpAndSettle();
        }
        final keys = h.actions.selection.selected;
        await tester.tap(find.byKey(ValueKey('book-selection-$operation')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            operation == 'remove'
                ? h.l.bookDeleteSelected
                : h.l.bookReparseSelected(3),
          ),
        );
        await h.frame();
        await tester.tap(find.text(h.l.localReparseStop));
        await h.frame();
        expect(h.library.writing, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await h.frame();
        expect(find.byType(BookBatchPanel), findsOneWidget);
        if (operation == 'remove') {
          expect(h.store.deleteCalls.single.token.isCancelled, isTrue);
          h.store.deleteGates.single.complete(
            const Success(LocalBookDeletion(cleanupPending: true)),
          );
        } else {
          expect(h.store.calls.single.token.isCancelled, isTrue);
          h.store.reparseGates.single.complete(reparseSuccess);
        }
        await tester.pumpAndSettle();
        expect(h.store.deleteCalls.length + h.store.calls.length, 1);
        expect(
          find.text(
            h.l.bookBatchSummary(1, 0, 2, 0, operation == 'remove' ? 0 : 2),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text(h.l.importDone));
        await tester.pumpAndSettle();
        expect(
          h.actions.selection.selected,
          keys.difference({
            h.store.calls.firstOrNull?.key ?? h.store.deleteCalls.single.key,
          }),
        );
        await h.close();
      },
    );
  }

  testWidgets(
    'desktop keyboard, checkbox hit, right click and geometry across layout/resize',
    (tester) async {
      final h = ShelfBatchHarness(tester);
      await h.pump(
        desktop: true,
        width: 1280,
        lang: 'zh',
        brightness: Brightness.dark,
        extra: 30,
      );
      final firstKey = h.library.sorted.first.snapshot.key;
      final cover = tester.getSize(
        find
            .descendant(
              of: find.byKey(ValueKey(firstKey)),
              matching: find.byType(BookCover),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, isEmpty);
      final row = find.byKey(ValueKey(firstKey));
      final check = find.descendant(
        of: row,
        matching: find.byType(BookSelectionCheck),
      );
      await tester.ensureVisible(check);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(check));
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, {firstKey});
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(row),
        matchesSemantics(
          isChecked: true,
          hasCheckedState: true,
          isSelected: true,
          hasSelectedState: true,
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
          label:
              '${h.l.bookToggleSelection(h.library.sorted.first.snapshot.title)}\n${h.library.sorted.first.snapshot.title}',
        ),
      );
      semantics.dispose();
      expect(
        tester.getSize(
          find.descendant(of: row, matching: find.byType(BookCover)),
        ),
        cover,
      );
      final focus = tester
          .widget<InkWell>(
            find.descendant(of: row, matching: find.byType(InkWell)).first,
          )
          .focusNode!;
      for (var i = 0; i < 20 && !focus.hasFocus; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, isEmpty);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, hasLength(35));
      await tester.tap(row, buttons: kSecondaryMouseButton);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(find.text(h.l.localDeleteConfirm), findsNothing);
      expect(h.store.deleteCalls, isEmpty);
      await h.screenshot('07-windows-selection-toolbar');
      h.layout.value = false;
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, hasLength(35));
      final listCover = tester.getSize(
        find.descendant(
          of: find.byKey(ValueKey(firstKey)),
          matching: find.byType(BookCover),
        ),
      );
      expect(listCover.width, 40);
      tester.view.physicalSize = const Size(560, 844);
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, hasLength(35));
      expect(tester.takeException(), isNull);
      await h.screenshot('08-windows-narrow-selection');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.actions.selection.active, isFalse);
      expect(h.reads, 0);
      expect(h.details, 0);
      await h.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'mobile list has one toggle and closes swipe; overlay back has priority',
    (tester) async {
      final h = ShelfBatchHarness(tester);
      await h.pump();
      h.layout.value = false;
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey(h.store.books.first.key));
      await tester.drag(row, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(find.text(h.l.shelfRemove), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey(('shelf-more', h.store.books.first.key))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(h.l.bookMultiSelect));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: row, matching: find.text(h.l.shelfRemove)),
        findsNothing,
      );
      await h.screenshot('09-phone-selection-list');
      final check = find.descendant(
        of: row,
        matching: find.byType(BookSelectionCheck),
      );
      await tester.ensureVisible(check);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(check));
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, isEmpty);
      await tester.drag(row, const Offset(-200, 0));
      await tester.longPress(row);
      await tester.pumpAndSettle();
      expect(find.text(h.l.detailRemoveShelf), findsNothing);
      expect(h.actions.selection.selected, hasLength(1));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 700));
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getCenter(find.text('Continue synthetic book')),
      );
      expect(h.reads, 0);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, isEmpty);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('book-selection-remove')));
      await tester.pumpAndSettle();
      expect(find.byType(BookBatchPanel), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.actions.selection.active, isTrue);
      expect(find.byType(BookBatchPanel), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.actions.selection.active, isFalse);
      expect(h.store.deleteCalls, isEmpty);
      await h.close();
    },
  );

  testWidgets(
    'background retires unconfirmed selection without mutation or resume dispatch',
    (tester) async {
      final h = ShelfBatchHarness(tester);
      await h.pump();
      await h.selectAll();
      await tester.tap(find.byKey(const ValueKey('book-selection-remove')));
      await tester.pumpAndSettle();
      expect(h.library.writing, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(h.actions.selection.active, isFalse);
      expect(find.byType(BookBatchPanel), findsNothing);
      expect(h.library.writing, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.store.deleteCalls, isEmpty);
      expect(h.cache.cleared, isEmpty);
      expect(find.byType(BookBatchPanel), findsNothing);
      await h.close();
    },
  );

  testWidgets(
    'owner exit cancels current work, waits for settlement and preserves unrelated root dialog',
    (tester) async {
      final h = ShelfBatchHarness(tester);
      await h.pump();
      await h.selectAll();
      await tester.tap(find.byKey(const ValueKey('book-selection-reparse')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, h.l.bookReparseSelected(3)),
      );
      await h.frame();
      final context = tester.element(find.byType(BookshelfView));
      final other = DialogRoute<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Unrelated dialog')),
      );
      unawaited(Navigator.of(context, rootNavigator: true).push(other));
      await h.frame();
      h.actions.leave();
      await h.frame();
      expect(h.store.calls.single.token.isCancelled, isTrue);
      expect(h.library.writing, isTrue);
      expect(find.text('Unrelated dialog'), findsOneWidget);
      h.store.reparseGates.single.complete(reparseSuccess);
      await tester.pumpAndSettle();
      expect(h.library.writing, isFalse);
      expect(h.store.calls, hasLength(1));
      expect(h.actions.selection.active, isFalse);
      expect(find.text('Unrelated dialog'), findsOneWidget);
      other.navigator!.removeRoute(other);
      await tester.pumpAndSettle();
      await h.close();
    },
  );

  testWidgets(
    'missing confirmed book is skipped; additions and repeated start cannot enter frozen batch',
    (tester) async {
      final h = ShelfBatchHarness(tester);
      await h.pump();
      await h.selectAll();
      final targets = h.actions.selection.snapshot
          .where((b) => b.local)
          .toList();
      final owner = tester.element(find.byType(BookshelfView));
      await tester.tap(find.byKey(const ValueKey('book-selection-reparse')));
      await tester.pumpAndSettle();
      await h.actions.reparseSelected(owner);
      expect(find.byType(BookBatchPanel), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, h.l.bookReparseSelected(3)),
      );
      await h.frame();
      await h.repository.removeFromBookshelf(
        targets[1].key,
        cancellation: CancellationSource().token,
      );
      final added = NovelKey(sourceId: SourceId('fixture'), novelId: 'new');
      await h.repository.putBookshelf(
        BookshelfEntry(
          snapshot: NovelSummary(key: added, title: 'New'),
          addedAt: DateTime.utc(2026),
        ),
        cancellation: CancellationSource().token,
      );
      await h.frame();
      h.store.reparseGates.first.complete(reparseSuccess);
      await h.frame();
      expect(h.store.calls.map((c) => c.key), [targets[0].key, targets[2].key]);
      h.store.reparseGates.last.complete(reparseSuccess);
      await tester.pumpAndSettle();
      expect(find.text(h.l.bookBatchSummary(2, 0, 0, 1, 2)), findsOneWidget);
      await tester.tap(find.text(h.l.importDone));
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, h.online.map((b) => b.key).toSet());
      expect(h.actions.selection.selected, isNot(contains(added)));
      await h.close();
    },
  );

  testWidgets(
    'selected one TXT retains selected wording; encoding cancel stops without another book',
    (tester) async {
      final h = ShelfBatchHarness(tester, store: QueuedStore()..prompt = true);
      await h.pump(desktop: true, width: 1100);
      await tester.tap(find.byKey(const ValueKey('book-multi-select')));
      await tester.pumpAndSettle();
      final txt = h.store.books.firstWhere(
        (b) => b.format == LocalBookFormat.txt,
      );
      await tester.tap(find.byKey(ValueKey(txt.key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('book-selection-reparse')));
      await tester.pumpAndSettle();
      expect(find.text(h.l.bookReparseSelectedConfirm(1, 0)), findsOneWidget);
      expect(find.byType(DropdownButton<TxtEncoding>), findsNothing);
      await tester.tap(
        find.widgetWithText(FilledButton, h.l.bookReparseSelected(1)),
      );
      await h.frame();
      expect(find.text('Synthetic sample'), findsOneWidget);
      expect(h.store.calls.single.key, txt.key);
      await tester.tap(
        find.descendant(
          of: find.byType(BookBatchPanel).last,
          matching: find.widgetWithText(OutlinedButton, h.l.importCancel),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.store.calls, hasLength(1));
      expect(h.store.reparseGates, isEmpty);
      expect(find.text(h.l.bookBatchSummary(0, 0, 1, 0, 0)), findsOneWidget);
      await tester.tap(find.text(h.l.importDone));
      await tester.pumpAndSettle();
      expect(h.actions.selection.selected, {txt.key});
      expect(h.library.writing, isFalse);
      await h.close();
    },
  );
}
