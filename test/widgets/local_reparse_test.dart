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

void main() {
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
        await tester.tap(find.byType(PopupMenuButton<String>));
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
    await tester.tap(find.byType(PopupMenuButton<String>));
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
