import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';

import 'settings_test.dart' show Store;

void main() {
  testWidgets(
    'back closes visible toolbars before leaving the reader',
    (tester) async {
      final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          navigatorKey: navigator,
          routes: AppRoutes(home: (_) => const Scaffold()),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => BookReaderScreen(
            chapter: fixtureChapterKey(FixtureScenario.multiVolume),
            repository: env.novels,
            library: env.library,
            settings: Store()..value = ReaderSettings(controlsHintSeen: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reading settings'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsOneWidget);
      expect(find.byTooltip('Reading settings'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsNothing);
      expect(tester.takeException(), isNull);

      // The toolbar back button is an explicit exit, even with toolbars shown.
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => BookReaderScreen(
            chapter: fixtureChapterKey(FixtureScenario.multiVolume),
            repository: env.novels,
            library: env.library,
            settings: Store()..value = ReaderSettings(controlsHintSeen: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'system bars return when leaving starts, not after the transition',
    (tester) async {
      final modes = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            modes.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          navigatorKey: navigator,
          routes: AppRoutes(home: (_) => const Scaffold()),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => BookReaderScreen(
            chapter: fixtureChapterKey(FixtureScenario.multiVolume),
            repository: env.novels,
            library: env.library,
            settings: Store()..value = ReaderSettings(controlsHintSeen: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(modes, ['SystemUiMode.immersiveSticky']);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      for (var i = 0; i < 5 && modes.length < 2; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(modes.last, 'SystemUiMode.edgeToEdge');
      expect(find.byType(BookReaderScreen), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsNothing);
      expect(modes.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
