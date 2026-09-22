import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

void main() {
  for (final locale in ['en', 'zh']) {
    testWidgets('$locale narrow large text keeps home and search usable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final env = FixtureEnvironment();
      await env.library.putBookshelf(
        BookshelfEntry(
          snapshot: env.source.data.summary(FixtureScenario.longTitle),
          addedAt: DateTime.now(),
        ),
        cancellation: CancellationSource().token,
      );
      await tester.pumpWidget(
        ShioriApp(
          locale: Locale(locale),
          homeBuilder: (context, _) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: ReadingHome(
              repository: env.novels,
              library: env.library,
              sources: [env.source.descriptor],
              environmentLabel: AppLocalizations.of(context).offlineEnvironment,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(
          ValueKey(env.source.data.summary(FixtureScenario.longTitle).key),
        ),
        100,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('shelf-grid')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.longPressAt(
        tester.getTopLeft(
              find.byKey(
                ValueKey(
                  env.source.data.summary(FixtureScenario.longTitle).key,
                ),
              ),
            ) +
            const Offset(30, 30),
      );
      await tester.pumpAndSettle();
      final remove = locale == 'zh' ? '移出书架' : 'Remove from bookshelf';
      await tester.tap(find.text(remove));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final search = locale == 'zh' ? '搜索' : 'Search';
      await tester.tap(find.byTooltip(search));
      await tester.pumpAndSettle();
      expect(
        find.text(
          locale == 'zh' ? '离线演示 · 仅含测试书籍' : 'Offline demo · sample books only',
        ),
        findsOneWidget,
      );
      expect(env.source.controls.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(env.close);
    });
  }
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
                  displayName: 'LightNovel.fun',
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
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Discover'), findsNothing);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-input')), findsOneWidget);
      expect(find.text('Online source'), findsNothing);
      expect(find.text('LightNovel.fun'), findsOneWidget);
      expect(env.source.controls.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(env.close);
    });
  }
}
