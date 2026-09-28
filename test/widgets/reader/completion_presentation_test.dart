import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_chrome.dart';
import 'package:shiori/features/reader/reader_completion_page.dart';
import 'package:shiori/features/reader/reader_completion_transition.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/viewport/page_turn.dart';
import 'package:shiori/features/reader/viewport/paper_turn.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'settings_test.dart' show Store;

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'completion status follows its page at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const battery = MethodChannel('dev.fluttercommunity.plus/battery');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          battery,
          (call) async => switch (call.method) {
            'getBatteryLevel' => 82,
            'getBatteryState' => 'discharging',
            _ => throw MissingPluginException(),
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            battery,
            null,
          ),
        );
        final completion = ValueNotifier<BookTerminalState?>(null);
        final chrome = ValueNotifier(false);
        addTearDown(completion.dispose);
        addTearDown(chrome.dispose);
        final settings = Store()
          ..value = ReaderSettings(
            controlsHintSeen: true,
            horizontalPadding: 30,
          );
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  alwaysUse24HourFormat: true,
                  padding: const EdgeInsets.only(top: 24, bottom: 20),
                ),
                child: ValueListenableBuilder<BookTerminalState?>(
                  valueListenable: completion,
                  builder: (context, value, _) => ReaderContentView(
                    content: ChapterContent(
                      key: fixtureChapterKey(FixtureScenario.shortChapter),
                      title: 'Last chapter',
                      blocks: [ParagraphBlock(text: 'Last page.')],
                    ),
                    runningTitle: 'Book',
                    settings: settings,
                    chrome: chrome,
                    completion: value,
                    actions: ReaderActions(
                      completionPrevious: () => completion.value = null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final immersive = defaultTargetPlatform != TargetPlatform.windows;
        final status = find.byType(ReaderStatusRow);
        final progress = find.textContaining(RegExp(r'^Chapter \d+%$'));
        expect(progress, findsOneWidget);
        Rect? ordinaryStatus;
        if (immersive) ordinaryStatus = tester.getRect(status);

        for (final state in [
          BookTerminalState.finished,
          BookTerminalState.caughtUp,
          BookTerminalState.currentEnd,
        ]) {
          completion.value = state;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          final endLayer = find.byKey(const ValueKey('completion-end-layer'));
          if (immersive) {
            expect(
              find.descendant(of: endLayer, matching: status),
              findsOneWidget,
            );
            expect(
              find.ancestor(of: status, matching: find.byType(PageTurnSlot)),
              findsOneWidget,
            );
          }
          await tester.pumpAndSettle();
          expect(find.byType(ReaderCompletionPage), findsOneWidget);
          expect(find.byType(ReaderRunningChrome), findsNothing);
          expect(progress, findsNothing);
          expect(status, immersive ? findsOneWidget : findsNothing);
          if (immersive) {
            expect(tester.getRect(status), ordinaryStatus);
            expect(
              find.textContaining(RegExp(r'\d{1,2}:\d{2}')),
              findsOneWidget,
            );
            expect(find.text('82%'), findsOneWidget);
            expect(
              find.descendant(of: status, matching: find.byType(CustomPaint)),
              findsOneWidget,
            );
            expect(
              tester.widget<ReaderStatusRow>(status).progress,
              isA<SizedBox>(),
            );
          } else {
            expect(find.text('82%'), findsNothing);
          }
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          if (immersive) {
            expect(
              find.descendant(of: endLayer, matching: status),
              findsOneWidget,
            );
          }
          await tester.pumpAndSettle();
          expect(find.byType(ReaderCompletionPage), findsNothing);
          expect(find.byType(ReaderRunningChrome), findsOneWidget);
          expect(progress, findsOneWidget);
          expect(status, immersive ? findsOneWidget : findsNothing);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
      }),
    );
  }

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
