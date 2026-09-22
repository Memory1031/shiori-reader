import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/dev/ui/dev_app.dart';
import 'package:shiori/features/search/search_screen.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

import 'search_controller_test.dart' show Repository, sourceId, page;

Future<void> mount(
  WidgetTester tester,
  Repository repository, {
  String locale = 'en',
  String? sourceName,
  String? environmentLabel,
  double scale = 1,
  bool dark = false,
  AppRoutes routes = const AppRoutes(),
}) => tester.pumpWidget(
  MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: shioriTheme(dark ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: SearchScreen(
      repository: repository,
      sourceId: sourceId,
      routes: routes,
      sourceName: sourceName,
      environmentLabel: environmentLabel,
    ),
  ),
);

final input = find.byKey(const ValueKey('search-input'));
final submit = find.byKey(const ValueKey('search-submit'));
final more = find.byKey(const ValueKey('search-more'));

void main() {
  testWidgets('source label names the source unless environment overrides it', (
    tester,
  ) async {
    await mount(tester, Repository(), sourceName: 'Test library');
    await tester.pumpAndSettle();
    expect(find.text('Test library'), findsOneWidget);
    await mount(
      tester,
      Repository(),
      sourceName: 'Test library',
      environmentLabel: 'Offline fixture',
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline fixture'), findsOneWidget);
    expect(find.text('Test library'), findsNothing);
  });

  testWidgets(
    'hardware Enter submits; editing cancels and late results stay hidden',
    (tester) async {
      final repo = Repository();
      await mount(tester, repo);
      await tester.enterText(input, '拼音');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '拼音',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(repo.calls, isEmpty);
      await tester.enterText(input, 'old');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(repo.calls.length, 1);
      await tester.enterText(input, 'new');
      await tester.pump();
      expect(repo.calls.first.token.isCancelled, isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      repo.calls.last.pending.complete(Success(page(['current'])));
      await tester.pumpAndSettle();
      repo.calls.first.pending.complete(Success(page(['outdated'])));
      await tester.pumpAndSettle();
      expect(find.text('current'), findsOneWidget);
      expect(find.text('outdated'), findsNothing);
    },
  );

  testWidgets('dev menu opens real offline search with pagination', (
    tester,
  ) async {
    await tester.pumpWidget(createDevApp(locale: const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dev-search')));
    await tester.pumpAndSettle();
    await tester.enterText(input, 'a');
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      more,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'typing waits; button and keyboard submit, loading and empty differ',
    (tester) async {
      final repo = Repository();
      await mount(tester, repo);
      expect(find.text('Enter a keyword, then choose Search.'), findsOneWidget);
      await tester.enterText(input, ' first ');
      await tester.pump(const Duration(seconds: 1));
      expect(repo.calls, isEmpty);
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      expect(repo.calls.single.query, 'first');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.calls.last.pending.complete(Success(page([])));
      await tester.pumpAndSettle();
      expect(
        find.text('No novels found. Try another keyword.'),
        findsOneWidget,
      );
      await tester.enterText(input, 'second');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(repo.calls.length, 2);
      repo.calls.last.pending.complete(Success(page(['book'])));
      await tester.pumpAndSettle();
      expect(find.text('book'), findsOneWidget);
      expect(find.text('All results shown'), findsOneWidget);
    },
  );

  testWidgets(
    'pagination failure stays below results; explicit retry appends',
    (tester) async {
      final repo = Repository();
      await mount(tester, repo);
      await tester.enterText(input, 'query');
      await tester.pump();
      await tester.tap(submit);
      repo.calls.last.pending.complete(Success(page(['one'], next: 'next')));
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pump();
      expect(find.text('one'), findsOneWidget);
      repo.calls.last.pending.complete(
        Failure(
          AppFailure(
            kind: FailureKind.network,
            operation: Operation.search,
            retryPolicy: RetryPolicy.manual,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('one'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(repo.calls.length, 3);
      repo.calls.last.pending.complete(Success(page(['two'])));
      await tester.pumpAndSettle();
      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
      expect(find.text('All results shown'), findsOneWidget);
    },
  );

  testWidgets(
    'edit labels retained query and disables paging; correct opaque key navigates',
    (tester) async {
      final repo = Repository();
      final result = page(['same/title', 'other:opaque'], next: 'next');
      Object? selected;
      await mount(
        tester,
        repo,
        routes: AppRoutes(
          novel: (_, key) {
            selected = key;
            return const Scaffold(body: Text('destination'));
          },
        ),
      );
      await tester.enterText(input, 'old');
      await tester.pump();
      await tester.tap(submit);
      repo.calls.last.pending.complete(Success(result));
      await tester.pumpAndSettle();
      await tester.enterText(input, 'new');
      await tester.pump();
      expect(find.text('Results for “old”'), findsOneWidget);
      expect(more, findsNothing);
      await tester.tap(find.text('other:opaque'));
      await tester.pumpAndSettle();
      expect(selected, result.items.last.key);
      expect(find.text('destination'), findsOneWidget);
      Navigator.of(tester.element(find.text('destination'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Results for “old”'), findsOneWidget);
      expect(repo.calls.length, 1);
    },
  );

  for (final kind in [
    FailureKind.network,
    FailureKind.unsupported,
    FailureKind.accessRestricted,
  ]) {
    testWidgets('initial ${kind.name} failure respects retry policy', (
      tester,
    ) async {
      final repo = Repository();
      await mount(tester, repo);
      await tester.enterText(input, 'query');
      await tester.pump();
      await tester.tap(submit);
      repo.calls.last.pending.complete(
        Failure(
          AppFailure(
            kind: kind,
            operation: Operation.search,
            retryPolicy: kind == FailureKind.network
                ? RetryPolicy.manual
                : RetryPolicy.never,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Retry'),
        kind == FailureKind.network ? findsOneWidget : findsNothing,
      );
      expect(find.byType(TextField), findsOneWidget);
      if (kind == FailureKind.network) {
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(repo.calls.length, 2);
      }
      await tester.pumpWidget(const SizedBox());
      expect(repo.calls.last.token.isCancelled, kind == FailureKind.network);
    });
  }

  for (final locale in ['en', 'zh']) {
    testWidgets(
      '$locale small screen, keyboard and large text keep actions scrollable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final repo = Repository();
        await mount(
          tester,
          repo,
          locale: locale,
          scale: 2,
          dark: locale == 'zh',
        );
        await tester.enterText(input, 'long');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        await tester.ensureVisible(submit);
        await tester.pump();
        await tester.tap(submit);
        expect(repo.calls.length, 1);
        tester.view.resetViewInsets();
        repo.calls.last.pending.complete(
          Success(page([List.filled(12, '很长的书名 Long title').join()])),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(locale == 'en' ? 'Search' : '搜索'), findsWidgets);
      },
    );
  }
}
