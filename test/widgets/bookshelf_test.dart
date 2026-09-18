import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/library_controller.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

class RemovalCache implements CacheManagement {
  final cleared = <NovelKey?>[];
  Completer<Result<void>>? pending;
  @override
  ReadingPrefetch? get prefetch => null;
  @override
  void Function() pinChapter(ChapterKey chapter) => () {};
  @override
  Future<Result<CacheOverview>> inspect({NovelKey? novel}) async =>
      Success(CacheOverview(textBytes: 0, imageBytes: 0, chapters: []));
  @override
  Future<Result<void>> clear({NovelKey? novel}) async {
    cleared.add(novel);
    return pending == null ? const Success(null) : await pending!.future;
  }
}

class ShelfLocalBooks implements LocalBookManagement {
  ShelfLocalBooks(this.repo);
  final LibraryRepository repo;
  final deleted = <NovelKey>[];
  @override
  Stream<Result<List<LocalBookInfo>>> watchBooks() =>
      Stream.value(const Success([]));
  @override
  Future<Result<LocalBookDeletion>> deleteBook(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    deleted.add(key);
    await repo.removeFromBookshelf(key, cancellation: cancellation);
    return const Success(LocalBookDeletion());
  }
}

void main() {
  for (final grid in [true, false]) {
    testWidgets(
      'local removal requires confirmation in ${grid ? "grid" : "list"}',
      (tester) async {
        final repo = FixtureLibraryRepository();
        final management = ShelfLocalBooks(repo);
        final cache = RemovalCache();
        final controller = LibraryController(
          repo,
          localBooks: management,
          cache: cache,
        )..onStart();
        final book = NovelSummary(
          key: LocalBookIdentity.book('b' * 64),
          title: 'Imported book',
        );
        await controller.add(book);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => BookshelfView(
                  controller: controller,
                  onOpen: (_) {},
                  onSearch: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (!grid) {
          await tester.tap(find.byTooltip('List'));
          await tester.pumpAndSettle();
        }
        Future<void> request() async {
          if (grid) {
            await tester.longPress(find.byKey(ValueKey(book.key)));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Remove from bookshelf'));
          } else {
            await tester.drag(
              find.byKey(ValueKey(book.key)),
              const Offset(-200, 0),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Remove'));
          }
          await tester.pumpAndSettle();
        }

        await request();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(management.deleted, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(controller.contains(book.key), isTrue);
        await request();
        await tester.tap(find.text('Delete book and progress'));
        await tester.pumpAndSettle();
        expect(management.deleted, [book.key]);
        expect(cache.cleared, isEmpty);
        expect(controller.contains(book.key), isFalse);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          controller.onDelete();
          await controller.resourcesReleased;
          controller.dispose();
          await repo.close();
        });
      },
    );
  }

  test(
    'removal waits for scoped cleanup; cleanup failure keeps entry for retry',
    () async {
      final repo = FixtureLibraryRepository();
      final cache = RemovalCache()..pending = Completer<Result<void>>();
      final c = LibraryController(repo, cache: cache)..onStart();
      final book = const FixtureData().summary(FixtureScenario.shortChapter);
      final other = const FixtureData().summary(FixtureScenario.longChapter);
      await c.add(book);
      await c.add(other);
      await Future<void>.delayed(Duration.zero);
      final attempt = c.remove(book.key);
      expect(cache.cleared, [book.key]);
      expect(c.contains(book.key), isTrue);
      expect(await c.remove(other.key), isFalse);
      cache.pending!.complete(
        Failure(
          AppFailure(
            kind: FailureKind.cache,
            operation: Operation.libraryWrite,
          ),
        ),
      );
      expect(await attempt, isFalse);
      expect(c.contains(book.key), isTrue);
      expect(c.writeFailure?.kind, FailureKind.cache);
      cache.pending = null;
      expect(await c.remove(book.key), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(c.contains(book.key), isFalse);
      expect(c.contains(other.key), isTrue);
      expect(cache.cleared, [book.key, book.key]);
      c.onDelete();
      await c.resourcesReleased;
      c.dispose();
      await repo.close();
    },
  );

  for (final language in ['zh', 'en']) {
    testWidgets('local provenance in grid and list: $language large text', (
      tester,
    ) async {
      final repo = FixtureLibraryRepository();
      final c = LibraryController(repo)..onStart();
      final local = NovelSummary(
        key: NovelKey(
          sourceId: LocalBookIdentity.sourceId,
          novelId: 'local-book',
        ),
        title: 'Local book with a long title',
      );
      final online = const FixtureData().summary(FixtureScenario.shortChapter);
      c.localFormats = {local.key: LocalBookFormat.epub};
      await c.add(local);
      await c.add(online);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: BookshelfView(controller: c, onOpen: (_) {}, onSearch: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = language == 'zh' ? '本地 · EPUB' : 'Local · EPUB';
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip(language == 'zh' ? '列表' : 'List'));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        c.onDelete();
        await c.resourcesReleased;
        c.dispose();
        await repo.close();
      });
    });
  }

  testWidgets(
    'grid taps read, long press offers details; swipe reveals actions without removing',
    (tester) async {
      final repo = FixtureLibraryRepository();
      final c = LibraryController(repo)..onStart();
      final book = const FixtureData().summary(FixtureScenario.shortChapter);
      await c.add(book);
      var reads = 0, details = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => BookshelfView(
                controller: c,
                onOpen: (_) => reads++,
                onDetails: (_) => details++,
                onSearch: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(book.key)));
      expect(reads, 1);
      final card = find.byKey(ValueKey(book.key));
      final title = find.descendant(
        of: card,
        matching: find.byType(AnimatedDefaultTextStyle),
      );
      Color? titleColor() =>
          tester.widget<AnimatedDefaultTextStyle>(title).style.color;
      final restingColor = titleColor();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(card));
      await tester.pumpAndSettle();
      expect(titleColor(), isNot(restingColor));
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(titleColor(), restingColor);
      final press = await tester.startGesture(tester.getCenter(card));
      await tester.pump(const Duration(milliseconds: 150));
      expect(titleColor(), isNot(restingColor));
      await press.cancel();
      await tester.pumpAndSettle();
      expect(titleColor(), restingColor);
      final focus = Focus.of(tester.element(title));
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(titleColor(), isNot(restingColor));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(reads, 2);
      focus.unfocus();
      await tester.pumpAndSettle();
      expect(titleColor(), restingColor);
      await tester.longPress(find.byKey(ValueKey(book.key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novel details'));
      await tester.pumpAndSettle();
      expect(details, 1);
      await tester.tap(find.byTooltip('List'));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(ValueKey(book.key)), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(c.books.length, 1);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(details, 2);
      await tester.drag(find.byKey(ValueKey(book.key)), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(c.books, isEmpty);
      expect(find.text('Undo removal'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        c.onDelete();
        await c.resourcesReleased;
        c.dispose();
        await repo.close();
      });
    },
  );
  test('add is idempotent; failed removal preserves shelf entry', () async {
    final repo = FixtureLibraryRepository();
    final c = LibraryController(repo)..onStart();
    final book = const FixtureData().summary(FixtureScenario.shortChapter);
    await c.add(book);
    await c.add(book);
    await Future<void>.delayed(Duration.zero);
    expect(c.books.length, 1);
    await c.remove(book.key);
    await Future<void>.delayed(Duration.zero);
    expect(c.books, isEmpty);
    await c.add(book);
    await Future<void>.delayed(Duration.zero);
    expect(c.books.single.snapshot, book);
    repo.controls.failNext(
      AppFailure(kind: FailureKind.database, operation: Operation.libraryWrite),
    );
    expect(await c.remove(book.key), isFalse);
    expect(c.writeFailure, isNotNull);
    expect(c.books.length, 1);
    c.onDelete();
    await c.resourcesReleased;
    c.dispose();
    await repo.close();
  });
  testWidgets('500 book grid is lazy and large text layout toggles', (
    tester,
  ) async {
    final repo = FixtureLibraryRepository();
    final c = LibraryController(repo)..onStart();
    await tester.runAsync(() async {
      for (var i = 0; i < 500; i++) {
        await c.add(
          NovelSummary(
            key: NovelKey(sourceId: SourceId('fixture'), novelId: '$i'),
            title: 'Book $i',
          ),
        );
      }
    });
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: BookshelfView(controller: c, onOpen: (_) {}, onSearch: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Book ').evaluate().length,
      inInclusiveRange(1, 39),
    );
    await tester.tap(find.byTooltip('List'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      c.onDelete();
      await c.resourcesReleased;
      c.dispose();
      await repo.close();
    });
  });
}
