import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_chrome.dart';

import 'settings_test.dart' show Store;

void main() {
  late List<bool> calls;
  setUp(() {
    calls = [];
    ReaderSystemUi.keepAwake = (enable) async => calls.add(enable);
  });
  tearDown(() => ReaderSystemUi.keepAwake = (_) async {});

  test('nested readers hold the screen on until the outermost leaves', () {
    ReaderSystemUi.enter();
    ReaderSystemUi.enter();
    ReaderSystemUi.exit();
    expect(calls, [true]);
    ReaderSystemUi.exit();
    expect(calls, [true, false]);
    // An unmatched exit cannot release a lock it does not hold.
    ReaderSystemUi.exit();
    expect(calls, [true, false]);
  });

  test('a refused wake lock does not escape', () async {
    ReaderSystemUi.keepAwake = (_) async => throw PlatformException(code: 'x');
    ReaderSystemUi.enter();
    ReaderSystemUi.exit();
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets(
    'the screen stays on only while a touch reader is open',
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
      expect(calls, isEmpty);
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
      expect(calls, [true]);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsNothing);
      expect(calls, [true, false]);
      await tester.pumpWidget(const SizedBox());
      await env.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'desktop readers leave screen sleep to the system',
    (tester) async {
      final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: fixtureChapterKey(FixtureScenario.multiVolume),
              repository: env.novels,
              library: env.library,
              settings: Store()..value = ReaderSettings(controlsHintSeen: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await env.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
