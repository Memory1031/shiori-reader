import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/dev/ui/dev_app.dart';
import 'package:shiori/dev/ui/scenario_page.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/domain/contracts/contracts.dart';

void main() {
  test('startup accepts only stable scenario IDs and empty opens menu', () {
    expect(parseDevScenario(''), isNull);
    for (final scenario in FixtureScenario.values) {
      expect(parseDevScenario(scenario.name), scenario);
    }
    expect(() => createDevApp(scenarioId: 'typo'), throwsArgumentError);
    expect(() => parseDevScenario(' shortChapter '), throwsArgumentError);
  });

  test('production import graph excludes dev code and dev-only entry', () {
    final root = Directory.current.uri;
    final seen = <Uri>{};
    void visit(Uri file) {
      if (!seen.add(file)) return;
      final path = file.path;
      expect(path, isNot(contains('/lib/dev/')));
      expect(path, isNot(endsWith('/main_dev.dart')));
      final code = File.fromUri(file).readAsStringSync();
      expect(code, isNot(contains('/dev/scenario')));
      for (final match in RegExp(
        r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
        multiLine: true,
      ).allMatches(code)) {
        final uri = match[1]!;
        if (uri.startsWith('dart:')) continue;
        if (uri.startsWith('package:shiori/')) {
          visit(root.resolve('lib/${uri.substring('package:shiori/'.length)}'));
        } else if (!uri.startsWith('package:')) {
          visit(file.resolve(uri));
        }
      }
    }

    visit(root.resolve('lib/main.dart'));
    expect(seen.length, greaterThan(10));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = pubspec.substring(pubspec.indexOf('  assets:'));
    expect(assets, isNot(contains('fixture')));
    expect(assets, isNot(contains('dev/')));
    for (final file in Directory('lib/dev/ui').listSync().whereType<File>()) {
      expect(
        file.readAsStringSync(),
        isNot(matches(r'''import ['"](?:dart:io|package:(?:dio|http)/)''')),
      );
    }
  });

  testWidgets('menu follows locale and opening/back retains menu', (
    tester,
  ) async {
    await tester.pumpWidget(createDevApp(locale: const Locale('zh')));
    expect(find.text('Shiori DEV'), findsOneWidget);
    expect(find.text('普通短章'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shortChapter')));
    await tester.pumpAndSettle();
    expect(find.byType(DevScenarioPage), findsOneWidget);
    expect(find.textContaining('"blocks": 8'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Shiori DEV'), findsOneWidget);
    await tester.pumpWidget(createDevApp(locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Short chapter'), findsOneWidget);
  });

  testWidgets(
    'specified scenario opens once, can return to menu, locale preserves route',
    (tester) async {
      await tester.pumpWidget(
        createDevApp(
          scenarioId: 'extremeParagraph',
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('"characters": 100000'), findsOneWidget);
      expect(find.text('Extreme single paragraph'), findsOneWidget);
      await tester.pumpWidget(
        createDevApp(
          scenarioId: 'extremeParagraph',
          locale: const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('极端单段'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(DevScenarioPage), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Shiori DEV'), findsOneWidget);
    },
  );

  testWidgets('empty and repeated-page search are reachable through controls', (
    tester,
  ) async {
    for (final scenario in ['emptySearch', 'repeatedCursor']) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        createDevApp(scenarioId: scenario, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pumpAndSettle();
      if (scenario == 'emptySearch') {
        expect(find.textContaining('"results": 0'), findsOneWidget);
        expect(find.text('Load more'), findsNothing);
      } else {
        final more = find.text('Load more');
        await tester.ensureVisible(more);
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'The content format may have changed and cannot be read right now.',
          ),
          findsOneWidget,
        );
      }
    }
  });

  testWidgets(
    'catalog selection and revision use existing repository contracts',
    (tester) async {
      await tester.pumpWidget(
        createDevApp(scenarioId: 'revisedContent', locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      final before = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data;
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('revision=1').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        isNot(before),
      );
      expect(find.textContaining('Revision 1'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Contents'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"catalogRevision"'), findsOneWidget);
      final chapter = find.byType(ListTile).first;
      await tester.ensureVisible(chapter);
      await tester.tap(chapter);
      await tester.pumpAndSettle();
      expect(find.textContaining('"contentRevision"'), findsOneWidget);
    },
  );

  testWidgets(
    'image stream failure is retryable and navigation releases bodies',
    (tester) async {
      final env = FixtureEnvironment(scenario: FixtureScenario.failingImage);
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => DevScenarioPage(
              scenario: FixtureScenario.failingImage,
              createEnvironment: (_) => env,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final retry = find.widgetWithText(FilledButton, 'Retry');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(env.source.controls.calls[Operation.media], 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(env.source.activeBodies, 0);
    },
  );

  testWidgets('leaving a delayed load cancels work without late setState', (
    tester,
  ) async {
    final env = FixtureEnvironment();
    env.source.controls.delays[Operation.chapter] = const Duration(seconds: 30);
    await tester.pumpWidget(
      ShioriApp(
        routes: AppRoutes(
          home: (_) => DevScenarioPage(
            scenario: FixtureScenario.shortChapter,
            createEnvironment: (_) => env,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(env.source.activeBodies, 0);
  });
}
