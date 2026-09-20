import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_completion_page.dart';
import 'package:shiori/features/reader/reader_completion_transition.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/viewport/paper_turn.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('reduced motion switches immediately and retains the reader', (
    tester,
  ) async {
    final visible = ValueNotifier(false);
    var turning = false;
    final bodyKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, end, _) => ReaderCompletionTransition(
              onTurning: (v) => turning = v,
              completion: end
                  ? const ColoredBox(color: Colors.white, child: Text('End'))
                  : null,
              child: Text('Last page', key: bodyKey),
            ),
          ),
        ),
      ),
    );
    final body = bodyKey.currentContext;
    visible.value = true;
    await tester.pump();
    expect(find.text('End'), findsOneWidget);
    expect(turning, isFalse);
    expect(find.byType(PaperTurnFold), findsNothing);
    expect(bodyKey.currentContext, same(body));
    visible.value = false;
    await tester.pump();
    expect(find.text('End'), findsNothing);
    expect(bodyKey.currentContext, same(body));
    await tester.pumpWidget(const SizedBox());
    visible.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets(
      'completion remains usable on narrow large-text ${dark ? 'dark' : 'warm'} paper',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var exits = 0, catalogs = 0, restarts = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: readerTheme(
              ReaderSettings(
                paper: ReaderPaper.warm,
                themeMode: dark ? ReaderThemeMode.dark : ReaderThemeMode.light,
              ),
              Brightness.light,
            ),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: ReaderCompletionPage(
                    state: BookTerminalState.currentEnd,
                    title: 'P.S.致对谎言微笑的你 第一卷 一段很长的书名',
                    style: TextStyle(
                      fontSize: 20,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPrevious: () {},
                    onExit: () => exits++,
                    onCatalog: () => catalogs++,
                    onRestart: () => restarts++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in ['返回书架', '查看目录', '重新阅读']) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
          await tester.pump();
        }
        expect([exits, catalogs, restarts], [1, 1, 1]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
