import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/cache/cache_screen.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/local_books/local_books_screen.dart';

import 'cache_screen_test.dart' show Cache;
import 'local_reparse_test.dart' show ReparseStore;

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'mobile home reparses a shelf EPUB on $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final env = FixtureEnvironment();
        final local = _EpubReparseStore()..approximate = false;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(env.close);
          await local.events.close();
        });
        final book = local.content.detail.summary;
        await env.library.putBookshelf(
          BookshelfEntry(snapshot: book, addedAt: DateTime.utc(2025)),
          cancellation: CancellationSource().token,
        );
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (_) => ReadingHome(
                repository: env.novels,
                library: env.library,
                sources: const [],
                localBooks: local,
                localManagement: local,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.byKey(ValueKey(book.key)));
        await tester.pumpAndSettle();
        final sheet = find.byType(BottomSheet);
        expect(
          find.descendant(of: sheet, matching: find.text('epub')),
          findsOneWidget,
        );
        final reparse = find.descendant(
          of: sheet,
          matching: find.text('Reparse'),
        );
        expect(reparse, findsOneWidget);
        await tester.tap(reparse);
        await tester.pumpAndSettle();
        expect(local.called, isFalse);
        await tester.tap(find.widgetWithText(FilledButton, 'Reparse'));
        await tester.pumpAndSettle();
        expect(local.called, isTrue);
        expect(
          find.text('Reparsed. Your reading position is preserved.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('home menu opens offline content and local files', (
    tester,
  ) async {
    final env = FixtureEnvironment();
    final local = ReparseStore();
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => ReadingHome(
            repository: env.novels,
            library: env.library,
            sources: [env.source.descriptor],
            cache: Cache(),
            localBooks: local,
            localManagement: local,
            onImport: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final (label, screen) in [
      ('Offline content', CacheScreen),
      ('Local files', LocalBooksScreen),
    ]) {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget, reason: label);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(env.close);
  });
}

class _EpubReparseStore extends ReparseStore {
  @override
  Stream<Result<List<LocalBookInfo>>> watchBooks() => Stream.value(
    Success([
      LocalBookInfo(
        key: content.detail.summary.key,
        title: content.detail.summary.title,
        format: LocalBookFormat.epub,
        importedAt: DateTime.utc(2025),
      ),
    ]),
  );
}
