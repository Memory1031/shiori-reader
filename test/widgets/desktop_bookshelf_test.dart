import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/home/continue_reading_card.dart';
import 'package:shiori/app/theme.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/home/desktop_shell.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/widgets/book_cover.dart';

import 'reader/continue_test.dart' show seed;

void main() {
  for (final display in [
    (size: const Size(1280, 720), dpr: 1.0, textScale: 1.0),
    (size: const Size(1920, 1080), dpr: 1.0, textScale: 1.0),
    (size: const Size(2560, 1440), dpr: 1.0, textScale: 1.0),
    (size: const Size(2560, 1440), dpr: 1.5, textScale: 1.0),
    (size: const Size(2560, 1440), dpr: 2.0, textScale: 1.6),
  ]) {
    for (final language in ['zh', 'en']) {
      testWidgets(
        'desktop shelf layout ${display.size} DPR ${display.dpr} $language',
        (tester) async {
          tester.view
            ..physicalSize = display.size
            ..devicePixelRatio = display.dpr;
          addTearDown(tester.view.reset);
          final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
          final token = CancellationSource().token;
          for (var i = 0; i < 60; i++) {
            await env.library.putBookshelf(
              BookshelfEntry(
                snapshot: NovelSummary(
                  key: i.isEven
                      ? LocalBookIdentity.book(
                          i.toRadixString(16).padLeft(64, '0'),
                        )
                      : NovelKey(sourceId: SourceId('fixture'), novelId: '$i'),
                  title: '$i ${'很长的中文书名 Long English book title ' * 3}',
                  authors: ['${'Long author name 作者 ' * 4}$i'],
                ),
                addedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
              ),
              cancellation: token,
            );
          }
          await seed(env, fixtureChapterKey(FixtureScenario.multiVolume));
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: appTheme(
                language == 'zh' ? Brightness.light : Brightness.dark,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(display.textScale)),
                child: child!,
              ),
              home: ReadingHome(
                repository: env.novels,
                library: env.library,
                sources: [env.source.descriptor],
                settings: env.settings,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final shelf = find.byType(BookshelfView);
          final l = AppLocalizations.of(tester.element(shelf));
          final logicalWidth = display.size.width / display.dpr;
          ShellLayout layout() => tester
              .widget<ShellNavigation>(find.byType(ShellNavigation))
              .layout;
          // Centred in the workspace beside the navigation, not the window.
          final workspace = find.ancestor(
            of: shelf,
            matching: find.byType(Scaffold),
          );
          expect(layout(), shellLayoutFor(logicalWidth));
          final shelfRect = tester.getRect(shelf);
          expect(shelfRect.width, lessThanOrEqualTo(840.01));
          expect(
            shelfRect.center.dx,
            closeTo(tester.getRect(workspace).center.dx, .01),
          );
          expect(
            tester.getRect(workspace).left,
            closeTo(
              logicalWidth >= ShioriLayout.sidebarBreakpoint
                  ? ShioriLayout.sidebar
                  : ShioriLayout.rail,
              .01,
            ),
          );
          expect(find.text(l.detailContinue), findsOneWidget);

          final covers = find.descendant(
            of: shelf,
            matching: find.byType(BookCover),
          );
          // The continue card scrolls inside the shelf; measure grid covers only.
          final cardCovers = find
              .descendant(
                of: find.byType(ContinueReadingCard),
                matching: find.byType(BookCover),
              )
              .evaluate()
              .toSet();
          final coverRects = covers
              .evaluate()
              .where((e) => !cardCovers.contains(e))
              .map((e) => tester.getRect(find.byWidget(e.widget)))
              .toList();
          expect(coverRects.length, inInclusiveRange(4, 59));
          expect(
            coverRects
                .where((r) => (r.top - coverRects.first.top).abs() < 1)
                .length,
            greaterThanOrEqualTo(4),
          );
          for (final rect in coverRects) {
            expect(rect.width, inExclusiveRange(0, 200));
            expect(rect.height / rect.width, closeTo(1.5, .01));
            expect(rect.left, greaterThanOrEqualTo(shelfRect.left));
            expect(rect.right, lessThanOrEqualTo(shelfRect.right));
          }
          expect(tester.takeException(), isNull);
          final scrollable = find.descendant(
            of: shelf,
            matching: find.byType(Scrollable),
          );
          final scrollState = tester.state<ScrollableState>(scrollable);
          await tester.sendEventToBinding(
            PointerScrollEvent(
              kind: PointerDeviceKind.mouse,
              position: tester.getCenter(shelf),
              scrollDelta: const Offset(0, 500),
            ),
          );
          await tester.pumpAndSettle();
          expect(scrollState.position.pixels, greaterThan(0));
          scrollState.position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip(l.shelfList));
          await tester.pumpAndSettle();
          expect(find.byType(SliverGrid), findsNothing);
          expect(find.byTooltip(l.shelfGrid), findsOneWidget);
          expect(tester.takeException(), isNull);
          // Resizing preserves the chosen mode and supports narrow windows.
          for (final width in [390.0, logicalWidth]) {
            tester.view.physicalSize = Size(
              width * display.dpr,
              display.size.height,
            );
            await tester.pumpAndSettle();
            expect(layout(), shellLayoutFor(width));
            expect(find.byTooltip(l.shelfGrid), findsOneWidget);
            expect(tester.getSize(shelf).width, lessThanOrEqualTo(width));
            for (final element in find.byType(ListTile).evaluate()) {
              expect(
                tester.getSize(find.byWidget(element.widget)).width,
                lessThanOrEqualTo(840),
              );
            }
            expect(tester.takeException(), isNull);
          }
          await tester.tap(find.byTooltip(l.shelfGrid));
          await tester.pumpAndSettle();
          expect(find.byType(SliverGrid), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await tester.runAsync(env.close);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  }
}
