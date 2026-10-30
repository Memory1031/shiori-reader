import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/shared/widgets/desktop_content_frame.dart';
import 'package:shiori/shared/widgets/shiori_panel.dart';

void main() {
  testWidgets(
    'one entry chooses compact sheets, app dialogs and reader sides',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      final themes = ValueNotifier(Colors.amber);
      addTearDown(themes.dispose);
      final root = GlobalKey<NavigatorState>();
      final nested = GlobalKey<NavigatorState>();
      ModalRoute<int>? route;
      int? result;
      var opens = 0, themeBuilds = 0;
      Future<void> mount(double width, ShioriPanelSide? side) async {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: root,
            home: Navigator(
              key: nested,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      opens++;
                      result = await showShioriPanel<int>(
                        context,
                        side: side,
                        themeChanges: themes,
                        theme: (_) {
                          themeBuilds++;
                          return ThemeData(
                            scaffoldBackgroundColor: themes.value,
                            dialogTheme: DialogThemeData(
                              backgroundColor: themes.value,
                            ),
                          );
                        },
                        builder: (context) {
                          route = ModalRoute.of<int>(context);
                          return StatefulBuilder(
                            builder: (context, setState) => SizedBox(
                              height: 160,
                              child: TextButton(
                                onPressed: () => Navigator.pop(context, 7),
                                child: Text('Close $opens'),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(route!.navigator, root.currentState);
        expect(nested.currentState!.canPop(), isFalse);
        final surface = find
            .ancestor(
              of: find.text('Close $opens'),
              matching: find.byType(Material),
            )
            .first;
        expect(
          Theme.of(tester.element(surface)).scaffoldBackgroundColor,
          Colors.amber,
        );
        themes.value = Colors.blue;
        await tester.pump();
        expect(
          Theme.of(tester.element(surface)).scaffoldBackgroundColor,
          Colors.blue,
        );
        if (width >= 840 && side == null) {
          final material = find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first;
          expect(tester.widget<Material>(material).color, Colors.blue);
        }
      }

      for (final (width, side) in [
        (390.0, null),
        (390.0, ShioriPanelSide.end),
        (900.0, null),
        (900.0, ShioriPanelSide.start),
        (900.0, ShioriPanelSide.end),
      ]) {
        themes.value = Colors.amber;
        await mount(width, side);
        expect(
          find.byType(BottomSheet),
          width < 840 ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(Dialog),
          width >= 840 && side == null ? findsOneWidget : findsNothing,
        );
        if (side != null && width >= 840) {
          final rect = tester.getRect(
            find.byKey(const ValueKey('reader-panel')),
          );
          expect(
            side == ShioriPanelSide.start ? rect.left : width - rect.right,
            ShioriSidePanelRoute.margin,
          );
        }
        final state = tester.state(find.byType(StatefulBuilder).last);
        tester.view.physicalSize = Size(width < 840 ? 1000 : 390, 800);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(StatefulBuilder).last), same(state));
        expect(
          find.byType(BottomSheet),
          width < 840 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close $opens'));
        await tester.pumpAndSettle();
        expect(result, 7);
        final buildsAfterClose = themeBuilds;
        themes.value = Colors.green;
        await tester.pump();
        expect(themeBuilds, buildsAfterClose);
        await tester.pumpWidget(const SizedBox());
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'shell logical width and dismissal guards reach the factory',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view
        ..physicalSize = const Size(2400, 1600)
        ..devicePixelRatio = 2;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopLayoutScope(
            width: 839,
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showShioriPanel<void>(
                    context,
                    dismissible: false,
                    builder: (context) => SizedBox(
                      height: 160,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Finish'),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Finish'), findsOneWidget);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
