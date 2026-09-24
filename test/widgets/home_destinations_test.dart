import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/features/cache/cache_screen.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/local_books/local_books_screen.dart';

import 'cache_screen_test.dart' show Cache;
import 'local_reparse_test.dart' show ReparseStore;

void main() {
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
