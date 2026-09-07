import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/home/reading_home.dart';

void main() {
  for (final supported in [false, true]) {
    testWidgets('home is local first, discover capability=$supported', (
      tester,
    ) async {
      final env = FixtureEnvironment();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => ReadingHome(
              repository: env.novels,
              library: env.library,
              sources: [
                SourceDescriptor(
                  sourceId: fixtureSourceId,
                  displayName: 'Fixture',
                  supportsDiscover: supported,
                  supportsSearchPaging: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(env.source.controls.calls, isEmpty);
      expect(find.text('Your bookshelf is empty.'), findsOneWidget);
      await tester.tap(find.text('Discover').last);
      await tester.pumpAndSettle();
      expect(
        env.source.controls.calls[Operation.discover] ?? 0,
        supported ? 1 : 0,
      );
      if (!supported) {
        expect(
          find.text(
            'This source has no recommendations. Use Search to find a novel.',
          ),
          findsOneWidget,
        );
      }
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-input')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(env.close);
    });
  }
  testWidgets('discover error has retry and leaves local shelf usable', (
    tester,
  ) async {
    final env = FixtureEnvironment();
    env.source.controls.failNext(
      AppFailure(
        kind: FailureKind.network,
        operation: Operation.discover,
        retryPolicy: RetryPolicy.manual,
      ),
    );
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => ReadingHome(
            repository: env.novels,
            library: env.library,
            sources: [env.source.descriptor],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discover').last);
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(env.source.controls.calls[Operation.discover], 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(env.close);
  });
}
