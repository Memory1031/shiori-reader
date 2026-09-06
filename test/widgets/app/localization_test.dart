import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/app_controller.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/shared/widgets/app_scaffold.dart';
import 'package:shiori/shared/widgets/state_views.dart';

import '../../support/contract_fakes.dart';

void main() {
  test(
    'ARB languages have matching nonempty messages, without silent fallback',
    () {
      Map<String, dynamic> messages(String locale) =>
          (jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
                as Map<String, dynamic>)
            ..removeWhere((key, _) => key.startsWith('@'));
      final english = messages('en');
      final chinese = messages('zh');
      expect(chinese.keys.toSet(), english.keys.toSet());
      expect(english, isNotEmpty);
      for (final entries in [english, chinese]) {
        expect(
          entries.values.every(
            (value) => value is String && value.trim().isNotEmpty,
          ),
          isTrue,
        );
      }
    },
  );

  testWidgets(
    'system language preferences resolve Chinese, English and fallback',
    (tester) async {
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final cases = <(List<Locale>, String, String)>[
        ([const Locale('zh', 'CN')], 'zh', '阅读功能正在准备中。'),
        (
          [
            const Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hant',
              countryCode: 'TW',
            ),
          ],
          'zh',
          '阅读功能正在准备中。',
        ),
        ([const Locale('en', 'GB')], 'en', 'Reading features are coming soon.'),
        ([const Locale('fr'), const Locale('zh')], 'zh', '阅读功能正在准备中。'),
        ([const Locale('fr')], 'en', 'Reading features are coming soon.'),
      ];
      for (final (preferences, language, message) in cases) {
        tester.platformDispatcher.localesTestValue = preferences;
        await tester.pumpWidget(ShioriApp(key: UniqueKey()));
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(AppScaffold));
        expect(Localizations.localeOf(context).languageCode, language);
        expect(find.text(message), findsOneWidget);
        expect(
          MaterialLocalizations.of(context).backButtonTooltip,
          language == 'zh' ? '返回' : 'Back',
        );
        expect(
          CupertinoLocalizations.of(context).backButtonLabel,
          language == 'zh' ? '返回' : 'Back',
        );
      }
    },
  );

  testWidgets(
    'locale property updates existing route without recreating app controller',
    (tester) async {
      var created = 0;
      late AppController controller;
      late BuildContext homeContext;
      const routes = AppRoutes();
      Widget app(Locale locale) => ShioriApp(
        locale: locale,
        createController: () {
          created++;
          return controller = AppController();
        },
        routes: AppRoutes(
          home: (context) {
            homeContext = context;
            return const Text('Shiori');
          },
        ),
      );
      await tester.pumpWidget(app(const Locale('zh')));
      unawaited(routes.open(homeContext, NovelDestination(contractNovel)));
      await tester.pumpAndSettle();
      expect(find.text('小说详情'), findsOneWidget);
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.text('Novel details'), findsOneWidget);
      expect(
        find.text('This feature is still in development.'),
        findsOneWidget,
      );
      expect(created, 1);
      expect(controller.isClosed, isFalse);
      expect(
        Navigator.of(tester.element(find.text('Novel details'))).canPop(),
        isTrue,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Shiori'), findsOneWidget);
      expect(created, 1);
    },
  );

  testWidgets('system locale changes refresh an already open route', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const ShioriApp());
    final context = tester.element(find.byType(AppScaffold));
    unawaited(
      const AppRoutes().open(context, ReaderDestination(contractChapter)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reader'), findsOneWidget);
    tester.platformDispatcher.localesTestValue = [const Locale('zh')];
    await tester.pumpAndSettle();
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('此功能尚在开发中。'), findsOneWidget);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
      '${locale.languageCode} errors, actions and loading fit large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var retries = 0;
        for (final kind in FailureKind.values) {
          final failure = AppFailure(
            kind: kind,
            operation: Operation.chapter,
            retryPolicy: kind == FailureKind.network
                ? RetryPolicy.manual
                : RetryPolicy.never,
          );
          await tester.pumpWidget(
            ShioriApp(
              locale: locale,
              routes: AppRoutes(
                home: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: AppScaffold(
                    title: 'Shiori',
                    body: FailureView(
                      failure: failure,
                      onRetry: () => retries++,
                      onBack: () {},
                      onReadCache: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (kind == FailureKind.network) {
            expect(
              find.text(
                locale.languageCode == 'zh'
                    ? '无法连接，请检查网络后重试。'
                    : 'Unable to connect. Check your network and try again.',
              ),
              findsOneWidget,
            );
            final retry = find.text(
              locale.languageCode == 'zh' ? '重试' : 'Retry',
            );
            await tester.ensureVisible(retry);
            await tester.tap(retry);
          }
          expect(tester.takeException(), isNull, reason: kind.name);
          if (locale.languageCode == 'en') {
            expect(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    RegExp(r'[\u4e00-\u9fff]').hasMatch(widget.data ?? ''),
              ),
              findsNothing,
            );
          }
        }
        expect(retries, 1);
        await tester.pumpWidget(
          ShioriApp(
            locale: locale,
            routes: AppRoutes(
              home: (_) =>
                  const AppScaffold(title: 'Shiori', body: LoadingView()),
            ),
          ),
        );
        await tester.pump();
        final label = locale.languageCode == 'zh' ? '正在加载…' : 'Loading…';
        expect(find.text(label), findsOneWidget);
        expect(
          tester
              .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator),
              )
              .semanticsLabel,
          label,
        );
      },
    );
  }
}
