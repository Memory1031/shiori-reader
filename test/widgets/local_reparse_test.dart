import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/local_books/local_books_screen.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import '../domain/reparse_position_test.dart' as f;
import '../data/local/local_reading_test.dart' show ForbiddenOnline;

class ReparseStore
    implements LocalBookStore, LocalBookManagement, LocalBookReparse {
  final content = f.book([
    [f.p('A readable page')],
  ]);
  final events = StreamController<NovelKey>.broadcast(sync: true);
  bool called = false;
  bool approximate = true;
  bool wait = false;
  bool cancelled = false;
  @override
  Stream<NovelKey> get invalidations => events.stream;
  @override
  Stream<NovelKey> get changes => const Stream.empty();
  @override
  Stream<Result<List<LocalBookInfo>>> watchBooks() => Stream.value(
    Success([
      LocalBookInfo(
        key: f.key,
        title: 'Book',
        format: LocalBookFormat.txt,
        importedAt: DateTime.utc(2025),
      ),
    ]),
  );
  @override
  Future<Result<LocalBookRecord?>> read(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async => Success(
    LocalBookRecord(
      content: content,
      format: LocalBookFormat.txt,
      importedAt: DateTime.utc(2025),
    ),
  );
  @override
  Future<Result<LocalReparseResult>> reparseBook(
    NovelKey key, {
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
    required CancellationToken cancellation,
  }) async {
    called = true;
    if (wait) {
      await cancellation.whenCancelled;
      cancelled = true;
      return Failure(AppFailure.cancelled(Operation.libraryWrite));
    }
    return Success(LocalReparseResult(approximate: approximate));
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class BatchReparseStore extends ReparseStore {
  final books = List.generate(
    3,
    (i) => LocalBookInfo(
      key: LocalBookIdentity.book('${i + 1}' * 64),
      title: 'Book ${i + 1}',
      format: i == 1 ? LocalBookFormat.txt : LocalBookFormat.epub,
      importedAt: DateTime.utc(2025),
    ),
  );
  final calls = <NovelKey>[];
  final overrides = <TxtEncoding?>[];
  final gates = List.generate(
    3,
    (_) => Completer<Result<LocalReparseResult>>(),
  );
  bool promptEncoding = false;
  @override
  Stream<Result<List<LocalBookInfo>>> watchBooks() =>
      Stream.value(Success(books));
  @override
  Future<Result<LocalReparseResult>> reparseBook(
    NovelKey key, {
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
    required CancellationToken cancellation,
  }) async {
    final index = calls.length;
    calls.add(key);
    overrides.add(encoding);
    if (promptEncoding) {
      await chooseEncoding(TxtEncodingPreview({TxtEncoding.utf8: 'Sample'}));
    }
    return Future.any([
      gates[index].future,
      cancellation.whenCancelled.then((_) {
        cancelled = true;
        return Failure<LocalReparseResult>(
          AppFailure.cancelled(Operation.libraryWrite),
        );
      }),
    ]);
  }
}

void main() {
  Future<void> openBatch(
    WidgetTester tester,
    BatchReparseStore store, {
    String lang = 'en',
  }) async {
    await tester.pumpWidget(
      ShioriApp(
        locale: Locale(lang),
        routes: AppRoutes(
          home: (_) => LocalBooksScreen(
            store: store,
            management: store,
            library: FixtureLibraryRepository(),
            onRead: (_) {},
            onImport: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('local-books-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(lang == 'en' ? 'Reparse all' : '全部重新解析'));
    await tester.pumpAndSettle();
    expect(store.calls, isEmpty);
    await tester.tap(
      find.widgetWithText(
        FilledButton,
        lang == 'en' ? 'Reparse all' : '全部重新解析',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'local library keeps reading and import reachable on narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = BatchReparseStore();
      NovelKey? selected;
      var imports = 0;
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          overlayBuilder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.6)),
            child: child,
          ),
          routes: AppRoutes(
            home: (_) => LocalBooksScreen(
              store: store,
              management: store,
              library: FixtureLibraryRepository(),
              onRead: (key) => selected = key,
              onImport: () => imports++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.books.first.title));
      expect(selected, store.books.first.key);
      await tester.tap(find.byKey(const ValueKey('local-books-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import book'));
      await tester.pumpAndSettle();
      expect(imports, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await store.events.close();
    },
  );

  for (final lang in ['en', 'zh']) {
    testWidgets(
      'batch reparse serializes, continues after failure and reports results in $lang',
      (tester) async {
        final store = BatchReparseStore();
        await openBatch(tester, store, lang: lang);
        expect(store.calls, [store.books[0].key]);
        expect(
          tester
              .widget<PopupMenuButton<String>>(
                find.byKey(const ValueKey('local-books-actions')),
              )
              .enabled,
          isFalse,
        );
        store.gates[0].complete(Success(LocalReparseResult(approximate: true)));
        await tester.pump();
        expect(store.calls, [store.books[0].key, store.books[1].key]);
        store.gates[1].complete(
          Failure(
            AppFailure(
              kind: FailureKind.parse,
              operation: Operation.libraryWrite,
            ),
          ),
        );
        await tester.pump();
        expect(store.calls, store.books.map((b) => b.key));
        store.gates[2].complete(
          Success(LocalReparseResult(approximate: false, cleanupPending: true)),
        );
        await tester.pumpAndSettle();
        expect(store.overrides, [null, null, null]);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining(
              lang == 'en' ? 'Succeeded: 2' : '成功 2 本',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            lang == 'en' ? 'nearby positions for 1' : '1 本书恢复到了附近位置',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Book 2\n'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await store.events.close();
      },
    );
  }
  testWidgets(
    'stop batch preserves prior success and never starts remaining books',
    (tester) async {
      final store = BatchReparseStore();
      await openBatch(tester, store);
      store.gates[0].complete(Success(LocalReparseResult(approximate: false)));
      await tester.pump();
      await tester.tap(find.text('Stop reparsing'));
      await tester.pumpAndSettle();
      expect(store.cancelled, isTrue);
      expect(store.calls, hasLength(2));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(
            'Succeeded: 1 · Failed: 0 · Not processed: 2',
          ),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await store.events.close();
    },
  );
  testWidgets('cancelling per-book encoding stops the batch without hanging', (
    tester,
  ) async {
    final store = BatchReparseStore()..promptEncoding = true;
    await openBatch(tester, store);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Book 1'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(store.calls, hasLength(1));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Not processed: 3'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await store.events.close();
  });
  testWidgets(
    'leaving management cancels the batch and avoids late UI updates',
    (tester) async {
      final store = BatchReparseStore();
      await openBatch(tester, store);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(store.cancelled, isTrue);
      expect(store.calls, hasLength(1));
      expect(tester.takeException(), isNull);
      await store.events.close();
    },
  );

  for (final lang in ['en', 'zh']) {
    testWidgets(
      'reparse menu confirms and reports approximate position in $lang',
      (tester) async {
        final store = ReparseStore();
        await tester.pumpWidget(
          ShioriApp(
            locale: Locale(lang),
            routes: AppRoutes(
              home: (_) => LocalBooksScreen(
                store: store,
                management: store,
                library: FixtureLibraryRepository(),
                onRead: (_) {},
                onImport: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(('local-book-actions', f.key))));
        await tester.pumpAndSettle();
        final label = lang == 'en' ? 'Reparse' : '重新解析';
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(store.called, isFalse);
        await tester.tap(find.widgetWithText(FilledButton, label));
        await tester.pumpAndSettle();
        expect(store.called, isTrue);
        expect(
          find.textContaining(lang == 'en' ? 'nearby position' : '附近位置'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await store.events.close();
      },
    );
  }
  testWidgets('pending reparse can be cancelled from management', (
    tester,
  ) async {
    final store = ReparseStore()..wait = true;
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => LocalBooksScreen(
            store: store,
            management: store,
            library: FixtureLibraryRepository(),
            onRead: (_) {},
            onImport: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(('local-book-actions', f.key))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reparse'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reparse'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(store.cancelled, isTrue);
    await tester.pumpWidget(const SizedBox());
    await store.events.close();
  });
  testWidgets(
    'maintenance retires active local reader and removes old content',
    (tester) async {
      final store = ReparseStore();
      final repo = LocalReadingRepository(
        local: store,
        online: ForbiddenOnline(),
      );
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: store.content.chapters.first.key,
              repository: repo,
              library: FixtureLibraryRepository(),
              settings: FixtureSettingsStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      store.events.add(f.key);
      await tester.pumpAndSettle();
      expect(find.textContaining('being reparsed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await store.events.close();
    },
  );
}
